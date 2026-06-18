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
    private let key = "workouts.v1"

    init() { load() }

    func add(_ r: WorkoutRecord) {
        records.insert(r, at: 0)
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
