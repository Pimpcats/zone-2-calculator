import Foundation
import SwiftUI
import UIKit
import UserNotifications

/// Owns the live session: heart rate (BLE strap) + distance/pace (GPS) + duration,
/// calories, time-in-zone, the HR history for the graph, peak HR, and the alert band.
final class WorkoutViewModel: ObservableObject {

    // Live metrics
    @Published var bpm: Int? = nil
    @Published var currentZone: Int = 0
    @Published var peakBpm: Int = 0
    @Published var lowBpm: Int = 0     // lowest reading seen (for resting-HR measurement)
    @Published var duration: TimeInterval = 0
    @Published var calories: Double = 0
    @Published var timeInZone: [Double] = Array(repeating: 0, count: 6)   // 0 = below Z1, 1...5 = zones
    @Published var hrHistory: [Int] = []
    @Published var active = false
    @Published var notifStatus: String = "Checking…"

    // 5-minute resting-HR test
    @Published var restingTesting = false
    @Published var restingRemaining = 0      // seconds left
    @Published var restingLow = 0            // lowest HR seen during the test
    @Published var restingResult = 0         // final resting HR after the test
    private var restingTimer: Timer?
    private let restingTestLength = 300

    // Settings (pushed in from the persisted @AppStorage values)
    private(set) var age: Int = 40
    private(set) var isMale: Bool = true
    private(set) var weightKg: Double = 75
    private(set) var restingHR: Int = 60
    private(set) var bandZone: Int = 2         // the zone you want to stay inside
    private(set) var mhrOverride: Int? = nil   // measured Max HR (from VO2 test), if locked in
    private(set) var manualFloor: Int? = nil   // direct bpm floor (manual band mode)
    private(set) var manualCeiling: Int? = nil // direct bpm ceiling (manual band mode)
    private(set) var useHRR: Bool = false      // Heart-Rate Reserve (adaptive) zone math

    // OwnZone-style HRV warm-up test
    @Published var ownzoneTesting = false
    @Published var ownzoneRemaining = 0
    @Published var ownzoneRMSSD: Double = 0      // current HRV (ms)
    @Published var ownzoneBaseline: Double = 0   // highest HRV seen (easy effort)
    @Published var ownzoneThresholdHR = 0        // detected aerobic threshold HR
    private var ownzoneTimer: Timer?
    private var rrBuffer: [Double] = []
    private var ownzoneBelowSince: Date?
    private let ownzoneLength = 300

    let hrm = HeartRateManager()
    let loc = LocationTracker()

    /// History store, injected from the app, used for auto-save on disconnect.
    var store: WorkoutStore?

    private var timer: Timer?
    private var startDate: Date?
    private var accumulated: TimeInterval = 0
    private var lastHRDate: Date?
    private var hrSum = 0
    private var hrCount = 0
    private var sessionSaved = false
    private var disconnectWork: DispatchWorkItem?

    var avgBpm: Int { hrCount > 0 ? hrSum / hrCount : 0 }

    /// Snapshot of the current session for saving to history.
    func makeRecord() -> WorkoutRecord {
        WorkoutRecord(date: Date(), duration: duration, distanceMiles: distanceMiles,
                      calories: calories, avgBpm: avgBpm, peakBpm: peakBpm, timeInZone: timeInZone)
    }

    init() {
        hrm.onReading = { [weak self] bpm in self?.ingest(bpm: bpm) }
        hrm.onDisconnect = { [weak self] in self?.scheduleAutoSave() }
        hrm.onReconnect = { [weak self] in self?.cancelAutoSave() }
    }

    // MARK: - Auto-save (never lose a workout)

