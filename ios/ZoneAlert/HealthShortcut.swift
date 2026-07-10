import UIKit

/// Sends a finished workout to Apple Health through a user-made Shortcut.
///
/// Free-signed builds can't write to HealthKit directly (the entitlement is
/// stripped when AltStore/SideStore re-signs), but Apple's Shortcuts app CAN
/// log workouts to Health. So on Finish we hand the numbers to a Shortcut
/// named `shortcutName` and it does the write. x-callback returns to the app.
enum HealthShortcut {
    static let shortcutName = "Log Zone Alert Workout"

    static func send(_ r: WorkoutRecord) {
        let payload: [String: Any] = [
            "kcal": Int(r.calories),
            "miles": (r.distanceMiles * 100).rounded() / 100,
            "minutes": max(1, Int((r.duration / 60).rounded())),
            "avgbpm": r.avgBpm,
            "type": r.exerciseType ?? "treadmill",
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: payload),
              let json = String(data: data, encoding: .utf8),
              var comps = URLComponents(string: "shortcuts://x-callback-url/run-shortcut")
        else { return }
        comps.queryItems = [
            URLQueryItem(name: "name", value: shortcutName),
            URLQueryItem(name: "input", value: "text"),
            URLQueryItem(name: "text", value: json),
            URLQueryItem(name: "x-success", value: "zonealert://"),
            URLQueryItem(name: "x-error", value: "zonealert://"),
        ]
        if let url = comps.url { UIApplication.shared.open(url) }
    }
}
