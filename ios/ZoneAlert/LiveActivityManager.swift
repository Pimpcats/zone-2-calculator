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

    /// Fire a 15-second sample Live Activity so the user can verify the Dynamic Island /
    /// Lock Screen display works — and surface iOS's exact error when it doesn't.
    func runTest(completion: @escaping (String) -> Void) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            completion("iOS says Live Activities are disabled for Zone Alert. Turn them on in iPhone Settings → Zone Alert → Live Activities.")
            return
        }
        let state = ZoneActivityAttributes.ContentState(bpm: 142, zone: 2, floor: 125,
                                                        ceiling: 140, status: "ok")
        do {
            let test = try Activity.request(
                attributes: ZoneActivityAttributes(title: "Test"),
                content: ActivityContent(state: state, staleDate: nil),
                pushType: nil)
            completion("Test started. Swipe to the Home Screen or lock the phone — you should see 142 bpm in the Dynamic Island / on the Lock Screen. It disappears in ~15 seconds.")
            Task {
                try? await Task.sleep(nanoseconds: 15_000_000_000)
                await test.end(nil, dismissalPolicy: .immediate)
            }
        } catch {
            completion("iOS refused to start the Live Activity: \(error.localizedDescription)")
        }
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
