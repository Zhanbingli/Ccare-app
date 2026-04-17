import Foundation
import UserNotifications

// MARK: - Lifecycle Reminders & Orphan Cleanup
// Manages inventory refill reminders, course-end reminders, and removal of
// notification requests that no longer correspond to active medications.

extension NotificationManager {

    // MARK: - Category identifiers

    static let refillCategoryId = "MED_REFILL"
    static let courseCategoryId = "MED_COURSE_END"

    // MARK: - Identifier helpers

    func refillIdentifier(for medID: UUID) -> String {
        "refill_\(medID.uuidString)"
    }

    func courseIdentifier(for medID: UUID) -> String {
        "course_\(medID.uuidString)"
    }

    /// A stable token that encodes both the medication ID and the course end date (day precision).
    /// Used to detect when a previously delivered catch-up reminder is still valid, avoiding
    /// re-delivery for the same course-end event.
    func courseToken(for medication: Medication, calendar: Calendar = .current) -> String? {
        guard let courseEndDate = medication.courseEndDate else { return nil }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd"
        let day = formatter.string(from: calendar.startOfDay(for: courseEndDate))
        return "\(medication.id.uuidString)_\(day)"
    }

    func storedCourseCatchUpToken(for medicationID: UUID) -> String? {
        let dict = defaults.dictionary(forKey: courseCatchUpTokensKey) as? [String: String] ?? [:]
        return dict[medicationID.uuidString]
    }

    func setStoredCourseCatchUpToken(_ token: String?, for medicationID: UUID) {
        var dict = defaults.dictionary(forKey: courseCatchUpTokensKey) as? [String: String] ?? [:]
        if let token {
            dict[medicationID.uuidString] = token
        } else {
            dict.removeValue(forKey: medicationID.uuidString)
        }
        defaults.set(dict, forKey: courseCatchUpTokensKey)
    }

