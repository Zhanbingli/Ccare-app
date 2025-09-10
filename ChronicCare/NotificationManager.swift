import Foundation
import UserNotifications

final class NotificationManager {
    static let shared = NotificationManager()
    private init() {}

    static let categoryId = "MED_REMINDER"
    static let actionTaken = "MED_TAKEN"
    static let actionSnooze = "MED_SNOOZE"
    static let actionSkip = "MED_SKIP"

    func requestAuthorization() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            if let error = error {
                print("Notification auth error: \(error)")
            } else {
                print("Notifications granted: \(granted)")
            }
        }
    }

    func registerCategories() {
        let taken = UNNotificationAction(identifier: Self.actionTaken, title: "Taken", options: [.authenticationRequired])
        let snooze = UNNotificationAction(identifier: Self.actionSnooze, title: "Snooze 10m", options: [])
        let skip = UNNotificationAction(identifier: Self.actionSkip, title: "Skip", options: [.destructive])
        let category = UNNotificationCategory(identifier: Self.categoryId, actions: [taken, snooze, skip], intentIdentifiers: [])
        UNUserNotificationCenter.current().setNotificationCategories([category])
    }

    func schedule(for medication: Medication) {
        let center = UNUserNotificationCenter.current()
        let id = medication.id.uuidString
        // Remove existing first
        center.removePendingNotificationRequests(withIdentifiers: [id])

        guard medication.remindersEnabled,
              let hour = medication.timeOfDay.hour,
              let minute = medication.timeOfDay.minute else { return }

        var dateComp = DateComponents()
        dateComp.hour = hour
        dateComp.minute = minute

        let content = UNMutableNotificationContent()
        content.title = medication.name
        content.body = "Dose: \(medication.dose)"
        content.sound = .default
        content.categoryIdentifier = Self.categoryId
        content.userInfo = ["medicationID": medication.id.uuidString]

        let trigger = UNCalendarNotificationTrigger(dateMatching: dateComp, repeats: true)
        let request = UNNotificationRequest(identifier: id, content: content, trigger: trigger)
        center.add(request) { error in
            if let error = error { print("Notification schedule error: \(error)") }
        }
    }

    func cancel(for medication: Medication) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [medication.id.uuidString])
    }

    func cancelAll(for medication: Medication) {
        let center = UNUserNotificationCenter.current()
        let ids = [medication.id.uuidString, "snooze_\(medication.id.uuidString)"]
        center.removePendingNotificationRequests(withIdentifiers: ids)
        center.removeDeliveredNotifications(withIdentifiers: ids)
    }

    func scheduleSnooze(for medicationID: UUID, minutes: Int = 10) {
        // Avoid stacking multiple snooze notifications for the same medication
        let snoozeId = "snooze_\(medicationID.uuidString)"
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [snoozeId])

        let content = UNMutableNotificationContent()
        content.title = "Snoozed Reminder"
        content.body = "Time to take your medication"
        content.sound = .default
        content.categoryIdentifier = Self.categoryId
        content.userInfo = ["medicationID": medicationID.uuidString]

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: TimeInterval(minutes * 60), repeats: false)
        let req = UNNotificationRequest(identifier: snoozeId, content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(req, withCompletionHandler: nil)
    }

    func scheduleSnooze(for medication: Medication, minutes: Int = 10) {
        let snoozeId = "snooze_\(medication.id.uuidString)"
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [snoozeId])

        let content = UNMutableNotificationContent()
        content.title = medication.name
        content.body = "Snoozed: \(medication.dose)"
        content.sound = .default
        content.categoryIdentifier = Self.categoryId
        content.userInfo = ["medicationID": medication.id.uuidString]

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: TimeInterval(minutes * 60), repeats: false)
        let req = UNNotificationRequest(identifier: snoozeId, content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(req, withCompletionHandler: nil)
    }
}
