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
        // The Island/banner is rendered by the bundled widget extension. Sideloaders
        // sometimes strip extensions when re-signing — detect that from inside the
        // installed bundle so the test names the real problem instead of doing nothing.
        let plugins = (Bundle.main.builtInPlugInsURL.flatMap {
            try? FileManager.default.contentsOfDirectory(at: $0, includingPropertiesForKeys: nil)
        }) ?? []
        guard plugins.contains(where: { $0.lastPathComponent == "ZoneAlertWidget.appex" }) else {
            completion("❌ The widget extension (the code that draws the Dynamic Island / Lock Screen display) is MISSING from this install — your sideloader removed it while signing. Delete Zone Alert and reinstall the .ipa, choosing “Keep App Extensions” when asked.")
            return
        }
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            completion("iOS says Live Activities are disabled for Zone Alert. Turn them on in iPhone Settings → Zone Alert → Live Activities.")
            return
        }

        // Identity readout: a re-signer that renames the app but not the widget breaks
        // the parent/child bundle-ID rule, and iOS then silently never loads the widget.
        let mainID = Bundle.main.bundleIdentifier ?? "?"
        let appexURL = Bundle.main.builtInPlugInsURL!.appendingPathComponent("ZoneAlertWidget.appex")
        let appexID = Bundle(url: appexURL)?.bundleIdentifier ?? "unreadable"
        let idsMatch = appexID.hasPrefix(mainID + ".")

        // Read the widget's embedded signing profile: if its application-identifier
        // doesn't cover the widget's bundle ID, iOS refuses to launch the extension
        // and dismisses the Live Activity moments after it starts.
        var profileID = "none — widget has NO embedded signing profile"
        let provURL = appexURL.appendingPathComponent("embedded.mobileprovision")
        if let d = try? Data(contentsOf: provURL), let s = String(data: d, encoding: .isoLatin1),
           let keyRange = s.range(of: "<key>application-identifier</key>") {
            let tail = s[keyRange.upperBound...]
            if let a = tail.range(of: "<string>"), let b = tail.range(of: "</string>"), a.upperBound <= b.lowerBound {
                profileID = String(tail[a.upperBound..<b.lowerBound])
            }
        }
        // Profile IDs are TEAMID.bundle-id; compare the suffix against the widget's ID.
        let profileCovers = profileID.hasSuffix(".\(appexID)") || profileID.hasSuffix(".*") || profileID == appexID
        let identity = """
        App ID: \(mainID)
        Widget ID: \(appexID)
        Prefix match: \(idsMatch ? "✓" : "❌ MISMATCH — re-signer renamed the app but not the widget")
        Widget profile: \(profileID)
        Profile covers widget: \(profileCovers ? "✓" : "❌ NO — iOS will refuse to launch the widget; this is why the Island is blank")
        """

        let state = ZoneActivityAttributes.ContentState(bpm: 142, zone: 2, floor: 125,
                                                        ceiling: 140, status: "ok")
        do {
            let test = try Activity.request(
                attributes: ZoneActivityAttributes(title: "Test"),
                content: ActivityContent(state: state, staleDate: nil),
                pushType: nil)
            Task {
                try? await Task.sleep(nanoseconds: 2_500_000_000)
                let st = String(describing: test.activityState)
                await MainActor.run {
                    completion("Live Activity requested — iOS reports state “\(st)” after 2.5 s.\n\n\(identity)\n\nIf everything above is ✓ and 142 bpm still isn’t in the Island, screenshot this pop-up. Test ends in ~12 s.")
                }
                try? await Task.sleep(nanoseconds: 12_000_000_000)
                await test.end(nil, dismissalPolicy: .immediate)
            }
        } catch {
            completion("iOS refused to start the Live Activity: \(error.localizedDescription)\n\n\(identity)")
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
