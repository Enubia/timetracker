import Foundation
import UserNotifications

enum Notifier {
    static func requestAuthorization() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    static func nudgeTenHours() {
        let content = UNMutableNotificationContent()
        content.title = "Still tracking — 10h reached"
        content.body = "You've been working 10 hours. Austrian law caps the working day at 10h — time to end the session?"
        content.sound = .default
        let request = UNNotificationRequest(identifier: "ten-hour-nudge", content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
}
