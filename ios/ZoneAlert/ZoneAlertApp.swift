import SwiftUI
import UserNotifications
import UIKit

@main
struct ZoneAlertApp: App {
    init() {
        UNUserNotificationCenter.current().delegate = NotificationForegrounder.shared
    }
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

/// Controls how notifications surface while the app is in the FOREGROUND.
/// Zone alerts only buzz (the on-screen highlight already shows them); everything
/// else (test alerts, auto-save) shows a normal banner. In the background iOS shows
/// the banner directly and this delegate isn't called.
final class NotificationForegrounder: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationForegrounder()
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        let kind = notification.request.content.userInfo["kind"] as? String
        if kind == "zone" {
            UINotificationFeedbackGenerator().notificationOccurred(.warning)  // buzz only
            completionHandler([])
        } else {
            completionHandler([.banner, .sound, .list])
        }
    }
}
