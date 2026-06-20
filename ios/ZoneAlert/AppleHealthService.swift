import Foundation
import HealthKit

/// One day's all-day summary pulled from **Apple Health**.
struct DailyHealth {
    var date: Date
    var steps: Int = 0
    var activeCalories: Int = 0
    var restingHR: Int = 0
    var sleepMinutes: Int = 0
}

/// Reads your all-day data — steps, active calories, resting heart rate, sleep — from
/// **Apple Health**, kept completely separate from the H9 workout data. Whatever you
/// wear (Fitbit via a bridge app, Apple Watch, Garmin, Oura, …) writes into Apple
/// Health, and we read it locally: no internet, no OAuth, no tokens that expire.
///
/// HealthKit *read* access needs the entitlement, which is present on a properly
/// signed build (AltStore/TestFlight/App Store). Everything is guarded so a build
/// without it fails gracefully instead of crashing.
final class AppleHealthService: ObservableObject {
    @Published var authorized = false
    @Published var loading = false
    @Published var status = ""
    @Published var today = DailyHealth(date: Calendar.current.startOfDay(for: Date()))
    @Published var recent: [DailyHealth] = []      // last 7 days, newest first

    private let store = HKHealthStore()
    private var available: Bool { HKHealthStore.isHealthDataAvailable() }

    private var readTypes: Set<HKObjectType> {
        var s: Set<HKObjectType> = []
        s.insert(HKQuantityType(.stepCount))
        s.insert(HKQuantityType(.activeEnergyBurned))
        s.insert(HKQuantityType(.restingHeartRate))
        s.insert(HKCategoryType(.sleepAnalysis))
        return s
    }

    func connect() {
        guard available else { status = "Apple Health isn't available on this device."; return }
        loading = true; status = "Requesting access…"
        store.requestAuthorization(toShare: [], read: readTypes) { [weak self] ok, err in
            DispatchQueue.main.async {
                guard let self else { return }
                self.loading = false
                if let err { self.status = "Health access error: \(err.localizedDescription)"; return }
                self.authorized = ok
                self.status = ok ? "Connected to Apple Health ✓" : "Access not granted."
                if ok { self.refresh() }
            }
        }
    }

    // MARK: - Pull

    func refresh() {
        guard available else { return }
        loading = true; status = "Reading from Apple Health…"
        let cal = Calendar.current
        let group = DispatchGroup()
        var days: [Date: DailyHealth] = [:]
        for offset in 0..<7 {
            let start = cal.date(byAdding: .day, value: -offset, to: cal.startOfDay(for: Date()))!
            days[start] = DailyHealth(date: start)
        }

        for (start, _) in days {
            let end = cal.date(byAdding: .day, value: 1, to: start)!
            let range = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)

            group.enter()
            sum(.stepCount, unit: .count(), predicate: range) { v in
                days[start]?.steps = Int(v); group.leave()
            }
            group.enter()
            sum(.activeEnergyBurned, unit: .kilocalorie(), predicate: range) { v in
                days[start]?.activeCalories = Int(v); group.leave()
            }
            group.enter()
            average(.restingHeartRate, unit: HKUnit.count().unitDivided(by: .minute()), predicate: range) { v in
                days[start]?.restingHR = Int(v.rounded()); group.leave()
            }
            group.enter()
            asleepMinutes(start: start, end: end) { m in
                days[start]?.sleepMinutes = m; group.leave()
            }
        }

        group.notify(queue: .main) { [weak self] in
            guard let self else { return }
            let sorted = days.values.sorted { $0.date > $1.date }
            self.recent = sorted
            self.today = sorted.first ?? DailyHealth(date: Calendar.current.startOfDay(for: Date()))
            self.loading = false
            self.status = "Updated \(Date().formatted(date: .omitted, time: .shortened))"
        }
    }

    // MARK: - Query helpers

    private func sum(_ id: HKQuantityTypeIdentifier, unit: HKUnit,
                     predicate: NSPredicate, _ done: @escaping (Double) -> Void) {
        let type = HKQuantityType(id)
        let q = HKStatisticsQuery(quantityType: type, quantitySamplePredicate: predicate,
                                  options: .cumulativeSum) { _, stats, _ in
            done(stats?.sumQuantity()?.doubleValue(for: unit) ?? 0)
        }
        store.execute(q)
    }

    private func average(_ id: HKQuantityTypeIdentifier, unit: HKUnit,
                         predicate: NSPredicate, _ done: @escaping (Double) -> Void) {
        let type = HKQuantityType(id)
        let q = HKStatisticsQuery(quantityType: type, quantitySamplePredicate: predicate,
                                  options: .discreteAverage) { _, stats, _ in
            done(stats?.averageQuantity()?.doubleValue(for: unit) ?? 0)
        }
        store.execute(q)
    }

    private func asleepMinutes(start: Date, end: Date, _ done: @escaping (Int) -> Void) {
        let type = HKCategoryType(.sleepAnalysis)
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: [])
        let q = HKSampleQuery(sampleType: type, predicate: predicate, limit: HKObjectQueryNoLimit,
                              sortDescriptors: nil) { _, samples, _ in
            let asleep: Set<Int> = [
                HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue,
                HKCategoryValueSleepAnalysis.asleepCore.rawValue,
                HKCategoryValueSleepAnalysis.asleepDeep.rawValue,
                HKCategoryValueSleepAnalysis.asleepREM.rawValue,
            ]
            var seconds = 0.0
            for s in (samples as? [HKCategorySample]) ?? [] where asleep.contains(s.value) {
                seconds += s.endDate.timeIntervalSince(s.startDate)
            }
            done(Int(seconds / 60))
        }
        store.execute(q)
    }
}
