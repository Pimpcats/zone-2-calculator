import Foundation

/// A finished workout, persisted for daily / weekly progress.
struct WorkoutRecord: Codable, Identifiable {
    var id = UUID()
    var date: Date
    var duration: TimeInterval
    var distanceMiles: Double
    var calories: Double
    var avgBpm: Int
    var peakBpm: Int
    var timeInZone: [Double]   // index 1...5
    var exerciseType: String? = nil
    // Added later — all optional so older saved workouts and backups still decode.
    // `calories` above is the gross heart-rate (Keytel) estimate.
    var activeCalories: Double? = nil            // heart-rate estimate minus resting share
    var treadmillCalories: Double? = nil         // gross, from speed + grade + weight
    var treadmillActiveCalories: Double? = nil
    var hrTrackedSeconds: Double? = nil          // workout time that had heart-rate data
    var hrInterpolatedSeconds: Double? = nil     // part of that filled in across short gaps

    /// Active calories: the stored figure when recorded live, otherwise gross minus an
    /// estimated resting share for the workout's duration.
    func activeEstimate(restPerMin: Double) -> Double {
        activeCalories ?? Energy.activeKcal(gross: calories, restPerMin: restPerMin, seconds: duration)
    }
}

/// A single physiology measurement (resting HR or OwnZone aerobic threshold) over time.
struct Measurement: Codable, Identifiable {
    var id = UUID()
    var date: Date
    var kind: String     // "resting" or "ownzone"
    var bpm: Int
}

/// Machine-readable backup of everything the store holds — written alongside the PDF
/// on export, read back by "Import all data" to survive reinstalls.
struct BackupFile: Codable {
    var version = 1
    var records: [WorkoutRecord]
    var measurements: [Measurement]
    var weights: [WeightEntry]? = nil
}

/// Aggregated totals over a span of workouts.
struct ProgressTotals {
    var count: Int = 0
    var duration: TimeInterval = 0
    var miles: Double = 0
    var calories: Double = 0
}

/// Stores workout history in UserDefaults and computes day/week aggregates.
final class WorkoutStore: ObservableObject {
    @Published private(set) var records: [WorkoutRecord] = []
    @Published private(set) var measurements: [Measurement] = []   // newest first
    private let key = "workouts.v1"
    @Published private(set) var weights: [WeightEntry] = []        // newest first
    private let mKey = "measurements.v1"
    private let wKey = "weights.v1"

    init() { load(); loadMeasurements(); loadWeights() }

    // MARK: - Body-weight log

    func addWeight(lbs: Double, date: Date = Date()) {
        weights.insert(WeightEntry(date: date, lbs: lbs), at: 0)
        weights.sort { $0.date > $1.date }
        saveWeights()
    }

    func deleteWeight(_ w: WeightEntry) {
        weights.removeAll { $0.id == w.id }
        saveWeights()
    }

    private func loadWeights() {
        if let data = UserDefaults.standard.data(forKey: wKey),
           let arr = try? JSONDecoder().decode([WeightEntry].self, from: data) {
            weights = arr
        }
    }

    private func saveWeights() {
        if let data = try? JSONEncoder().encode(weights) {
            UserDefaults.standard.set(data, forKey: wKey)
        }
    }

    /// Average workout active calories per day between two dates.
    func avgDailyActiveCalories(from start: Date, to end: Date, restPerMin: Double) -> Double {
        let days = end.timeIntervalSince(start) / 86400
        guard days > 0 else { return 0 }
        let total = records.filter { $0.date >= start && $0.date <= end }
            .reduce(0.0) { $0 + $1.activeEstimate(restPerMin: restPerMin) }
        return total / days
    }

    // MARK: - Measurements (resting HR / OwnZone threshold trends)

    func addMeasurement(kind: String, bpm: Int) {
        guard bpm > 0 else { return }
        measurements.insert(Measurement(date: Date(), kind: kind, bpm: bpm), at: 0)
        if measurements.count > 365 { measurements = Array(measurements.prefix(365)) }
        if let data = try? JSONEncoder().encode(measurements) {
            UserDefaults.standard.set(data, forKey: mKey)
        }
    }

    /// Measurements of one kind, oldest → newest (for left-to-right charts).
    func series(_ kind: String) -> [Measurement] {
        measurements.filter { $0.kind == kind }.reversed()
    }

    private func loadMeasurements() {
        if let data = UserDefaults.standard.data(forKey: mKey),
           let arr = try? JSONDecoder().decode([Measurement].self, from: data) {
            measurements = arr
        }
    }

    /// Add a workout. Saving the same session again (e.g. Finish after an auto-save)
    /// replaces the earlier copy instead of creating a duplicate.
    func add(_ r: WorkoutRecord) {
        records.removeAll { $0.id == r.id }
        records.insert(r, at: 0)
        records.sort { $0.date > $1.date }
        save()
    }

