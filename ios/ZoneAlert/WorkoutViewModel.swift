import Foundation
import SwiftUI

/// Owns the live workout session: heart rate (BLE strap) + distance/pace (GPS) +
/// duration, calories, time-in-zone and the HR history used for the live graph.
final class WorkoutViewModel: ObservableObject {

    // Live metrics
    @Published var bpm: Int? = nil
    @Published var currentZone: Int = 0
    @Published var duration: TimeInterval = 0
    @Published var calories: Double = 0
    @Published var timeInZone: [Double] = Array(repeating: 0, count: 6)   // index 0 = below Z1, 1...5 = zones
    @Published var hrHistory: [Int] = []
    @Published var active = false

    // Settings (persisted by the view via @AppStorage and pushed in here)
    var age: Int = 40 { didSet { hrm.age = age } }
    var targetZone: Int = 2 { didSet { hrm.targetZone = targetZone } }
    var weightKg: Double = 75
    var isMale: Bool = true

    let hrm = HeartRateManager()
    let loc = LocationTracker()

    private var timer: Timer?
    private var startDate: Date?
    private var accumulated: TimeInterval = 0
    private var lastHRDate: Date?

    init() {
        hrm.onReading = { [weak self] bpm in self?.ingest(bpm: bpm) }
    }

    // Derived
    var distanceMiles: Double { loc.distanceMeters / 1609.344 }
    var paceSecPerMile: Double? {
        guard distanceMiles > 0.02, duration > 0 else { return nil }
        return duration / distanceMiles
    }
    var connected: Bool { hrm.connected }
    var bluetoothReady: Bool { hrm.bluetoothReady }
    var statusText: String { hrm.statusText }
    var mhr: Int { Zones.mhr(age: age) }

    // MARK: - Session control

    func connect() { hrm.startScanning() }
    func disconnectStrap() { hrm.disconnect() }

    func start() {
        active = true
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
        startDate = nil
        lastHRDate = nil
        loc.reset()
        timer?.invalidate()
    }

    // MARK: - Data ingestion

    private func ingest(bpm value: Int) {
        bpm = value
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
        addCalories(bpm: value, dt: dt)
        hrHistory.append(value)
        if hrHistory.count > 600 { hrHistory.removeFirst() }
    }

    /// HR-based calorie estimate (Keytel et al., 2005), accumulated per sample.
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