    func removeLifecycleNotifications(identifier: String) {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [identifier])
        center.removeDeliveredNotifications(withIdentifiers: [identifier])
    }

    // MARK: - Budget reservation

    /// Number of notification slots to reserve for lifecycle (refill + course) reminders,
    /// capped at 10 so dose reminders always get the majority of the 64-slot budget.
    func lifecycleReservationSlots(for medications: [Medication]) -> Int {
        let refillSlots = medications.reduce(into: 0) { count, medication in
            if medication.daysOfSupplyRemaining != nil { count += 1 }
        }
        let courseSlots = medications.reduce(into: 0) { count, medication in
            if medication.courseEndDate != nil { count += 1 }
        }
        return min(10, refillSlots + courseSlots)
    }

    // MARK: - Refill reminders

    /// Schedules or cancels a refill reminder for `medication` based on remaining supply
    /// versus the user-configured threshold (default 7 days). Fires at 9 AM the next day.
    func scheduleRefillReminder(for medication: Medication) {
        let id = refillIdentifier(for: medication.id)
        guard let days = medication.daysOfSupplyRemaining else {
            removeLifecycleNotifications(identifier: id)
            return
        }
        let threshold = UserDefaults.standard.object(forKey: "prefs.refillThresholdDays") as? Int ?? 7
        let center = UNUserNotificationCenter.current()

        guard days <= threshold else {
            removeLifecycleNotifications(identifier: id)
            return
        }

        let content = UNMutableNotificationContent()
        content.title = NSLocalizedString("Refill Reminder", comment: "")
        if days == 0 {
            content.body = String(
                format: NSLocalizedString("%@ has run out. Time to refill!", comment: ""),
                medication.name
            )
        } else {
            content.body = String(
                format: NSLocalizedString("%@ has %lld days of supply left. Consider refilling soon.", comment: ""),
                medication.name,
                days
            )
        }
        content.sound = .default
        content.categoryIdentifier = Self.refillCategoryId
        content.userInfo = ["medicationID": medication.id.uuidString]

        // Fire at 9 AM tomorrow to avoid spamming
        var dateComps = Calendar.current.dateComponents([.year, .month, .day], from: Date())
        if let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: Date()) {
            dateComps = Calendar.current.dateComponents([.year, .month, .day], from: tomorrow)
        }
        dateComps.hour = 9
        dateComps.minute = 0
        let trigger = UNCalendarNotificationTrigger(dateMatching: dateComps, repeats: false)
        center.add(UNNotificationRequest(identifier: id, content: content, trigger: trigger), withCompletionHandler: nil)
    }

    func cancelRefillReminder(for medID: UUID) {
        removeLifecycleNotifications(identifier: refillIdentifier(for: medID))
    }

    // MARK: - Course-end reminders

    /// Schedules a course-end reminder that fires `threshold` days before `medication.courseEndDate`
    /// at 9 AM. If the preferred fire time has already passed and no catch-up token is stored for the
    /// current course end date, a catch-up notification fires 5 seconds from now instead.
    func scheduleCourseReminder(for medication: Medication, now: Date = Date()) {
        let id = courseIdentifier(for: medication.id)
        guard let courseEndDate = medication.courseEndDate else {
            setStoredCourseCatchUpToken(nil, for: medication.id)
            removeLifecycleNotifications(identifier: id)
            return
        }

        let threshold = UserDefaults.standard.object(forKey: "prefs.courseEndThresholdDays") as? Int ?? 3
        let calendar = Calendar.current
        let endDay = calendar.startOfDay(for: courseEndDate)
        guard let endOfCourseWindow = calendar.date(byAdding: .day, value: 1, to: endDay) else {
            setStoredCourseCatchUpToken(nil, for: medication.id)
            removeLifecycleNotifications(identifier: id)
            return
        }

        if now >= endOfCourseWindow {
            setStoredCourseCatchUpToken(nil, for: medication.id)
            removeLifecycleNotifications(identifier: id)
            // Cancel any pending dose/follow-up reminders for an ended course
            cancelAll(for: medication)
            return
        }

        let warningDay = calendar.date(byAdding: .day, value: -max(threshold, 0), to: endDay) ?? endDay
        let preferredFire = calendar.date(bySettingHour: 9, minute: 0, second: 0, of: warningDay) ?? warningDay
        let currentToken = courseToken(for: medication, calendar: calendar)
        let fireDate: Date
        if preferredFire > now {
            fireDate = preferredFire
        } else if storedCourseCatchUpToken(for: medication.id) == currentToken {
            removeLifecycleNotifications(identifier: id)
            return
        } else {
            fireDate = now.addingTimeInterval(5)
        }

        let content = UNMutableNotificationContent()
        content.title = NSLocalizedString("Course Reminder", comment: "")
        guard let courseState = medication.courseState(thresholdDays: threshold, reference: now, calendar: calendar) else {
            removeLifecycleNotifications(identifier: id)
            return
        }
        switch courseState {
        case .ended(let daysPast):
            content.body = String(
                format: NSLocalizedString("%@ reached its end date %lld days ago. Review whether it should continue.", comment: ""),
                medication.name, daysPast
            )
        case .endsToday:
            content.body = String(
                format: NSLocalizedString("%@ is scheduled to end today. Review whether it should continue.", comment: ""),
                medication.name
            )
        case .endingSoon(let daysRemaining):
            content.body = String(
                format: NSLocalizedString("%@ is scheduled to end in %lld days. Review the plan soon.", comment: ""),
                medication.name, daysRemaining
            )
        case .scheduled(let daysRemaining):
            content.body = String(
                format: NSLocalizedString("%@ is scheduled to end in %lld days. Review the plan soon.", comment: ""),
                medication.name, daysRemaining
            )
        }
        content.sound = .default
        content.categoryIdentifier = Self.courseCategoryId
        content.userInfo = ["medicationID": medication.id.uuidString]

        let comps = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: fireDate)
        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
        let req = UNNotificationRequest(identifier: id, content: content, trigger: trigger)
        setStoredCourseCatchUpToken(fireDate != preferredFire ? currentToken : nil, for: medication.id)
        UNUserNotificationCenter.current().add(req, withCompletionHandler: nil)
    }

    func cancelCourseReminder(for medID: UUID) {
        setStoredCourseCatchUpToken(nil, for: medID)
        removeLifecycleNotifications(identifier: courseIdentifier(for: medID))
    }

    /// Ensures refill and course reminders are in sync with the current medication list.
    /// Checks the pending notification count first and skips lifecycle scheduling
    /// if it would push the total past the iOS 64-notification limit.
    func checkLifecycleReminders(medications: [Medication], now: Date = Date()) {
        let center = UNUserNotificationCenter.current()
        center.getPendingNotificationRequests { [weak self] list in
            guard let self else { return }
            let lifecycleIds = Set(medications.flatMap { med -> [String] in
                [self.refillIdentifier(for: med.id), self.courseIdentifier(for: med.id)]
            })
            let nonLifecycleCount = list.filter { !lifecycleIds.contains($0.identifier) }.count
            let budget = max(0, SchedulingConfig.maxPendingNotifications - nonLifecycleCount)

            // Sort medications: those with urgent refill/course needs first
            let sorted = medications.sorted { a, b in
                (a.daysOfSupplyRemaining ?? Int.max) < (b.daysOfSupplyRemaining ?? Int.max)
            }
            var used = 0
            for med in sorted {
                if used < budget { self.scheduleRefillReminder(for: med); used += 1 }
                else { self.cancelRefillReminder(for: med.id) }
                if used < budget { self.scheduleCourseReminder(for: med, now: now); used += 1 }
                else { self.cancelCourseReminder(for: med.id) }
            }
        }
    }

    // MARK: - Orphan cleanup

    /// Removes any pending or delivered notification requests whose medication ID is no longer
    /// present in `validMedicationIDs`. Called on launch and on every `syncAll` invocation.
    func cleanOrphanedRequests(validMedicationIDs: Set<UUID>) {
        let center = UNUserNotificationCenter.current()
        let validStrings = Set(validMedicationIDs.map { $0.uuidString })
        center.getPendingNotificationRequests { list in
            let orphanIds = list
                .map { $0.identifier }
                .filter { id in
                    Self.isMedicationScoped(identifier: id) && !Self.hasValidMedication(identifier: id, validMedicationIDs: validStrings)
                }
            if !orphanIds.isEmpty { center.removePendingNotificationRequests(withIdentifiers: orphanIds) }
        }
        center.getDeliveredNotifications { notes in
            let orphanIds = notes
                .map { $0.request.identifier }
                .filter { id in
                    Self.isMedicationScoped(identifier: id) && !Self.hasValidMedication(identifier: id, validMedicationIDs: validStrings)
                }
            if !orphanIds.isEmpty { center.removeDeliveredNotifications(withIdentifiers: orphanIds) }
        }
    }
}