    /// Merge a backup into the store, skipping anything already present (by id).
    /// Returns how many workouts / measurements were actually added.
    func mergeImported(_ backup: BackupFile) -> (workouts: Int, measurements: Int) {
        let haveR = Set(records.map { $0.id })
        let newR = backup.records.filter { !haveR.contains($0.id) }
        records.append(contentsOf: newR)
        records.sort { $0.date > $1.date }
        save()

        let haveM = Set(measurements.map { $0.id })
        let newM = backup.measurements.filter { !haveM.contains($0.id) }
        measurements.append(contentsOf: newM)
        measurements.sort { $0.date > $1.date }
        if let data = try? JSONEncoder().encode(measurements) {
            UserDefaults.standard.set(data, forKey: mKey)
        }
        let haveW = Set(weights.map { $0.id })
        weights.append(contentsOf: (backup.weights ?? []).filter { !haveW.contains($0.id) })
        weights.sort { $0.date > $1.date }
        saveWeights()
        return (newR.count, newM.count)
    }

    /// Replace a saved workout (matched by id) with an edited version.
    func update(_ r: WorkoutRecord) {
        guard let i = records.firstIndex(where: { $0.id == r.id }) else { return }
        records[i] = r
        records.sort { $0.date > $1.date }
        save()
    }

    func delete(_ r: WorkoutRecord) {
        records.removeAll { $0.id == r.id }
        save()
    }

    private func load() {
        if let data = UserDefaults.standard.data(forKey: key),
           let arr = try? JSONDecoder().decode([WorkoutRecord].self, from: data) {
            records = arr
        }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(records) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    // MARK: - Aggregates

    func totals(since start: Date) -> ProgressTotals {
        var t = ProgressTotals()
        for r in records where r.date >= start {
            t.count += 1
            t.duration += r.duration
            t.miles += r.distanceMiles
            t.calories += r.calories
        }
        return t
    }

    var todayTotals: ProgressTotals {
        totals(since: Calendar.current.startOfDay(for: Date()))
    }

    var weekTotals: ProgressTotals {
        let cal = Calendar.current
        let start = cal.dateInterval(of: .weekOfYear, for: Date())?.start
            ?? cal.startOfDay(for: Date())
        return totals(since: start)
    }

    // MARK: - Calendar lookups

    func records(on day: Date) -> [WorkoutRecord] {
        records.filter { Calendar.current.isDate($0.date, inSameDayAs: day) }
    }
    func measurements(on day: Date) -> [Measurement] {
        measurements.filter { Calendar.current.isDate($0.date, inSameDayAs: day) }
    }
    func hasData(on day: Date) -> Bool {
        !records(on: day).isEmpty || !measurements(on: day).isEmpty
    }
    func totals(on day: Date) -> ProgressTotals {
        var t = ProgressTotals()
        for r in records(on: day) {
            t.count += 1; t.duration += r.duration; t.miles += r.distanceMiles; t.calories += r.calories
        }
        return t
    }

    /// Combined time-in-zone (index 0…5) across all of a day's workouts.
    func timeInZoneTotals(on day: Date) -> [Double] {
        var arr = [Double](repeating: 0, count: 6)
        for r in records(on: day) {
            for i in 0..<min(6, r.timeInZone.count) { arr[i] += r.timeInZone[i] }
        }
        return arr
    }

    /// Duration-weighted average HR and peak HR for a day.
    func hrSummary(on day: Date) -> (avg: Int, peak: Int) {
        let recs = records(on: day)
        guard !recs.isEmpty else { return (0, 0) }
        let totalDur = recs.reduce(0) { $0 + $1.duration }
        let weighted = recs.reduce(0.0) { $0 + Double($1.avgBpm) * $1.duration }
        let avg = totalDur > 0 ? Int(weighted / totalDur) : 0
        return (avg, recs.map { $0.peakBpm }.max() ?? 0)
    }

    // MARK: - Goals & streaks

    func minutes(on day: Date) -> Double {
        records(on: day).reduce(0) { $0 + $1.duration / 60.0 }
    }

    /// Consecutive days (ending today, or yesterday if today isn't met yet) meeting the goal.
    func currentStreak(goalMinutes: Int) -> Int {
        let cal = Calendar.current
        var day = cal.startOfDay(for: Date())
        if minutes(on: day) < Double(goalMinutes) {
            guard let y = cal.date(byAdding: .day, value: -1, to: day) else { return 0 }
            day = y
        }
        var streak = 0
        while minutes(on: day) >= Double(goalMinutes) {
            streak += 1
            guard let prev = cal.date(byAdding: .day, value: -1, to: day) else { break }
            day = prev
        }
        return streak
    }

    /// Duration (in minutes) for each of the last 7 days, oldest → newest.
    func last7DaysMinutes() -> [(label: String, minutes: Double)] {
        let cal = Calendar.current
        let fmt = DateFormatter(); fmt.dateFormat = "EEEEE"   // single-letter weekday
        var out: [(String, Double)] = []
        for offset in stride(from: 6, through: 0, by: -1) {
            guard let day = cal.date(byAdding: .day, value: -offset, to: Date()) else { continue }
            let start = cal.startOfDay(for: day)
            let end = cal.date(byAdding: .day, value: 1, to: start)!
            let mins = records
                .filter { $0.date >= start && $0.date < end }
                .reduce(0.0) { $0 + $1.duration / 60.0 }
            out.append((fmt.string(from: day), mins))
        }
        return out
    }
}
