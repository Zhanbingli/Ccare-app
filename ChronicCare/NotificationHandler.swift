import Foundation
import UserNotifications

@MainActor final class NotificationHandler: NSObject, UNUserNotificationCenterDelegate {
    weak var store: DataStore?

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        if let visitIDString = response.notification.request.content.userInfo["doctorVisitID"] as? String,
           let visitID = UUID(uuidString: visitIDString) {
            await MainActor.run {
                NotificationCenter.default.post(name: Notification.Name("openVisitSnapshot"), object: visitID)
            }
            return
        }

        guard let idStr = response.notification.request.content.userInfo["medicationID"] as? String,
              let medID = UUID(uuidString: idStr) else { return }
        let actionTimestamp = Date()

        // Derive schedule time (HH:mm) from request identifier when possible:
        // Old pattern: "<medID>_HH_MM"; New pattern: "<medID>_yyyyMMdd_HH_MM"
        let requestId = response.notification.request.identifier
        var scheduleComps: DateComponents? = NotificationManager.scheduleComponents(from: response.notification.request.content.userInfo)
        let scheduledDate = NotificationManager.scheduledDate(from: response.notification.request.content.userInfo) ?? NotificationManager.scheduledDate(fromIdentifier: requestId)
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

        func logDate(from comps: DateComponents?, fallback: Date = Date()) -> Date {
            guard let comps, let schedDate = scheduledDate else { return fallback }
            var components = comps
            let cal = Calendar.current
            let dayParts = cal.dateComponents([.year, .month, .day], from: schedDate)
            components.year = dayParts.year
            components.month = dayParts.month
            components.day = dayParts.day
            return cal.date(from: components) ?? fallback
        }

        // Ignore actions for medications that have been deleted
        let medExists = await MainActor.run { store?.medications.contains(where: { $0.id == medID }) ?? false }
        guard medExists else { return }

        switch response.actionIdentifier {
        case UNNotificationDefaultActionIdentifier:
            await MainActor.run {
                NotificationCenter.default.post(name: Notification.Name("openMedicationDetail"), object: medID)
            }
            if let store = store { await MainActor.run { store.syncNotifications() } }
        case NotificationManager.actionTaken:
            if let comps = scheduleComps {
                let logAt = logDate(from: comps)
                if Calendar.current.isDateInToday(logAt) {
                    NotificationManager.shared.suppressToday(for: medID, timeComponents: comps)
                }
                await MainActor.run {
                    store?.recordTakenDose(
                        medicationID: medID,
                        scheduleTime: comps,
                        at: logAt,
                        scheduledDate: scheduledDate ?? logAt,
                        recordedAt: actionTimestamp
                    )
                }
                if let store, store.medications.contains(where: { $0.id == medID }) {
                    NotificationManager.shared.cancelDoseNotifications(for: medID, timeComponents: comps, scheduledDate: scheduledDate ?? logAt, now: logAt)
                }
            } else {
                await MainActor.run {
                    store?.recordTakenDose(medicationID: medID, scheduleTime: nil, recordedAt: actionTimestamp)
                }
            }
            if let store = store { await MainActor.run { store.syncNotifications() } }
        case NotificationManager.actionSkip:
            if let comps = scheduleComps {
                let logAt = logDate(from: comps)
                if Calendar.current.isDateInToday(logAt) {
                    NotificationManager.shared.suppressToday(for: medID, timeComponents: comps)
                }
                await MainActor.run {
                    store?.upsertIntake(
                        medicationID: medID,
                        status: .skipped,
                        scheduleTime: comps,
                        at: logAt,
                        scheduledDate: scheduledDate ?? logAt,
                        recordedAt: actionTimestamp
                    )
                }
                if let store, store.medications.contains(where: { $0.id == medID }) {
                    NotificationManager.shared.cancelDoseNotifications(for: medID, timeComponents: comps, scheduledDate: scheduledDate ?? logAt, now: logAt)
                }
            } else {
                await MainActor.run { store?.upsertIntake(medicationID: medID, status: .skipped, scheduleTime: nil, recordedAt: actionTimestamp) }
            }
            if let store = store { await MainActor.run { store.syncNotifications() } }
        case NotificationManager.actionSnooze, NotificationManager.actionSnooze10,
             NotificationManager.actionSnooze30, NotificationManager.actionSnooze60:
            // Data-driven snooze escalation via MedicationRules
            let count = NotificationManager.shared.snoozeCount(for: medID, scheduleTime: scheduleComps)
            let snoozeResult = await MainActor.run { MedicationRules.nextSnooze(for: medID, currentSnoozeCount: count) }
            switch snoozeResult {
            case .snooze(let minutes):
                if let comps = scheduleComps {
                    NotificationManager.shared.cancelFollowUps(for: medID, timeComponents: comps, scheduledDate: scheduledDate)
                }
                NotificationManager.shared.incrementSnoozeCount(for: medID, scheduleTime: scheduleComps)
                if let med = store?.medications.first(where: { $0.id == medID }) {
                    NotificationManager.shared.scheduleSnooze(for: med, minutes: minutes, scheduleTime: scheduleComps, scheduledDate: scheduledDate)
                } else {
                    NotificationManager.shared.scheduleSnooze(for: medID, minutes: minutes, scheduleTime: scheduleComps, scheduledDate: scheduledDate)
                }
                if let comps = scheduleComps {
                    let logAt = logDate(from: comps)
                    if Calendar.current.isDateInToday(logAt) {
                        NotificationManager.shared.suppressToday(for: medID, timeComponents: comps)
                    }
                    await MainActor.run {
                        store?.upsertIntake(
                            medicationID: medID,
                            status: .snoozed,
                            scheduleTime: comps,
                            at: logAt,
                            scheduledDate: scheduledDate ?? logAt,
                            recordedAt: actionTimestamp
                        )
                    }
                } else {
                    await MainActor.run { store?.upsertIntake(medicationID: medID, status: .snoozed, scheduleTime: nil, recordedAt: actionTimestamp) }
                }
            case .exhausted:
                if let comps = scheduleComps {
                    let logAt = logDate(from: comps)
                    if Calendar.current.isDateInToday(logAt) {
                        NotificationManager.shared.suppressToday(for: medID, timeComponents: comps)
                    }
                    await MainActor.run {
                        store?.upsertIntake(
                            medicationID: medID,
                            status: .skipped,
                            scheduleTime: comps,
                            at: logAt,
                            scheduledDate: scheduledDate ?? logAt,
                            recordedAt: actionTimestamp
                        )
                    }
                    if let store, store.medications.contains(where: { $0.id == medID }) {
                        NotificationManager.shared.cancelDoseNotifications(for: medID, timeComponents: comps, scheduledDate: scheduledDate ?? logAt, now: logAt)
                    }
                } else {
                    await MainActor.run { store?.upsertIntake(medicationID: medID, status: .skipped, scheduleTime: nil, recordedAt: actionTimestamp) }
                }
            }
            if let store = store { await MainActor.run { store.syncNotifications() } }
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
