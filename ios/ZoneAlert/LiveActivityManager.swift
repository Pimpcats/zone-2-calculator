import Foundation
import ActivityKit

/// Starts/updates/ends the Lock-Screen & Dynamic-Island Live Activity for a workout.
final class LiveActivityManager {
    private var activity: Activity<ZoneActivityAttributes>?

    func start(bpm: Int, zone: Int, floor: Int, ceiling: Int, status: String) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        if activity != nil { update(bpm: bpm, zone: zone, floor: floor, ceiling: ceiling, status: status); return }
        let state = ZoneActivityAttributes.ContentState(bpm: bpm, zone: zone, floor: floor,
                                                        ceiling: ceiling, status: status)
        do {
            activity = try Activity.request(
                attributes: ZoneActivityAttributes(title: "Workout"),
                content: ActivityContent(state: state, staleDate: nil),
                pushType: nil)
        } catch {
            activity = nil
        }
    }

    func update(bpm: Int, zone: Int, floor: Int, ceiling: Int, status: String) {
        guard let activity = activity else { return }
        let state = ZoneActivityAttributes.ContentState(bpm: bpm, zone: zone, floor: floor,
                                                        ceiling: ceiling, status: status)
        Task { await activity.update(ActivityContent(state: state, staleDate: nil)) }
    }

    func end() {
        guard let activity = activity else { return }
        Task { await activity.end(nil, dismissalPolicy: .immediate) }
        self.activity = nil
    }

    /// Dismiss any leftover activities (e.g. the app was killed mid-workout, leaving the
    /// Island/banner stuck). Safe to call on launch since a workout never survives a kill.
    func endOrphaned() {
        for a in Activity<ZoneActivityAttributes>.activities {
            Task { await a.end(nil, dismissalPolicy: .immediate) }
        }
        activity = nil
    }
}
