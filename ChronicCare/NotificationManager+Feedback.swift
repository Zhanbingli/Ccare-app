import Foundation
import UserNotifications

// MARK: - Behavioral Feedback Notifications
// Proactive notifications sent in response to user adherence patterns:
// streak milestones, missed-dose warnings, and caregiver text prompts.
// These fire immediately (1–2 second trigger) and do not use the dose reminder category.

extension NotificationManager {

    private static let behaviorCategoryId = "BEHAVIOR_FEEDBACK"

    /// Sends a streak congratulation when the user reaches a notable milestone (3, 7, 14, 30 days or multiples of 30).
    func sendStreakMilestone(streak: Int, medicationName: String) {
        guard streak > 0 && (streak == 3 || streak == 7 || streak == 14 || streak == 30 || streak % 30 == 0) else { return }
        let content = UNMutableNotificationContent()
        content.title = NSLocalizedString("Medication routine maintained", comment: "Calm adherence milestone notification title")
        content.body = String(format: NSLocalizedString("%@ has been logged consistently for %lld days.", comment: "Calm adherence milestone notification body"), medicationName, streak)
        content.sound = .default
        if #available(iOS 15.0, *) { content.interruptionLevel = .passive }
        let id = "streak_\(streak)_\(todayKey())"
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        let req = UNNotificationRequest(identifier: id, content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(req, withCompletionHandler: nil)
    }

    /// Sends a warning notification when the user has missed a medication for two or more consecutive days.
    func sendMissWarning(for medicationID: UUID, missedDays: Int, medicationName: String) {
        guard missedDays >= 2 else { return }
        let content = UNMutableNotificationContent()
        content.title = NSLocalizedString("Missed Medication", comment: "")
        content.body = String(
            format: NSLocalizedString("You haven't taken %@ for %lld days. Please take it or talk to your doctor.", comment: ""),
            medicationName,
            missedDays
        )
        content.sound = .default
        if #available(iOS 15.0, *) { content.interruptionLevel = .timeSensitive }
        let id = "miss_warn_\(medicationID.uuidString)_\(todayKey())"
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        let req = UNNotificationRequest(identifier: id, content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(req, withCompletionHandler: nil)
    }

    /// Prompts the user to text a named caregiver about missed-dose support.
    func sendCaregiverReminder(caregiverID: UUID, caregiverName: String, medicationName: String, missedDays: Int) {
        let content = UNMutableNotificationContent()
        content.title = NSLocalizedString("Notify caregiver", comment: "Caregiver notification title")
        content.body = String(
            format: NSLocalizedString("You haven't taken %@ for %lld days. Open caregiver support to text %@.", comment: "Caregiver notification body"),
            medicationName,
            missedDays,
            caregiverName
        )
        content.sound = .default
        if #available(iOS 15.0, *) { content.interruptionLevel = .active }
        let id = "caregiver_\(caregiverID.uuidString)_\(todayKey())"
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 2, repeats: false)
        let req = UNNotificationRequest(identifier: id, content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(req, withCompletionHandler: nil)
    }
}
