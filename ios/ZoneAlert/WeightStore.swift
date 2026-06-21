import Foundation

/// A logged body-weight reading over time.
struct WeightEntry: Codable, Identifiable {
    var id = UUID()
    var date: Date
    var lb: Double
}

/// One day's calorie ledger: eaten vs. burned (workout). Deficit is derived with
/// your maintenance calories.
struct DayDeficit: Codable {
    var dateKey: String      // "yyyy-MM-dd"
    var eaten: Int = 0
    var burned: Int = 0      // workout calories logged for the day
}

/// Tracks body weight over time plus a daily calorie ledger, and projects weekly
/// loss using the standard 1 lb ≈ 3,500 kcal rule. All on-device.
final class WeightStore: ObservableObject {
    static let kcalPerPound = 3500.0

    @Published private(set) var weights: [WeightEntry] = []   // oldest → newest
    @Published private(set) var days: [DayDeficit] = []
    private let wKey = "weights.v1"
    private let dKey = "deficits.v1"

    static let fmt: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()
    var todayKey: String { Self.fmt.string(from: Date()) }

    init() { load() }

    // MARK: - Weight log

    func logWeight(_ lb: Double) {
        guard lb > 0 else { return }
        weights.append(WeightEntry(date: Date(), lb: lb))
        if weights.count > 730 { weights.removeFirst(weights.count - 730) }
        save()
    }
    var latestWeight: Double? { weights.last?.lb }

    // MARK: - Daily ledger

    func day(_ key: String) -> DayDeficit { days.first { $0.dateKey == key } ?? DayDeficit(dateKey: key) }

    func setEaten(_ v: Int, for key: String) { upsert(key) { $0.eaten = max(0, v) } }
    func setBurned(_ v: Int, for key: String) { upsert(key) { $0.burned = max(0, v) } }

    private func upsert(_ key: String, _ mod: (inout DayDeficit) -> Void) {
        var d = days.first { $0.dateKey == key } ?? DayDeficit(dateKey: key)
        mod(&d)
        days.removeAll { $0.dateKey == key }
        days.append(d)
        days.sort { $0.dateKey < $1.dateKey }
        save()
    }

    /// Deficit for one day = maintenance + workout burn − eaten.
    func deficit(_ d: DayDeficit, maintenance: Int) -> Int { maintenance + d.burned - d.eaten }

    /// Actual summed deficit over the last 7 days that have any entry.
    func weeklyDeficit(maintenance: Int) -> (kcal: Int, loggedDays: Int) {
        let cal = Calendar.current
        var total = 0, n = 0
        for offset in 0..<7 {
            guard let date = cal.date(byAdding: .day, value: -offset, to: Date()) else { continue }
            let key = Self.fmt.string(from: date)
            if let d = days.first(where: { $0.dateKey == key }), d.eaten > 0 || d.burned > 0 {
                total += deficit(d, maintenance: maintenance); n += 1
            }
        }
        return (total, n)
    }

    /// Last N weight entries for a simple trend.
    func recentWeights(_ n: Int = 30) -> [WeightEntry] { Array(weights.suffix(n)) }

    // MARK: - Persistence

    private func load() {
        if let data = UserDefaults.standard.data(forKey: wKey),
           let arr = try? JSONDecoder().decode([WeightEntry].self, from: data) { weights = arr }
        if let data = UserDefaults.standard.data(forKey: dKey),
           let arr = try? JSONDecoder().decode([DayDeficit].self, from: data) { days = arr }
    }
    private func save() {
        if let w = try? JSONEncoder().encode(weights) { UserDefaults.standard.set(w, forKey: wKey) }
        if let d = try? JSONEncoder().encode(days) { UserDefaults.standard.set(d, forKey: dKey) }
    }
}
