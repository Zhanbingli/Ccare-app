import Foundation
import UserNotifications

@MainActor final class NotificationHandler: NSObject, UNUserNotificationCenterDelegate {
    weak var store: DataStore?

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        guard let idStr = response.notification.request.content.userInfo["medicationID"] as? String,
              let medID = UUID(uuidString: idStr) else { return }

        // Derive schedule time (HH:mm) from request identifier when possible:
        // Old pattern: "<medID>_HH_MM"; New pattern: "<medID>_yyyyMMdd_HH_MM"
        let requestId = response.notification.request.identifier
        var scheduleComps: DateComponents? = NotificationManager.scheduleComponents(from: response.notification.request.content.userInfo)
        if scheduleComps == nil {
            let parts = requestId.split(separator: "_")
            if parts.count >= 4, parts[0] == Substring(medID.uuidString) {
                if let h = Int(parts[2]), let m = Int(parts[3]), (0..<24).contains(h), (0..<60).contains(m) {
                    var c = DateComponents(); c.hour = h; c.minute = m; scheduleComps = c
                }
            } else if parts.count >= 3, parts[0] == Substring(medID.uuidString) { // legacy ids
                if let h = Int(parts[1]), let m = Int(parts[2]), (0..<24).contains(h), (0..<60).contains(m) {
                    var c = DateComponents(); c.hour = h; c.minute = m; scheduleComps = c
                }
            }
        }

        switch response.actionIdentifier {
        case NotificationManager.actionTaken:
            if let comps = scheduleComps {
                NotificationManager.shared.suppressToday(for: medID, timeComponents: comps)
                await MainActor.run { store?.upsertIntake(medicationID: medID, status: .taken, scheduleTime: comps) }
                if let med = store?.medications.first(where: { $0.id == medID }) {
                    NotificationManager.shared.cancelTodayInstance(for: medID, timeComponents: comps)
                    NotificationManager.shared.schedule(for: med)
                }
            } else {
                await MainActor.run { store?.upsertIntake(medicationID: medID, status: .taken, scheduleTime: nil) }
            }
            if let store = store { NotificationManager.shared.updateBadge(store: store) }
        case NotificationManager.actionSkip:
            if let comps = scheduleComps {
                NotificationManager.shared.suppressToday(for: medID, timeComponents: comps)
                await MainActor.run { store?.upsertIntake(medicationID: medID, status: .skipped, scheduleTime: comps) }
                if let med = store?.medications.first(where: { $0.id == medID }) {
                    NotificationManager.shared.cancelTodayInstance(for: medID, timeComponents: comps)
                    NotificationManager.shared.schedule(for: med)
                }
            } else {
                await MainActor.run { store?.upsertIntake(medicationID: medID, status: .skipped, scheduleTime: nil) }
            }
            if let store = store { NotificationManager.shared.updateBadge(store: store) }
        case NotificationManager.actionSnooze, NotificationManager.actionSnooze10:
            if let med = store?.medications.first(where: { $0.id == medID }) {
                NotificationManager.shared.scheduleSnooze(for: med, minutes: 10, scheduleTime: scheduleComps)
            } else {
                NotificationManager.shared.scheduleSnooze(for: medID, minutes: 10, scheduleTime: scheduleComps)
            }
            if let comps = scheduleComps {
                await MainActor.run { store?.upsertIntake(medicationID: medID, status: .snoozed, scheduleTime: comps) }
            } else {
                await MainActor.run { store?.upsertIntake(medicationID: medID, status: .snoozed, scheduleTime: nil) }
            }
            if let store = store { NotificationManager.shared.updateBadge(store: store) }
        case NotificationManager.actionSnooze30:
            if let med = store?.medications.first(where: { $0.id == medID }) {
                NotificationManager.shared.scheduleSnooze(for: med, minutes: 30, scheduleTime: scheduleComps)
            } else {
                NotificationManager.shared.scheduleSnooze(for: medID, minutes: 30, scheduleTime: scheduleComps)
            }
            if let comps = scheduleComps {
                await MainActor.run { store?.upsertIntake(medicationID: medID, status: .snoozed, scheduleTime: comps) }
            } else {
                await MainActor.run { store?.upsertIntake(medicationID: medID, status: .snoozed, scheduleTime: nil) }
            }
            if let store = store { NotificationManager.shared.updateBadge(store: store) }
        case NotificationManager.actionSnooze60:
            if let med = store?.medications.first(where: { $0.id == medID }) {
                NotificationManager.shared.scheduleSnooze(for: med, minutes: 60, scheduleTime: scheduleComps)
            } else {
                NotificationManager.shared.scheduleSnooze(for: medID, minutes: 60, scheduleTime: scheduleComps)
            }
            if let comps = scheduleComps {
                await MainActor.run { store?.upsertIntake(medicationID: medID, status: .snoozed, scheduleTime: comps) }
            } else {
                await MainActor.run { store?.upsertIntake(medicationID: medID, status: .snoozed, scheduleTime: nil) }
            }
            if let store = store { NotificationManager.shared.updateBadge(store: store) }
        default:
            break
        }
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        let id = notification.request.identifier
        if NotificationManager.shared.isSuppressedToday(requestIdentifier: id) {
            return []
        }
        return [.banner, .sound, .badge]
    }
}
