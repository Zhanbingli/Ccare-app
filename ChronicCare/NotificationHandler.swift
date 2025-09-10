import Foundation
import UserNotifications

@MainActor final class NotificationHandler: NSObject, UNUserNotificationCenterDelegate {
    weak var store: DataStore?

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        guard let idStr = response.notification.request.content.userInfo["medicationID"] as? String,
              let medID = UUID(uuidString: idStr) else { return }

        switch response.actionIdentifier {
        case NotificationManager.actionTaken:
            await MainActor.run { store?.logIntake(medicationID: medID, status: .taken) }
        case NotificationManager.actionSkip:
            await MainActor.run { store?.logIntake(medicationID: medID, status: .skipped) }
        case NotificationManager.actionSnooze:
            NotificationManager.shared.scheduleSnooze(for: medID)
            await MainActor.run { store?.logIntake(medicationID: medID, status: .snoozed) }
        default:
            break
        }
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        return [.banner, .sound, .badge]
    }
}
