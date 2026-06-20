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

    // 60-second heart-rate recovery test
    @Published var recoveryTesting = false
    @Published var recoveryRemaining = 0
    @Published var recoveryStartHR = 0
    @Published var recoveryResult = 0      // bpm dropped in 60s
    private var recoveryTimer: Timer?

    // Interval timer (VO2 / threshold intervals)
    @Published var intervalActive = false
    @Published var intervalIsWork = true
    @Published var intervalRemaining = 0
    @Published var intervalRound = 0
    private var intervalWorkSec = 120
    private var intervalRestSec = 120
    private var intervalRounds = 5
    private var intervalTimer: Timer?

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
    private var lastOwnzoneStage = -1
    @Published var ownzoneAlpha1: Double = 0          // DFA-α1 (≈0.75 = aerobic threshold)
    private var ownzoneAlphaBaseline: Double = 0
    private var cleanRR: [Double] = []                // artifact-corrected R-R window
    // Raw diagnostic log of the threshold test (for validation / recalibration)
    private(set) var ownzoneSamples: [(t: Int, stage: Int, label: String, bpm: Int, rmssd: Double, alpha1: Double)] = []
    private(set) var ownzoneRRLog: [Double] = []
    var ownzoneHasData: Bool { !ownzoneSamples.isEmpty }

    // Adaptive HRV zones: during a workout, watch DFA-α1 and, once per day, set today's
    // Zone-2 ceiling to the HR where α1 drops through 0.75 (the aerobic threshold).
    var adaptiveHRVEnabled = false
    @Published var adaptiveThresholdHR = 0      // today's detected aerobic-threshold HR (0 = not yet)
    @Published var adaptiveAlpha1: Double = 0   // live α1 for display while detecting
    private var adaptiveCleanRR: [Double] = []
    private var adaptiveAlphaBaseline = 0.0
    private var adaptiveBelowSince: Date?

    /// Guided ramp stages for the threshold test (escalating effort, ~1 min each).
    static let ownzoneStages: [(label: String, seconds: Int)] = [
        ("Easy walk", 60),
        ("Brisk walk", 60),
        ("Light jog", 60),
        ("Steady jog", 60),
        ("Build harder", 60),
    ]
    var ownzoneElapsed: Int { ownzoneLength - ownzoneRemaining }
    var ownzoneStageIndex: Int {
        var acc = 0
        for (i, s) in Self.ownzoneStages.enumerated() {
            acc += s.seconds
            if ownzoneElapsed < acc { return i }
        }
        return Self.ownzoneStages.count - 1
    }
    var ownzoneStageLabel: String { Self.ownzoneStages[ownzoneStageIndex].label }
    var ownzoneStageSeconds: Int { Self.ownzoneStages[ownzoneStageIndex].seconds }
    var ownzoneStageRemaining: Int {
        var acc = 0
        for s in Self.ownzoneStages {
            acc += s.seconds
            if ownzoneElapsed < acc { return acc - ownzoneElapsed }
        }
        return 0
    }
    var ownzoneNextStageLabel: String? {
        let next = ownzoneStageIndex + 1
        return next < Self.ownzoneStages.count ? Self.ownzoneStages[next].label : nil
    }

    let hrm = HeartRateManager()
    let loc = LocationTracker()
    let health = HealthStore()
    let liveActivity = LiveActivityManager()
    var liveBannerEnabled = false   // keep the Live Activity up whenever connected

    private func liveStatus(_ v: Int) -> String {
        if v < floorBpm { return "low" }
        if v > ceilingBpm { return "high" }
        return "in"
    }

    /// Show the Live Activity during a workout, or any time the banner option is on
    /// and a strap is connected; otherwise end it.
    func syncLiveActivity() {
        if active || (liveBannerEnabled && connected) {
            let b = bpm ?? 0
            liveActivity.start(bpm: b, zone: currentZone, floor: floorBpm, ceiling: ceilingBpm, status: liveStatus(b))
        } else {
            liveActivity.end()
        }
    }

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
        hrm.onRR = { [weak self] rrs in self?.handleRR(rrs) }
        hrm.onDisconnect = { [weak self] in self?.scheduleAutoSave(); self?.syncLiveActivity() }
        hrm.onReconnect = { [weak self] in self?.cancelAutoSave(); self?.syncLiveActivity() }
        loadTodayThreshold()
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
               useHRR: Bool, adaptiveHRV: Bool = false) {
        self.age = age
        self.isMale = isMale
        self.weightKg = weightKg
        self.restingHR = max(30, restingHR)
        self.bandZone = bandZone
        self.mhrOverride = mhrOverride
        self.manualFloor = manualFloor
        self.manualCeiling = manualCeiling
        self.useHRR = useHRR
        self.adaptiveHRVEnabled = adaptiveHRV
        if adaptiveHRV { loadTodayThreshold() }
        hrm.floorBpm = floorBpm
        hrm.ceilingBpm = ceilingBpm
        objectWillChange.send()
    }

    // Derived values
    var mhr: Int { mhrOverride ?? Zones.mhr(age: age) }
    var usingMeasuredMax: Bool { mhrOverride != nil }
    var usingManualBand: Bool { manualFloor != nil || manualCeiling != nil }
    /// True when adaptive HRV zones are on AND we've detected today's threshold.
    var usingAdaptiveBand: Bool { adaptiveHRVEnabled && adaptiveThresholdHR > 0 }

    var floorBpm: Int {
        if let m = manualFloor { return m }
        if usingAdaptiveBand {
            let width = Zones.upperBpm(zone: 2, mhr: mhr) - Zones.lowerBpm(zone: 2, mhr: mhr)
            return max(1, adaptiveThresholdHR - width)
        }
        return useHRR ? Zones.lowerBpmHRR(zone: bandZone, mhr: mhr, rest: restingHR)
                      : Zones.lowerBpm(zone: bandZone, mhr: mhr)
    }
    var ceilingBpm: Int {
        if let m = manualCeiling { return m }
        if usingAdaptiveBand { return adaptiveThresholdHR }   // aerobic threshold = top of Zone 2
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
        syncLiveActivity()
    }

    func start() {
        active = true
        hrm.alertsEnabled = true     // zone alerts only while actively working out
        sessionSaved = false
        startDate = Date().addingTimeInterval(-accumulated)
        lastHRDate = Date()
        loc.start()
        startTimer()
        let b = bpm ?? 0
        liveActivity.start(bpm: b, zone: currentZone, floor: floorBpm, ceiling: ceilingBpm, status: liveStatus(b))
    }

    func pause() {
        active = false
        hrm.alertsEnabled = false    // stop zone alerts when paused/ended
        accumulated = duration
        loc.pause()
        timer?.invalidate()
        lastHRDate = nil
        syncLiveActivity()
    }

    func reset() {
        active = false
        hrm.alertsEnabled = false    // stop zone alerts once the workout is ended/reset
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
        syncLiveActivity()
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
            if restingResult > 0 { store?.addMeasurement(kind: "resting", bpm: restingResult) }
            cancelRestingTest()
        }
    }

    // MARK: - Interval timer

    var intervalTotalRounds: Int { intervalRounds }

    func startIntervals(work: Int, rest: Int, rounds: Int) {
        intervalWorkSec = work; intervalRestSec = rest; intervalRounds = max(1, rounds)
        intervalActive = true
        intervalIsWork = true
        intervalRound = 1
        intervalRemaining = work
        announceInterval(work: true)
        intervalTimer?.invalidate()
        let t = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in self?.intervalTick() }
        RunLoop.main.add(t, forMode: .common)
        intervalTimer = t
    }

    func stopIntervals() {
        intervalActive = false
        intervalTimer?.invalidate()
        intervalTimer = nil
    }

    private func intervalTick() {
        guard intervalActive else { return }
        intervalRemaining -= 1
        if intervalRemaining > 0 { return }
        if intervalIsWork {
            intervalIsWork = false
            intervalRemaining = intervalRestSec
            announceInterval(work: false)
        } else if intervalRound >= intervalRounds {
            stopIntervals()
            hrm.say("Workout complete. Great job.")
        } else {
            intervalRound += 1
            intervalIsWork = true
            intervalRemaining = intervalWorkSec
            announceInterval(work: true)
        }
    }

    private func announceInterval(work: Bool) {
        hrm.say(work ? "Go hard" : "Recover")
        UINotificationFeedbackGenerator().notificationOccurred(work ? .warning : .success)
    }

    // MARK: - Heart-rate recovery test (60s drop after hard effort)

    func startRecoveryTest() {
        guard let b = bpm, b > 0 else { return }
        recoveryTesting = true
        recoveryRemaining = 60
        recoveryStartHR = b
        recoveryResult = 0
        recoveryTimer?.invalidate()
        let t = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in self?.recoveryTick() }
        RunLoop.main.add(t, forMode: .common)
        recoveryTimer = t
    }

    func cancelRecoveryTest() {
        recoveryTesting = false
        recoveryTimer?.invalidate()
        recoveryTimer = nil
    }

    private func recoveryTick() {
        guard recoveryTesting else { return }
        recoveryRemaining -= 1
        if recoveryRemaining <= 0 {
            if let b = bpm { recoveryResult = max(0, recoveryStartHR - b) }
            if recoveryResult > 0 { store?.addMeasurement(kind: "recovery", bpm: recoveryResult) }
            cancelRecoveryTest()
        }
    }

    // MARK: - OwnZone-style HRV warm-up (aerobic-threshold detection)

    func startOwnzoneTest() {
        ownzoneTesting = true
        ownzoneRemaining = ownzoneLength
        ownzoneRMSSD = 0
        ownzoneBaseline = 0
        ownzoneThresholdHR = 0
        ownzoneAlpha1 = 0
        ownzoneAlphaBaseline = 0
        rrBuffer = []
        cleanRR = []
        ownzoneSamples = []
        ownzoneRRLog = []
        ownzoneBelowSince = nil
        lastOwnzoneStage = -1
        ownzoneTimer?.invalidate()
        let t = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in self?.ownzoneTick() }
        RunLoop.main.add(t, forMode: .common)
        ownzoneTimer = t
    }

    func cancelOwnzoneTest() {
        ownzoneTesting = false
        ownzoneTimer?.invalidate()
        ownzoneTimer = nil
    }

    // MARK: - Adaptive HRV zones (live daily threshold)

    /// Route incoming R-R intervals: the guided test takes priority; otherwise, if
    /// adaptive zones are on during a live workout, run the daily threshold detector.
    private func handleRR(_ rrs: [Double]) {
        if ownzoneTesting { ingestRR(rrs) }
        else if adaptiveHRVEnabled && active { adaptiveIngestRR(rrs) }
    }

    /// Same validated DFA-α1 detector as the guided test, run passively during a
    /// normal workout. Fires once per day: when α1 (after a healthy easy baseline)
    /// drops through 0.75 for ~6s, that HR becomes today's Zone-2 ceiling.
    private func adaptiveIngestRR(_ rrs: [Double]) {
        guard adaptiveThresholdHR == 0 else { return }   // already detected today
        for raw in rrs where raw > 300 && raw < 2000 {
            if let last = adaptiveCleanRR.last, abs(raw - last) / last > 0.20 { continue }
            adaptiveCleanRR.append(raw)
        }
        if adaptiveCleanRR.count > 300 { adaptiveCleanRR.removeFirst(adaptiveCleanRR.count - 300) }
        guard adaptiveCleanRR.count >= 40, let a = Self.dfaAlpha1(Array(adaptiveCleanRR.suffix(120))) else { return }
        adaptiveAlpha1 = a
        if a > adaptiveAlphaBaseline { adaptiveAlphaBaseline = a }
        guard adaptiveAlphaBaseline > 0.85 else { return }   // need an easy baseline first
        if a < 0.75 {
            if let since = adaptiveBelowSince {
                if Date().timeIntervalSince(since) >= 6, let b = bpm, b > 0 {
                    saveTodayThreshold(b)
                    store?.addMeasurement(kind: "ownzone", bpm: b)
                    hrm.floorBpm = floorBpm
                    hrm.ceilingBpm = ceilingBpm
                    objectWillChange.send()
                }
            } else {
                adaptiveBelowSince = Date()
            }
        } else if a >= 0.78 {
            adaptiveBelowSince = nil   // hysteresis
        }
    }

    private func loadTodayThreshold() {
        let d = UserDefaults.standard.object(forKey: "adaptiveThrDate") as? Date
        if let d, Calendar.current.isDateInToday(d) {
            adaptiveThresholdHR = UserDefaults.standard.integer(forKey: "adaptiveThrBpm")
        } else {
            adaptiveThresholdHR = 0
        }
        adaptiveCleanRR = []; adaptiveAlphaBaseline = 0; adaptiveBelowSince = nil
    }

    private func saveTodayThreshold(_ bpm: Int) {
        adaptiveThresholdHR = bpm
        UserDefaults.standard.set(bpm, forKey: "adaptiveThrBpm")
        UserDefaults.standard.set(Date(), forKey: "adaptiveThrDate")
    }

    private func ownzoneTick() {
        guard ownzoneTesting else { return }
        ownzoneRemaining -= 1
        // Announce each new ramp stage with a voice cue + haptic.
        let stage = ownzoneStageIndex
        if stage != lastOwnzoneStage {
            lastOwnzoneStage = stage
            hrm.say(Self.ownzoneStages[stage].label)
            UINotificationFeedbackGenerator().notificationOccurred(.warning)
        }
        // Per-second diagnostic sample
        ownzoneSamples.append((t: ownzoneElapsed, stage: stage,
                               label: Self.ownzoneStages[stage].label,
                               bpm: bpm ?? 0, rmssd: ownzoneRMSSD, alpha1: ownzoneAlpha1))
        if ownzoneRemaining <= 0 {
            if ownzoneThresholdHR == 0, let b = bpm { ownzoneThresholdHR = b }
            if ownzoneThresholdHR > 0 { store?.addMeasurement(kind: "ownzone", bpm: ownzoneThresholdHR) }
            cancelOwnzoneTest()
        }
    }

    /// Feed R-R intervals → artifact-correct, track RMSSD + DFA-α1, and detect the
    /// aerobic threshold as the heart rate where DFA-α1 drops through 0.75.
    private func ingestRR(_ rrs: [Double]) {
        guard ownzoneTesting else { return }
        for raw in rrs where raw > 300 && raw < 2000 {
            // Artifact correction: reject beats that jump >20% from the last good beat.
            if let last = cleanRR.last, abs(raw - last) / last > 0.20 { continue }
            cleanRR.append(raw)
            ownzoneRRLog.append(raw)
        }
        if cleanRR.count > 300 { cleanRR.removeFirst(cleanRR.count - 300) }
        guard cleanRR.count >= 8 else { return }

        // RMSSD over the recent beats (for display/logging)
        let recent = Array(cleanRR.suffix(30))
        var sum = 0.0, n = 0
        for i in 1..<recent.count { let d = recent[i] - recent[i - 1]; sum += d * d; n += 1 }
        ownzoneRMSSD = n > 0 ? (sum / Double(n)).squareRoot() : 0

        // DFA-α1 over the recent window (the validated threshold marker)
        guard cleanRR.count >= 40 else { return }
        guard let a = Self.dfaAlpha1(Array(cleanRR.suffix(120))) else { return }
        ownzoneAlpha1 = a
        if a > ownzoneAlphaBaseline { ownzoneAlphaBaseline = a }

        // Threshold = α1 below 0.75 sustained ~6s, after a healthy resting baseline.
        if ownzoneThresholdHR == 0, ownzoneAlphaBaseline > 0.85 {
            if a < 0.75 {
                if let since = ownzoneBelowSince {
                    if Date().timeIntervalSince(since) >= 6, let b = bpm, b > 0 {
                        ownzoneThresholdHR = b
                    }
                } else {
                    ownzoneBelowSince = Date()
                }
            } else if a >= 0.78 {
                ownzoneBelowSince = nil   // hysteresis
            }
        }
    }

    /// Detrended Fluctuation Analysis short-term scaling exponent (α1), box sizes 4–16 beats.
    static func dfaAlpha1(_ rr: [Double]) -> Double? {
        let count = rr.count
        guard count >= 16 else { return nil }
        let mean = rr.reduce(0, +) / Double(count)
        var y = [Double](repeating: 0, count: count)
        var acc = 0.0
        for i in 0..<count { acc += rr[i] - mean; y[i] = acc }

        var logN = [Double](), logF = [Double]()
        for s in 4...16 where s <= count {
            let boxes = count / s
            guard boxes >= 1 else { continue }
            var sumSq = 0.0, total = 0
            for b in 0..<boxes {
                let start = b * s
                var sx = 0.0, sy = 0.0, sxx = 0.0, sxy = 0.0
                for j in 0..<s {
                    let x = Double(j), v = y[start + j]
                    sx += x; sy += v; sxx += x * x; sxy += x * v
                }
                let denom = Double(s) * sxx - sx * sx
                let slope = denom != 0 ? (Double(s) * sxy - sx * sy) / denom : 0
                let intercept = (sy - slope * sx) / Double(s)
                for j in 0..<s {
                    let resid = y[start + j] - (slope * Double(j) + intercept)
                    sumSq += resid * resid; total += 1
                }
            }
            guard total > 0 else { continue }
            let f = (sumSq / Double(total)).squareRoot()
            if f > 0 { logN.append(log(Double(s))); logF.append(log(f)) }
        }
        guard logN.count >= 2 else { return nil }
        let m = Double(logN.count)
        let sx = logN.reduce(0, +), sy = logF.reduce(0, +)
        var sxx = 0.0, sxy = 0.0
        for i in 0..<logN.count { sxx += logN[i] * logN[i]; sxy += logN[i] * logF[i] }
        let denom = m * sxx - sx * sx
        guard denom != 0 else { return nil }
        return (m * sxy - sx * sy) / denom
    }

    /// Write the diagnostic CSVs (per-second curve + raw R-R) and return their URLs.
    func ownzoneExportURLs() -> [URL] {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        var urls: [URL] = []
        var s = "seconds,stage,label,bpm,rmssd_ms,dfa_alpha1\n"
        for x in ownzoneSamples {
            s += "\(x.t),\(x.stage + 1),\(x.label),\(x.bpm),\(String(format: "%.1f", x.rmssd)),\(String(format: "%.3f", x.alpha1))\n"
        }
        let u1 = dir.appendingPathComponent("zonealert_threshold_curve.csv")
        if (try? s.write(to: u1, atomically: true, encoding: .utf8)) != nil { urls.append(u1) }

        var r = "index,rr_ms\n"
        for (i, rr) in ownzoneRRLog.enumerated() { r += "\(i),\(String(format: "%.1f", rr))\n" }
        let u2 = dir.appendingPathComponent("zonealert_threshold_rr.csv")
        if (try? r.write(to: u2, atomically: true, encoding: .utf8)) != nil { urls.append(u2) }
        return urls
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
        if active || (liveBannerEnabled && connected) {
            liveActivity.start(bpm: value, zone: z, floor: floorBpm, ceiling: ceilingBpm, status: liveStatus(value))
        }
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
        if hrHistory.count > 14400 { hrHistory.removeFirst() }   // ~4h at 1 Hz
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
