import Foundation

/// One day's all-day summary, imported from Apple Health via the Shortcuts bridge.
struct DailyHealth: Codable, Identifiable {
    var dateKey: String          // "yyyy-MM-dd"
    var steps: Int = 0
    var activeCalories: Int = 0
    var restingHR: Int = 0
    var sleepMinutes: Int = 0

    var id: String { dateKey }
    var date: Date? { DailyHealth.fmt.date(from: dateKey) }

    static let fmt: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()
}

/// Stores all-day data (steps, active calories, resting HR, sleep) handed in from the
/// **Shortcuts app** via a `zonealert://health?…` link. This needs no HealthKit
/// entitlement — the Shortcuts app reads Apple Health and pushes the numbers to us, so
/// it works on a free sideloaded build. Kept completely separate from H9 workout data.
final class HealthImportStore: ObservableObject {
    @Published private(set) var days: [DailyHealth] = []     // newest first
    private let key = "healthImport.v1"

    init() { load() }

    var today: DailyHealth? {
        let k = DailyHealth.fmt.string(from: Date())
        return days.first { $0.dateKey == k }
    }

    /// Parse a `zonealert://health?date=…&steps=…&restingHR=…&activeCalories=…&sleepMinutes=…`
    /// link and upsert that day. Only the fields present in the link are updated.
    @discardableResult
    func ingest(_ url: URL) -> Bool {
        guard url.scheme?.lowercased() == "zonealert",
              (url.host?.lowercased() == "health") else { return false }
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        func str(_ n: String) -> String? { items.first { $0.name == n }?.value }
        func num(_ n: String) -> Int? {
            guard let s = str(n)?.trimmingCharacters(in: .whitespaces), let d = Double(s) else { return nil }
            return Int(d.rounded())
        }

        let dateKey = str("date").flatMap { normalizeDate($0) } ?? DailyHealth.fmt.string(from: Date())
        var d = days.first { $0.dateKey == dateKey } ?? DailyHealth(dateKey: dateKey)
        if let v = num("steps") { d.steps = v }
        if let v = num("activeCalories") { d.activeCalories = v }
        if let v = num("restingHR") { d.restingHR = v }
        if let v = num("sleepMinutes") { d.sleepMinutes = v }

        days.removeAll { $0.dateKey == dateKey }
        days.append(d)
        days.sort { $0.dateKey > $1.dateKey }
        if days.count > 365 { days = Array(days.prefix(365)) }
        save()
        return true
    }

    func clear() { days = []; save() }

    /// Accept "yyyy-MM-dd" directly, or coerce common ISO/date strings to that form.
    private func normalizeDate(_ s: String) -> String? {
        let t = s.trimmingCharacters(in: .whitespaces)
        if DailyHealth.fmt.date(from: t) != nil { return t }
        if t.count >= 10, DailyHealth.fmt.date(from: String(t.prefix(10))) != nil {
            return String(t.prefix(10))
        }
        return nil
    }

    private func load() {
        if let data = UserDefaults.standard.data(forKey: key),
           let arr = try? JSONDecoder().decode([DailyHealth].self, from: data) {
            days = arr
        }
    }
    private func save() {
        if let data = try? JSONEncoder().encode(days) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
}
