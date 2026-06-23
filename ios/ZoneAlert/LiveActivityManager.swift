import Foundation
import ActivityKit

/// Starts/updates/ends the Lock-Screen & Dynamic-Island Live Activity for a workout.
///
/// iOS throttles local Live Activity updates (especially in the background), so we only
/// push an update when the displayed state actually changes — sending identical updates
/// every second just burns the system budget and makes the Island lag more.
final class LiveActivityManager {
    private var activity: Activity<ZoneActivityAttributes>?
    private var last: ZoneActivityAttributes.ContentState?

    func start(bpm: Int, zone: Int, floor: Int, ceiling: Int, status: String) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        let state = ZoneActivityAttributes.ContentState(bpm: bpm, zone: zone, floor: floor,
                                                        ceiling: ceiling, status: status)
        if activity != nil { update(state); return }
        do {
            activity = try Activity.request(
                attributes: ZoneActivityAttributes(title: "Workout"),
                content: ActivityContent(state: state, staleDate: nil),
                pushType: nil)
            last = state
        } catch {
            activity = nil
        }
    }

    func update(bpm: Int, zone: Int, floor: Int, ceiling: Int, status: String) {
        update(ZoneActivityAttributes.ContentState(bpm: bpm, zone: zone, floor: floor,
                                                   ceiling: ceiling, status: status))
    }

    private func update(_ state: ZoneActivityAttributes.ContentState) {
        guard let activity = activity, state != last else { return }   // skip redundant updates
        last = state
        Task { await activity.update(ActivityContent(state: state, staleDate: nil)) }
    }

    func end() {
        guard let activity = activity else { return }
        last = nil
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
        last = nil
    }
}
