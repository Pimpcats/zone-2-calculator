import Foundation
import HealthKit

/// Saves completed workouts to Apple Health.
///
/// NOTE: Writing to Health requires the HealthKit **entitlement**, which is only granted
/// on a properly signed build (App Store / TestFlight / paid Developer account). On a
/// free-account sideloaded build the entitlement isn't present, so authorization will
/// fail gracefully and nothing is saved — but the app keeps working. Everything is
/// guarded so this never crashes.
final class HealthStore {
    private let store = HKHealthStore()
    var available: Bool { HKHealthStore.isHealthDataAvailable() }

    private var shareTypes: Set<HKSampleType> {
        var s: Set<HKSampleType> = [HKObjectType.workoutType()]
        s.insert(HKQuantityType(.activeEnergyBurned))
        s.insert(HKQuantityType(.distanceWalkingRunning))
        return s
    }

    func requestAuth(_ completion: @escaping (Bool) -> Void) {
        guard available else { completion(false); return }
        store.requestAuthorization(toShare: shareTypes, read: []) { ok, _ in
            DispatchQueue.main.async { completion(ok) }
        }
    }

    func save(_ record: WorkoutRecord) {
        guard available else { return }
        let energy = HKQuantity(unit: .kilocalorie(), doubleValue: max(0, record.calories))
        let distance = HKQuantity(unit: .mile(), doubleValue: max(0, record.distanceMiles))
        let end = record.date
        let start = end.addingTimeInterval(-record.duration)
        let workout = HKWorkout(activityType: .running,
                                start: start, end: end, duration: record.duration,
                                totalEnergyBurned: energy, totalDistance: distance,
                                metadata: [HKMetadataKeyIndoorWorkout: false])
        store.save(workout) { _, _ in }
    }
}
