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

    /// Saves one workout. Energy is the *active* estimate (Health's workout energy means
    /// active energy), and start/end are derived from the same duration the app shows.
    /// The record id is used as HealthKit's sync identifier, so saving the same workout
    /// again replaces the earlier copy instead of adding a duplicate.
    func save(_ record: WorkoutRecord) {
        guard available, record.duration > 0 else { return }
        let energy = HKQuantity(unit: .kilocalorie(), doubleValue: max(0, record.activeCalories ?? record.calories))
        let distance = HKQuantity(unit: .mile(), doubleValue: max(0, record.distanceMiles))
        let end = record.date
        let start = end.addingTimeInterval(-record.duration)
        let type = ExerciseType(rawValue: record.exerciseType ?? "") ?? .other
        let metadata: [String: Any] = [
            HKMetadataKeyIndoorWorkout: type.isIndoor,
            HKMetadataKeySyncIdentifier: record.id.uuidString,
            HKMetadataKeySyncVersion: NSNumber(value: Int(record.date.timeIntervalSince1970)),
        ]
        let mph = record.distanceMiles / (record.duration / 3600)
        let workout = HKWorkout(activityType: HealthStore.activityType(for: type, mph: mph),
                                start: start, end: end, duration: record.duration,
                                totalEnergyBurned: energy, totalDistance: distance,
                                metadata: metadata)
        store.save(workout) { _, _ in }
    }

    /// A treadmill session at walking pace is logged as a walk, not a run.
    static func activityType(for type: ExerciseType, mph: Double) -> HKWorkoutActivityType {
        switch type {
        case .treadmill: return mph > 0 && mph < 4.0 ? .walking : .running
        case .outdoorRun: return .running
        case .outdoorWalk: return .walking
        case .indoorBike, .outdoorBike: return .cycling
        case .elliptical: return .elliptical
        case .rowing: return .rowing
        case .other: return .other
        }
    }
}
