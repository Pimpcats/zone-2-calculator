import SwiftUI
import UserNotifications

@main
struct ZoneAlertApp: App {
    init() {
        // Show notification banners + play sound even while the app is foregrounded.
        UNUserNotificationCenter.current().delegate = NotificationForegrounder.shared
    }
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

/// Allows alerts to surface (with sound) while the app is in the foreground too.
final class NotificationForegrounder: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationForegrounder()
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound, .list])
    }
}