    /// Strap dropped: if a real workout is running, save it after a short grace
    /// period (in case it auto-reconnects). Cancelled if it reconnects in time.
    private func scheduleAutoSave() {
        guard active else { return }
        disconnectWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.autoSaveIfNeeded() }
        disconnectWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 25, execute: work)
    }

    private func cancelAutoSave() {
        disconnectWork?.cancel()
        disconnectWork = nil
    }

    /// Save the current session to history once (if it's substantial), then pause.
    @discardableResult
    func autoSaveIfNeeded() -> Bool {
        guard !sessionSaved, duration >= 60, let store = store else { return false }
        let rec = makeRecord()
        store.add(rec)
        sessionSaved = true
        if active { pause() }
        notifyAutoSaved(rec.duration)
        return true
    }

    private func notifyAutoSaved(_ dur: TimeInterval) {
        let c = UNMutableNotificationContent()
        c.title = "Workout auto-saved"
        c.body = "Strap disconnected — your \(WorkoutViewModel.clock(dur)) workout was saved to Progress."
        c.sound = .default
        UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: UUID().uuidString, content: c, trigger: nil))
    }

    /// Apply persisted settings and recompute the alert band.
    func apply(age: Int, isMale: Bool, weightKg: Double, restingHR: Int,
               bandZone: Int, mhrOverride: Int?, manualFloor: Int?, manualCeiling: Int?,
               useHRR: Bool) {
        self.age = age
        self.isMale = isMale
        self.weightKg = weightKg
        self.restingHR = max(30, restingHR)
        self.bandZone = bandZone
        self.mhrOverride = mhrOverride
        self.manualFloor = manualFloor
        self.manualCeiling = manualCeiling
        self.useHRR = useHRR
        hrm.floorBpm = floorBpm
        hrm.ceilingBpm = ceilingBpm
        objectWillChange.send()
    }

    // Derived values
    var mhr: Int { mhrOverride ?? Zones.mhr(age: age) }
    var usingMeasuredMax: Bool { mhrOverride != nil }
    var usingManualBand: Bool { manualFloor != nil || manualCeiling != nil }
    var floorBpm: Int {
        if let m = manualFloor { return m }
        return useHRR ? Zones.lowerBpmHRR(zone: bandZone, mhr: mhr, rest: restingHR)
                      : Zones.lowerBpm(zone: bandZone, mhr: mhr)
    }
    var ceilingBpm: Int {
        if let m = manualCeiling { return m }
        return useHRR ? Zones.upperBpmHRR(zone: bandZone, mhr: mhr, rest: restingHR)
                      : Zones.upperBpm(zone: bandZone, mhr: mhr)
    }

    var distanceMiles: Double { loc.distanceMeters / 1609.344 }
    var paceSecPerMile: Double? {
        guard distanceMiles > 0.02, duration > 0 else { return nil }
        return duration / distanceMiles
    }
    var connected: Bool { hrm.connected }
    var bluetoothReady: Bool { hrm.bluetoothReady }
    var statusText: String { hrm.statusText }

    /// Cooper/Uth heart-rate-ratio VO2max estimate: 15.3 × (HRmax / HRrest).
    func vo2maxEstimate(usingMax hrMax: Int) -> Double {
        guard restingHR > 0, hrMax > 0 else { return 0 }
        return 15.3 * Double(hrMax) / Double(restingHR)
    }

    // MARK: - Session control

    func connect() { hrm.startScanning() }
    func disconnectStrap() {
        cancelAutoSave()
        autoSaveIfNeeded()      // user took the strap off — save what they did
        hrm.disconnect()
    }

    func start() {
        active = true
        sessionSaved = false
        startDate = Date().addingTimeInterval(-accumulated)
        lastHRDate = Date()
        loc.start()
        startTimer()
    }

    func pause() {
        active = false
        accumulated = duration
        loc.pause()
        timer?.invalidate()
        lastHRDate = nil
    }

    func reset() {
        active = false
        accumulated = 0
        duration = 0
        calories = 0
        timeInZone = Array(repeating: 0, count: 6)
        hrHistory = []
        peakBpm = 0
        hrSum = 0
        hrCount = 0
        sessionSaved = false
        cancelAutoSave()
        startDate = nil
        lastHRDate = nil
        loc.reset()
        timer?.invalidate()
    }

    func resetPeak() { peakBpm = 0 }
    func resetLow() { lowBpm = 0 }

    // MARK: - 5-minute resting-HR test

    func startRestingTest() {
        restingTesting = true
        restingRemaining = restingTestLength
        restingLow = 0
        restingResult = 0
        restingTimer?.invalidate()
        let t = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in self?.restingTick() }
        RunLoop.main.add(t, forMode: .common)
        restingTimer = t
    }

    func cancelRestingTest() {
        restingTesting = false
        restingTimer?.invalidate()
        restingTimer = nil
    }

    private func restingTick() {
        guard restingTesting else { return }
        restingRemaining -= 1
        if restingRemaining <= 0 {
            restingResult = restingLow
            cancelRestingTest()
        }
    }

    // MARK: - OwnZone-style HRV warm-up (aerobic-threshold detection)

    func startOwnzoneTest() {
        ownzoneTesting = true
        ownzoneRemaining = ownzoneLength
        ownzoneRMSSD = 0
        ownzoneBaseline = 0
        ownzoneThresholdHR = 0
        rrBuffer = []
        ownzoneBelowSince = nil
        hrm.onRR = { [weak self] rrs in self?.ingestRR(rrs) }
        ownzoneTimer?.invalidate()
        let t = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in self?.ownzoneTick() }
        RunLoop.main.add(t, forMode: .common)
        ownzoneTimer = t
    }

    func cancelOwnzoneTest() {
        ownzoneTesting = false
        ownzoneTimer?.invalidate()
        ownzoneTimer = nil
        hrm.onRR = nil
    }

    private func ownzoneTick() {
        guard ownzoneTesting else { return }
        ownzoneRemaining -= 1
        if ownzoneRemaining <= 0 {
            if ownzoneThresholdHR == 0, let b = bpm { ownzoneThresholdHR = b }
            cancelOwnzoneTest()
        }
    }

    /// Feed R-R intervals, track RMSSD, and detect where HRV collapses (≈ aerobic threshold).
    private func ingestRR(_ rrs: [Double]) {
        guard ownzoneTesting else { return }
        for rr in rrs where rr > 300 && rr < 2000 { rrBuffer.append(rr) }
        if rrBuffer.count > 40 { rrBuffer.removeFirst(rrBuffer.count - 40) }
        guard rrBuffer.count >= 8 else { return }

        var sum = 0.0, n = 0
        for i in 1..<rrBuffer.count {
            let d = rrBuffer[i] - rrBuffer[i - 1]
            sum += d * d; n += 1
        }
        let rmssd = n > 0 ? (sum / Double(n)).squareRoot() : 0
        ownzoneRMSSD = rmssd
        if rmssd > ownzoneBaseline { ownzoneBaseline = rmssd }

        // Threshold = HRV stays collapsed (low) for ~8s after a high-HRV baseline.
        if ownzoneThresholdHR == 0 {
            let collapsed = rmssd < max(12.0, ownzoneBaseline * 0.2)
            if collapsed && ownzoneBaseline > 20 {
                if let since = ownzoneBelowSince {
                    if Date().timeIntervalSince(since) >= 8, let b = bpm, b > 0 {
                        ownzoneThresholdHR = b
                    }
                } else {
                    ownzoneBelowSince = Date()
                }
            } else {
                ownzoneBelowSince = nil
            }
        }
    }

    // MARK: - Notifications / test alert

    /// Refresh the human-readable notification permission status shown in Settings.
    func refreshNotifStatus() {
        UNUserNotificationCenter.current().getNotificationSettings { s in
            DispatchQueue.main.async {
                switch s.authorizationStatus {
                case .authorized:   self.notifStatus = "On"
                case .provisional:  self.notifStatus = "On (quiet)"
                case .ephemeral:    self.notifStatus = "On"
                case .denied:       self.notifStatus = "Off — enable in iOS Settings"
                case .notDetermined: self.notifStatus = "Not yet allowed"
                @unknown default:   self.notifStatus = "Unknown"
                }
            }
        }
    }

    /// Run the test alert: immediate haptic + a notification. Calls `onDenied`
    /// (on the main thread) if the user must enable notifications in iOS Settings.
    func runTestAlert(onDenied: @escaping () -> Void) {
        UINotificationFeedbackGenerator().notificationOccurred(.warning)   // tactile confirmation
        let center = UNUserNotificationCenter.current()
        center.getNotificationSettings { s in
            switch s.authorizationStatus {
            case .authorized, .provisional, .ephemeral:
                self.hrm.sendTestAlert()
            case .notDetermined:
                center.requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
                    self.refreshNotifStatus()
                    if granted { self.hrm.sendTestAlert() }
                    else { DispatchQueue.main.async { onDenied() } }
                }
            case .denied:
                DispatchQueue.main.async { onDenied() }
            @unknown default:
                self.hrm.sendTestAlert()
            }
        }
    }

    func openSystemSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
        }
    }

    // MARK: - Data ingestion

    private func ingest(bpm value: Int) {
        bpm = value
        if value > peakBpm { peakBpm = value }
        if value >= 30 && (lowBpm == 0 || value < lowBpm) { lowBpm = value }
        if restingTesting && value >= 30 && (restingLow == 0 || value < restingLow) { restingLow = value }
        let z = Zones.zone(forBpm: value, mhr: mhr)
        currentZone = z
        guard active else { return }
        let now = Date()
        var dt: Double = 1
        if let last = lastHRDate {
            let delta = now.timeIntervalSince(last)
            if delta > 0 && delta < 10 { dt = delta }
        }
        lastHRDate = now
        timeInZone[z] += dt
        hrSum += value
        hrCount += 1
        addCalories(bpm: value, dt: dt)
        hrHistory.append(value)
        if hrHistory.count > 600 { hrHistory.removeFirst() }
    }

    /// HR-based calorie estimate (Keytel et al., 2005).
    private func addCalories(bpm: Int, dt: Double) {
        let hr = Double(bpm), a = Double(age), w = weightKg
        let perMin: Double = isMale
            ? (-55.0969 + 0.6309 * hr + 0.1988 * w + 0.2017 * a) / 4.184
            : (-20.4022 + 0.4472 * hr - 0.1263 * w + 0.0740 * a) / 4.184
        if perMin > 0 { calories += perMin * dt / 60.0 }
    }

    private func startTimer() {
        timer?.invalidate()
        let t = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    private func tick() {
        guard active, let s = startDate else { return }
        duration = Date().timeIntervalSince(s)
    }

    // MARK: - Formatting helpers

    static func clock(_ t: TimeInterval) -> String {
        let s = Int(t)
        return String(format: "%02d:%02d:%02d", s / 3600, (s % 3600) / 60, s % 60)
    }
    static func pace(_ secPerMile: Double?) -> String {
        guard let p = secPerMile, p.isFinite, p > 0 else { return "--:--" }
        let s = Int(p.rounded())
        return String(format: "%d:%02d", s / 60, s % 60)
    }
}
