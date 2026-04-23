import Foundation
import UserNotifications
import UIKit
import os

private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "ChronicCare", category: "Notifications")

// MARK: - NotificationManager
// Central singleton for all UNUserNotificationCenter interactions.
// Core responsibilities: scheduling dose reminders, badge computation, and
// notification category registration. Auxiliary responsibilities are implemented
// as extensions in:
//   • NotificationManager+Snooze.swift      — snooze count tracking
//   • NotificationManager+Suppression.swift — same-day suppression
//   • NotificationManager+Feedback.swift    — streak / miss-warning / caregiver prompts
//   • NotificationManager+Lifecycle.swift   — refill / course-end reminders & orphan cleanup

final class NotificationManager {

    // MARK: - Scheduling Constants
    enum SchedulingConfig {
        /// iOS caps pending local notifications at 64
        static let maxPendingNotifications = 64
        /// How many days ahead to pre-schedule dose reminders
        static let horizonDays = 120
        /// How many days ahead for adaptive follow-up reminders
        static let followUpHorizonDays = 3
        /// Max follow-up requests to schedule at once
        static let maxFollowUpRequests = 6
        /// Slots reserved for snooze/manual actions
        static let manualActionReserve = 2
        /// Seconds after scheduled time to still show a "due" (vs overdue) catch-up
        static let dueCatchUpWindowSeconds: TimeInterval = 90
    }

    static let shared = NotificationManager()
    private init() {}

    // MARK: - Notification Action / Category Identifiers

    static let categoryId = "MED_REMINDER"
    static let actionTaken = "MED_TAKEN"
    /// Backward compatibility alias for the 10-minute snooze action
    static let actionSnooze = "MED_SNOOZE"
    static let actionSnooze10 = "MED_SNOOZE_10"
    static let actionSnooze30 = "MED_SNOOZE_30"
    static let actionSnooze60 = "MED_SNOOZE_60"
    static let actionSkip = "MED_SKIP"

    private let maxAdaptiveFollowUpCount = 3

    // MARK: - Stored Properties (shared across all extensions)
    // Extensions cannot declare stored properties, so every UserDefaults key and
    // lazy/stored value lives here and is accessed via `self` or `defaults`.

    let defaults = UserDefaults.standard

    // Snooze count keys (used by NotificationManager+Snooze.swift)
    let snoozeCountKey = "snooze.today.counts"
    let snoozeCountDateKey = "snooze.today.date"

    // Suppression keys (used by NotificationManager+Suppression.swift)
    let suppressKey = "suppress.today.ids"
    let suppressDateKey = "suppress.today.date"

    // Lifecycle keys (used by NotificationManager+Lifecycle.swift)
    let courseCatchUpTokensKey = "course.reminder.catchup.tokens"

    // MARK: - Shared Helpers (used across multiple extensions)

    private var dueCatchUpWindow: TimeInterval { SchedulingConfig.dueCatchUpWindowSeconds }

    let isoFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    func todayKey(for date: Date = Date()) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: date)
    }

    // MARK: - Scheduling Budget Helpers

    private var primarySchedulingHorizonDays: Int { SchedulingConfig.horizonDays }
    private var followUpSchedulingHorizonDays: Int { SchedulingConfig.followUpHorizonDays }
    private var maxPendingNotificationBudget: Int { SchedulingConfig.maxPendingNotifications }
    private var maxScheduledFollowUpRequests: Int { SchedulingConfig.maxFollowUpRequests }
    private var manualActionReserveSlots: Int { SchedulingConfig.manualActionReserve }

    // MARK: - Internal Types

    private struct ScheduledDoseCandidate {
        let medication: Medication
        let timeComponents: DateComponents
        let doseDate: Date
        let fireDate: Date
        let strategy: AdaptiveReminderStrategy
    }

    // MARK: - Authorization & Category Registration

    func requestAuthorization() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            if let error = error {
                logger.error("Notification auth error: \(error.localizedDescription)")
            } else {
                logger.info("Notifications granted: \(granted)")
            }
        }
    }

    func registerCategories() {
        let taken   = UNNotificationAction(identifier: Self.actionTaken,   title: NSLocalizedString("Taken",      comment: ""), options: [])
        let snooze10 = UNNotificationAction(identifier: Self.actionSnooze10, title: NSLocalizedString("Snooze 10m", comment: ""), options: [])
        let snooze30 = UNNotificationAction(identifier: Self.actionSnooze30, title: NSLocalizedString("Snooze 30m", comment: ""), options: [])
        let snooze60 = UNNotificationAction(identifier: Self.actionSnooze60, title: NSLocalizedString("Snooze 60m", comment: ""), options: [])
        let skip    = UNNotificationAction(identifier: Self.actionSkip,    title: NSLocalizedString("Skip",       comment: ""), options: [.destructive])
        let doseCategory = UNNotificationCategory(
            identifier: Self.categoryId,
            actions: [taken, snooze10, snooze30, snooze60, skip],
            intentIdentifiers: []
        )
        let refillCategory = UNNotificationCategory(
            identifier: Self.refillCategoryId,
            actions: [],
            intentIdentifiers: []
        )
        let courseCategory = UNNotificationCategory(
            identifier: Self.courseCategoryId,
            actions: [],
            intentIdentifiers: []
        )
        UNUserNotificationCenter.current().setNotificationCategories([doseCategory, refillCategory, courseCategory])
    }

    func ensureAuthorization() async -> Bool {
        let settings = await fetchNotificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            return true
        case .denied:
            return false
        case .notDetermined:
            return await withCheckedContinuation { continuation in
                UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
                    continuation.resume(returning: granted)
                }
            }
        @unknown default:
            return false
        }
    }

    private func fetchNotificationSettings() async -> UNNotificationSettings {
        await withCheckedContinuation { continuation in
            UNUserNotificationCenter.current().getNotificationSettings { settings in
                continuation.resume(returning: settings)
            }
        }
    }

    // MARK: - Core Scheduling

    func isReminderEligible(_ medication: Medication) -> Bool {
        medication.remindersEnabled && medication.isAsNeeded != true && !medication.timesOfDay.isEmpty
    }

    /// Synchronises all pending notifications with the current medication and log state.
    /// Cancels orphans, removes inactive meds, reschedules eligible doses, and checks lifecycle reminders.
    func syncAll(medications: [Medication], intakeLogs: [IntakeLog], now: Date = Date()) {
        let validMedicationIDs = Set(medications.map { $0.id })
        cleanOrphanedRequests(validMedicationIDs: validMedicationIDs)

        let activeReminderIDs = Set(medications.filter(isReminderEligible).map { $0.id })
        medications.filter { !activeReminderIDs.contains($0.id) }.forEach { cancelAll(for: $0) }
        rescheduleDoseReminders(for: medications.filter(isReminderEligible), intakeLogs: intakeLogs, now: now)

        checkLifecycleReminders(medications: medications, now: now)
    }

    func schedule(for medication: Medication, intakeLogs: [IntakeLog], now: Date = Date()) {
        if isReminderEligible(medication) {
            rescheduleDoseReminders(for: [medication], intakeLogs: intakeLogs, now: now)
        } else {
            cancelAll(for: medication)
        }
    }

    private func rescheduleDoseReminders(for medications: [Medication], intakeLogs: [IntakeLog], now: Date) {
        let center = UNUserNotificationCenter.current()
        center.getPendingNotificationRequests { list in
            let validMedicationIDs = Set(medications.map { $0.id.uuidString })
            let ids = list.map { $0.identifier }.filter {
                Self.isManagedDoseReminder(identifier: $0, validMedicationIDs: validMedicationIDs)
            }
            if !ids.isEmpty { center.removePendingNotificationRequests(withIdentifiers: ids) }

            center.getDeliveredNotifications { notes in
                let delivered = notes.map { $0.request.identifier }.filter {
                    Self.isManagedDoseReminder(identifier: $0, validMedicationIDs: validMedicationIDs)
                }
                if !delivered.isEmpty { center.removeDeliveredNotifications(withIdentifiers: delivered) }
            }

            guard !medications.isEmpty else { return }

            let primaryCandidates = self.buildPrimaryCandidates(for: medications, intakeLogs: intakeLogs, now: now)
                .sorted {
                    if $0.fireDate == $1.fireDate {
                        return $0.medication.name.localizedCaseInsensitiveCompare($1.medication.name) == .orderedAscending
                    }
                    return $0.fireDate < $1.fireDate
                }
            let followUpBudget = self.followUpBudget(for: medications)
            let primaryBudget = self.primaryBudget(for: medications, followUpBudget: followUpBudget)
            let selectedPrimary = Array(primaryCandidates.prefix(primaryBudget))

            let selectedFollowUps = Array(
                self.buildFollowUpCandidates(from: selectedPrimary, now: now)
                    .sorted { $0.fireDate < $1.fireDate }
                    .prefix(followUpBudget)
            )

            // Merge primary and follow-up by fire date so badge numbers increment chronologically
            enum ScheduleItem {
                case primary(ScheduledDoseCandidate)
                case followUp(candidate: ScheduledDoseCandidate, attempt: Int, minutes: Int, fireDate: Date)

                var fireDate: Date {
                    switch self {
                    case .primary(let c): return c.fireDate
                    case .followUp(_, _, _, let d): return d
                    }
                }
            }

            var allItems: [ScheduleItem] = selectedPrimary.map { .primary($0) }
            allItems += selectedFollowUps.map { .followUp(candidate: $0.candidate, attempt: $0.attempt, minutes: $0.minutes, fireDate: $0.fireDate) }
            allItems.sort { $0.fireDate < $1.fireDate }

            // Reset badge counter so each scheduling cycle starts fresh
            self.nextBadgeNumber = 1

            for item in allItems {
                switch item {
                case .primary(let c):
                    self.schedulePrimaryReminder(for: c, center: center)
                case .followUp(let c, let attempt, let minutes, let fireDate):
                    self.scheduleFollowUpReminder(for: c, attempt: attempt, minutes: minutes, fireDate: fireDate, center: center)
                }
            }
        }
    }

    // MARK: - Instance-level Fire Date Computation

    func upcomingFireDates(
        for time: DateComponents,
        horizonDays: Int,
        from now: Date = Date(),
        catchUpWindow: TimeInterval = 0,
        calendar: Calendar = .current
    ) -> [Date] {
        guard let h = time.hour, let m = time.minute, horizonDays > 0 else { return [] }
        let startOfToday = calendar.startOfDay(for: now)
        var result: [Date] = []
        for offset in 0..<horizonDays {
            guard let day = calendar.date(byAdding: .day, value: offset, to: startOfToday),
                  let scheduled = calendar.date(bySettingHour: h, minute: m, second: 0, of: day) else { continue }
            if scheduled >= now || now.timeIntervalSince(scheduled) <= catchUpWindow {
                result.append(scheduled)
            }
        }
        return result
    }

    private func buildPrimaryCandidates(for medications: [Medication], intakeLogs: [IntakeLog], now: Date) -> [ScheduledDoseCandidate] {
        var uniqueCandidates: [String: ScheduledDoseCandidate] = [:]

        medications.forEach { medication in
            medication.timesOfDay.forEach { timeComponents in
                let strategy = AdaptiveReminderEngine.strategy(for: medication, intakeLogs: intakeLogs, now: now, scheduleTime: timeComponents)
                upcomingFireDates(
                    for: timeComponents,
                    horizonDays: primarySchedulingHorizonDays,
                    from: now,
                    catchUpWindow: dueCatchUpWindow
                )
                .filter { medication.isDoseActive(on: $0) }
                .forEach { doseDate in
                    guard Self.shouldScheduleDoseReminder(
                        medicationID: medication.id,
                        scheduleTime: timeComponents,
                        doseDate: doseDate,
                        intakeLogs: intakeLogs,
                        allowNilScheduleKey: medication.timesOfDay.count <= 1
                    ) else { return }

                    guard let primaryFireDate = resolvedPrimaryFireDate(
                        for: doseDate,
                        leadMinutes: strategy.leadMinutes,
                        now: now,
                        catchUpWindow: dueCatchUpWindow
                    ) else { return }

                    let candidate = ScheduledDoseCandidate(
                        medication: medication,
                        timeComponents: timeComponents,
                        doseDate: doseDate,
                        fireDate: primaryFireDate,
                        strategy: strategy
                    )
                    let identifier = instanceId(for: medication.id, date: doseDate, comps: timeComponents)
                    if let existing = uniqueCandidates[identifier], existing.fireDate <= candidate.fireDate {
                        return
                    }
                    uniqueCandidates[identifier] = candidate
                }
            }
        }

        return Array(uniqueCandidates.values)
    }

    /// Tracks the badge number to assign to each scheduled notification.
    /// Reset at the start of each rescheduleDoseReminders cycle, then incremented
    /// for each primary and follow-up notification in chronological order.
    private var nextBadgeNumber = 1

    private func schedulePrimaryReminder(for candidate: ScheduledDoseCandidate, center: UNUserNotificationCenter) {
        let calendar = Calendar.current
        let comps = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: candidate.fireDate)
        let id = instanceId(for: candidate.medication.id, date: candidate.doseDate, comps: candidate.timeComponents)
        let content = makeContent(
            for: candidate.medication,
            scheduleTime: candidate.timeComponents,
            scheduledDate: candidate.doseDate,
            riskLevel: candidate.strategy.riskLevel
        )
        content.badge = NSNumber(value: nextBadgeNumber)
        nextBadgeNumber += 1
        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
        center.add(UNNotificationRequest(identifier: id, content: content, trigger: trigger)) { error in
            if let error = error { logger.error("Notification schedule error: \(error.localizedDescription)") }
        }
    }

    private func buildFollowUpCandidates(
        from primaryCandidates: [ScheduledDoseCandidate],
        now: Date
    ) -> [(candidate: ScheduledDoseCandidate, attempt: Int, minutes: Int, fireDate: Date)] {
        let calendar = Calendar.current
        let horizonEnd = calendar.date(byAdding: .day, value: followUpSchedulingHorizonDays, to: now) ?? now
        return primaryCandidates.flatMap { candidate -> [(ScheduledDoseCandidate, Int, Int, Date)] in
            guard candidate.doseDate <= horizonEnd else { return [] }
            return candidate.strategy.followUpIntervals.enumerated().compactMap { index, minutes in
                let followUpDate = candidate.doseDate.addingTimeInterval(TimeInterval(minutes * 60))
                guard followUpDate > now else { return nil }
                return (candidate, index + 1, minutes, followUpDate)
            }
        }
    }

    private func scheduleFollowUpReminder(
        for candidate: ScheduledDoseCandidate,
        attempt: Int,
        minutes: Int,
        fireDate: Date,
        center: UNUserNotificationCenter
    ) {
        let calendar = Calendar.current
        let fuId = followUpId(index: attempt, for: candidate.medication.id, date: candidate.doseDate, comps: candidate.timeComponents)
        let fuContent = makeFollowUpContent(
            for: candidate.medication,
            scheduleTime: candidate.timeComponents,
            scheduledDate: candidate.doseDate,
            attempt: attempt,
            riskLevel: candidate.strategy.riskLevel
        )
        fuContent.badge = NSNumber(value: nextBadgeNumber)
        nextBadgeNumber += 1
        let fuComps = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: fireDate)
        let fuTrigger = UNCalendarNotificationTrigger(dateMatching: fuComps, repeats: false)
        center.add(UNNotificationRequest(identifier: fuId, content: fuContent, trigger: fuTrigger), withCompletionHandler: nil)
    }

    // MARK: - Budget Computation

    private func followUpBudget(for medications: [Medication]) -> Int {
        let reserved = lifecycleReservationSlots(for: medications) + manualActionReserveSlots
        let remaining = max(0, maxPendingNotificationBudget - reserved)
        // Count daily dose slots to estimate primary pressure
        let dailyDoseCount = medications.filter(isReminderEligible).reduce(0) { $0 + $1.timesOfDay.count }
        // If primary budget can't cover 3 days, yield all follow-up slots to primaries
        let minPrimaryDays = 3
        if dailyDoseCount > 0 && remaining < dailyDoseCount * minPrimaryDays {
            return 0
        }
        return min(maxScheduledFollowUpRequests, max(0, remaining / 6))
    }

    private func primaryBudget(for medications: [Medication], followUpBudget: Int) -> Int {
        let reserved = lifecycleReservationSlots(for: medications) + manualActionReserveSlots + followUpBudget
        return max(0, maxPendingNotificationBudget - reserved)
    }

    // MARK: - Fire Date Resolution

    private func adaptivePrimaryFireDate(for doseDate: Date, leadMinutes: Int, now: Date) -> Date {
        guard leadMinutes > 0 else { return doseDate }
        let reminderDate = doseDate.addingTimeInterval(TimeInterval(-leadMinutes * 60))
        return reminderDate > now ? reminderDate : doseDate
    }

    private func resolvedPrimaryFireDate(
        for doseDate: Date,
        leadMinutes: Int,
        now: Date,
        catchUpWindow: TimeInterval,
        calendar: Calendar = .current
    ) -> Date? {
        let desiredDate = adaptivePrimaryFireDate(for: doseDate, leadMinutes: leadMinutes, now: now)
        if desiredDate > now { return desiredDate }

        let age = now.timeIntervalSince(desiredDate)
        guard age >= 0,
              age <= catchUpWindow,
              calendar.isDate(desiredDate, inSameDayAs: now) else { return nil }
        return now.addingTimeInterval(2)
    }

    // MARK: - Notification Identifiers

    private func followUpId(index: Int, for medID: UUID, date: Date, comps: DateComponents) -> String {
        "followup_\(index)_\(instanceId(for: medID, date: date, comps: comps))"
    }

    func instanceId(for medID: UUID, date: Date, comps: DateComponents, calendar: Calendar = .current) -> String {
        let df = DateFormatter()
        df.dateFormat = "yyyyMMdd"
        let day = df.string(from: date)
        let h = String(format: "%02d", comps.hour ?? 0)
        let m = String(format: "%02d", comps.minute ?? 0)
        return "\(medID.uuidString)_\(day)_\(h)_\(m)"
    }

    private func timeKey(_ comps: DateComponents) -> String? {
        guard let h = comps.hour, let m = comps.minute else { return nil }
        return String(format: "%02d:%02d", h, m)
    }

    static func snoozeIdentifier(for medicationID: UUID, scheduleTime: DateComponents?) -> String {
        let base = "snooze_\(medicationID.uuidString)"
        guard let h = scheduleTime?.hour, let m = scheduleTime?.minute else { return base }
        return "\(base)_\(String(format: "%02d", h))_\(String(format: "%02d", m))"
    }

    // MARK: - Cancellation

    func cancelFollowUps(
        for medicationID: UUID,
        timeComponents: DateComponents,
        scheduledDate: Date? = nil,
        now: Date = Date()
    ) {
        let cal = Calendar.current
        let referenceDate = scheduledDate ?? now
        let day = cal.startOfDay(for: referenceDate)
        let baseId = instanceId(for: medicationID, date: day, comps: timeComponents)
        let ids = (1...maxAdaptiveFollowUpCount).map { "followup_\($0)_\(baseId)" }
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ids)
        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: ids)
    }

    func cancelSnooze(for medicationID: UUID, scheduleTime: DateComponents?) {
        let snoozeId = Self.snoozeIdentifier(for: medicationID, scheduleTime: scheduleTime)
        let legacyId = "snooze_\(medicationID.uuidString)"
        let ids = snoozeId == legacyId ? [legacyId] : [snoozeId, legacyId]
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: ids)
        center.removeDeliveredNotifications(withIdentifiers: ids)
    }

    func cancelDoseNotifications(
        for medicationID: UUID,
        timeComponents: DateComponents,
        scheduledDate: Date? = nil,
        now: Date = Date()
    ) {
        let referenceDate = scheduledDate ?? now
        cancelTodayInstance(for: medicationID, timeComponents: timeComponents, now: referenceDate)
        cancelFollowUps(for: medicationID, timeComponents: timeComponents, scheduledDate: referenceDate, now: referenceDate)
        cancelSnooze(for: medicationID, scheduleTime: timeComponents)
    }

    func cancelTodayInstance(for medicationID: UUID, timeComponents: DateComponents, now: Date = Date()) {
        let cal = Calendar.current
        let today = cal.startOfDay(for: now)
        let id = instanceId(for: medicationID, date: today, comps: timeComponents)
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [id])
        center.removeDeliveredNotifications(withIdentifiers: [id])
    }

    func cancelAll(for medication: Medication) {
        let center = UNUserNotificationCenter.current()
        let prefix = medication.id.uuidString
        Task {
            let pending = await center.pendingNotificationRequests()
            let pendingIDs = pending.map { $0.identifier }.filter {
                $0.hasPrefix(prefix) || $0.hasPrefix("snooze_\(prefix)") || $0.contains(prefix)
            }
            center.removePendingNotificationRequests(withIdentifiers: pendingIDs)

            let delivered = await center.deliveredNotifications()
            let deliveredIDs = delivered.map { $0.request.identifier }.filter {
                $0.hasPrefix(prefix) || $0.hasPrefix("snooze_\(prefix)") || $0.contains(prefix)
            }
            if !deliveredIDs.isEmpty { center.removeDeliveredNotifications(withIdentifiers: deliveredIDs) }
        }
    }

    // MARK: - Snooze Scheduling

    func scheduleSnooze(
        for medicationID: UUID,
        minutes: Int = 10,
        scheduleTime: DateComponents? = nil,
        scheduledDate: Date? = nil
    ) {
        let snoozeId = Self.snoozeIdentifier(for: medicationID, scheduleTime: scheduleTime)
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [snoozeId])
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ["snooze_\(medicationID.uuidString)"])

        let content = UNMutableNotificationContent()
        content.title = NSLocalizedString("Snoozed Reminder", comment: "")
        content.body = NSLocalizedString("Time to take your medication", comment: "")
        content.sound = .default
        content.categoryIdentifier = Self.categoryId
        var info: [String: Any] = ["medicationID": medicationID.uuidString]
        if let h = scheduleTime?.hour, let m = scheduleTime?.minute {
            info["scheduleHour"] = h
            info["scheduleMinute"] = m
        }
        let fireDate = Date().addingTimeInterval(TimeInterval(minutes * 60))
        let originalScheduledDate = scheduledDate ?? inferredScheduledDate(for: scheduleTime, relativeTo: Date()) ?? fireDate
        info["scheduledDate"] = isoFormatter.string(from: originalScheduledDate)
        content.userInfo = info
        content.threadIdentifier = medicationID.uuidString
        if #available(iOS 15.0, *) { content.interruptionLevel = .timeSensitive }
        if #available(iOS 15.0, *) { content.relevanceScore = 0.8 }

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: TimeInterval(minutes * 60), repeats: false)
        UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: snoozeId, content: content, trigger: trigger),
            withCompletionHandler: nil
        )
    }

    func scheduleSnooze(
        for medication: Medication,
        minutes: Int = 10,
        scheduleTime: DateComponents? = nil,
        scheduledDate: Date? = nil
    ) {
        let snoozeId = Self.snoozeIdentifier(for: medication.id, scheduleTime: scheduleTime)
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [snoozeId])
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ["snooze_\(medication.id.uuidString)"])

        let fireDate = Date().addingTimeInterval(TimeInterval(minutes * 60))
        let originalScheduledDate = scheduledDate ?? inferredScheduledDate(for: scheduleTime, relativeTo: Date()) ?? fireDate
        let content = makeContent(for: medication, scheduleTime: scheduleTime, scheduledDate: originalScheduledDate, isSnooze: true)

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: TimeInterval(minutes * 60), repeats: false)
        UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: snoozeId, content: content, trigger: trigger),
            withCompletionHandler: nil
        )
    }

    private func inferredScheduledDate(for scheduleTime: DateComponents?, relativeTo date: Date) -> Date? {
        guard let hour = scheduleTime?.hour, let minute = scheduleTime?.minute else { return nil }
        return Calendar.current.date(bySettingHour: hour, minute: minute, second: 0, of: date)
    }

    // MARK: - Notification Content Building

    private func makeFollowUpContent(
        for medication: Medication,
        scheduleTime: DateComponents?,
        scheduledDate: Date?,
        attempt: Int,
        riskLevel: AdaptiveReminderStrategy.RiskLevel
    ) -> UNMutableNotificationContent {
        let content = UNMutableNotificationContent()
        content.title = medication.name
        let urgency: String
        switch attempt {
        case 1:  urgency = NSLocalizedString("Haven't taken it yet?",              comment: "follow-up reminder")
        case 2:  urgency = NSLocalizedString("Reminder: still not taken",          comment: "follow-up reminder")
        default: urgency = NSLocalizedString("Urgent: please take your medication", comment: "follow-up reminder")
        }
        var bodyText = "\(urgency) — \(medication.dose)"
        if let fi = medication.foodInstruction { bodyText += " · \(fi.shortLabel)" }
        content.body = bodyText
        content.sound = .default
        content.categoryIdentifier = Self.categoryId
        var info: [String: Any] = ["medicationID": medication.id.uuidString]
        if let comps = scheduleTime, let h = comps.hour, let m = comps.minute {
            info["scheduleHour"] = h
            info["scheduleMinute"] = m
        }
        if let scheduledDate { info["scheduledDate"] = isoFormatter.string(from: scheduledDate) }
        content.userInfo = info
        content.threadIdentifier = medication.id.uuidString
        if #available(iOS 15.0, *) { content.interruptionLevel = riskLevel == .low ? .active : .timeSensitive }
        if #available(iOS 15.0, *) { content.relevanceScore = min(baseRelevanceScore(for: riskLevel) + Double(attempt) * 0.03, 1.0) }
        return content
    }

    func makeContent(
        for medication: Medication,
        scheduleTime: DateComponents?,
        scheduledDate: Date? = nil,
        isSnooze: Bool = false,
        riskLevel: AdaptiveReminderStrategy.RiskLevel = .medium
    ) -> UNMutableNotificationContent {
        let content = UNMutableNotificationContent()
        content.title = medication.name
        var bodyText: String
        if isSnooze {
            bodyText = String(format: NSLocalizedString("Snoozed: %@", comment: ""), medication.dose)
        } else if let comps = scheduleTime, let h = comps.hour, let m = comps.minute,
                  let timeDate = Calendar.current.date(bySettingHour: h, minute: m, second: 0, of: Date()) {
            let formatter = DateFormatter()
            formatter.timeStyle = .short
            let timeStr = formatter.string(from: timeDate)
            bodyText = String(format: NSLocalizedString("%@ — scheduled for %@", comment: "dose — scheduled for time"), medication.dose, timeStr)
        } else {
            bodyText = String(format: NSLocalizedString("Dose: %@", comment: ""), medication.dose)
        }
        if let fi = medication.foodInstruction { content.subtitle = "⚠ \(fi.displayName)" }
        content.body = bodyText
        content.sound = .default
        content.categoryIdentifier = Self.categoryId
        var info: [String: Any] = ["medicationID": medication.id.uuidString]
        if let comps = scheduleTime, let h = comps.hour, let m = comps.minute {
            info["scheduleHour"] = h
            info["scheduleMinute"] = m
        }
        if let scheduledDate { info["scheduledDate"] = isoFormatter.string(from: scheduledDate) }
        content.userInfo = info
        content.threadIdentifier = medication.id.uuidString
        if #available(iOS 15.0, *) { content.interruptionLevel = riskLevel == .low ? .active : .timeSensitive }
        if #available(iOS 15.0, *) { content.relevanceScore = baseRelevanceScore(for: riskLevel) }
        return content
    }

    private func baseRelevanceScore(for riskLevel: AdaptiveReminderStrategy.RiskLevel) -> Double {
        switch riskLevel {
        case .low:    return 0.75
        case .medium: return 0.9
        case .high:   return 1.0
        }
    }

    // MARK: - Badge Computation

    func updateBadge(store: DataStore) {
        Task {
            let snapshot: ([Medication], [IntakeLog]) = await MainActor.run { (store.medications, store.intakeLogs) }
            let grace = UserDefaults.standard.object(forKey: "prefs.graceMinutes") as? Int ?? 30
            let activeSnoozes = await activeSnoozeIdentifiers()
            let count = Self.computeOutstandingCount(
                medications: snapshot.0,
                intakeLogs: snapshot.1,
                graceMinutes: grace,
                activeSnoozes: activeSnoozes
            )
            await MainActor.run {
                UIApplication.shared.applicationIconBadgeNumber = count
            }
        }
    }

    private func activeSnoozeIdentifiers() async -> Set<String> {
        let center = UNUserNotificationCenter.current()
        let pending = await withCheckedContinuation { continuation in
            center.getPendingNotificationRequests { list in
                continuation.resume(returning: list.map { $0.identifier })
            }
        }
        let delivered = await withCheckedContinuation { continuation in
            center.getDeliveredNotifications { notes in
                continuation.resume(returning: notes.map { $0.request.identifier })
            }
        }
        let all = (pending + delivered).filter { $0.hasPrefix("snooze_") }
        return Set(all)
    }

    static func computeOutstandingCount(
        medications: [Medication],
        intakeLogs: [IntakeLog],
        graceMinutes: Int,
        activeSnoozes: Set<String> = [],
        now: Date = Date()
    ) -> Int {
        let cal = Calendar.current
        let todayStart = cal.startOfDay(for: now)
        var total = 0
        for med in medications where med.remindersEnabled && med.isAsNeeded != true {
            let times = med.timesOfDay.compactMap { comps -> (Int, Int)? in
                guard let h = comps.hour, let m = comps.minute else { return nil }
                return (h, m)
            }
            for (h, m) in times {
                guard let sched = cal.date(bySettingHour: h, minute: m, second: 0, of: now) else { continue }
                guard med.isDoseActive(on: sched) else { continue }
                // Count as outstanding once the scheduled time has arrived
                if now < sched { continue }
                let key = String(format: "%02d:%02d", h, m)
                let allowNil = times.count <= 1
                let logs = intakeLogs
                    .filter { log in
                        guard log.medicationID == med.id else { return false }
                        let d = log.date
                        guard let dayEnd = cal.date(byAdding: .day, value: 1, to: todayStart) else { return false }
                        return d >= todayStart
                            && d < dayEnd
                            && (log.scheduleKey == key || (allowNil && log.scheduleKey == nil))
                    }
                    .sorted { $0.date > $1.date }
                if let last = logs.first {
                    if last.status == .taken || last.status == .skipped { continue }
                    if last.status == .snoozed {
                        var comps = DateComponents(); comps.hour = h; comps.minute = m
                        let snoozeId = snoozeIdentifier(for: med.id, scheduleTime: comps)
                        if activeSnoozes.contains(snoozeId) { continue }
                    }
                }
                total += 1
            }
        }
        return total
    }

    // MARK: - Badge Auto-Refresh Observers

    private var observersInstalled = false

    func startBadgeAutoRefresh(store: DataStore) {
        guard !observersInstalled else { return }
        observersInstalled = true
        let center = NotificationCenter.default

        let syncAndRefresh: (Notification) -> Void = { [weak self] _ in
            self?.updateBadge(store: store)
            Task { @MainActor in
                let meds = store.medications
                let logs = store.intakeLogs
                self?.syncAll(medications: meds, intakeLogs: logs)
            }
        }

        center.addObserver(forName: UIApplication.significantTimeChangeNotification, object: nil, queue: .main, using: syncAndRefresh)
        center.addObserver(forName: NSNotification.Name.NSCalendarDayChanged, object: nil, queue: .main, using: syncAndRefresh)
        center.addObserver(forName: NSNotification.Name.NSSystemTimeZoneDidChange, object: nil, queue: .main, using: syncAndRefresh)
    }
}

// MARK: - Identifier Parsing Utilities

extension NotificationManager {

    static func medicationID(from requestIdentifier: String) -> String? {
        let parts = requestIdentifier.split(separator: "_")

        if let first = parts.first, UUID(uuidString: String(first)) != nil {
            return String(first)
        }
        if parts.count >= 2, parts[0] == "snooze", UUID(uuidString: String(parts[1])) != nil {
            return String(parts[1])
        }
        if parts.count >= 3, parts[0] == "followup", UUID(uuidString: String(parts[2])) != nil {
            return String(parts[2])
        }
        if parts.count >= 3, parts[0] == "miss", parts[1] == "warn", UUID(uuidString: String(parts[2])) != nil {
            return String(parts[2])
        }
        if parts.count >= 2, parts[0] == "refill", UUID(uuidString: String(parts[1])) != nil {
            return String(parts[1])
        }
        if parts.count >= 2, parts[0] == "course", UUID(uuidString: String(parts[1])) != nil {
            return String(parts[1])
        }
        return nil
    }

    static func isMedicationScoped(identifier: String) -> Bool {
        medicationID(from: identifier) != nil
    }

    static func hasValidMedication(identifier: String, validMedicationIDs: Set<String>) -> Bool {
        guard let medicationID = medicationID(from: identifier) else { return true }
        return validMedicationIDs.contains(medicationID)
    }

    static func isDoseReminder(identifier: String, medicationID: UUID) -> Bool {
        let medID = medicationID.uuidString
        if identifier.hasPrefix("\(medID)_") { return true }
        if identifier.hasPrefix("followup_"), identifier.contains("_\(medID)_") { return true }
        if identifier == "snooze_\(medID)" { return true }
        if identifier.hasPrefix("snooze_\(medID)_") { return true }
        return false
    }

    static func isManagedDoseReminder(identifier: String, validMedicationIDs: Set<String>) -> Bool {
        guard let medicationID = medicationID(from: identifier) else { return false }
        guard validMedicationIDs.contains(medicationID) else { return false }
        if identifier.hasPrefix("\(medicationID)_") { return true }
        if identifier.hasPrefix("followup_"), identifier.contains("_\(medicationID)_") { return true }
        return false
    }

    static func scheduleComponents(from userInfo: [AnyHashable: Any]) -> DateComponents? {
        guard let hour = userInfo["scheduleHour"] as? Int,
              let minute = userInfo["scheduleMinute"] as? Int,
              (0..<24).contains(hour),
              (0..<60).contains(minute) else { return nil }
        var comps = DateComponents()
        comps.hour = hour
        comps.minute = minute
        return comps
    }

    static func scheduledDate(from userInfo: [AnyHashable: Any]) -> Date? {
        guard let str = userInfo["scheduledDate"] as? String else { return nil }
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f.date(from: str)
    }

    static func scheduledDate(fromIdentifier identifier: String) -> Date? {
        let parts = identifier.split(separator: "_")
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd"

        // Primary: <UUID>_yyyyMMdd_HH_MM  → parts[1] is date
        if parts.count >= 4, parts[0] != "snooze", parts[0] != "followup" {
            return formatter.date(from: String(parts[1]))
        }
        // followup_<attempt>_<UUID>_yyyyMMdd_HH_MM → parts[3] is date
        if parts.count >= 6, parts[0] == "followup" {
            return formatter.date(from: String(parts[3]))
        }
        // snooze_<UUID>_HH_MM → no date component, return nil (caller uses userInfo)
        return nil
    }

    static func shouldScheduleDoseReminder(
        medicationID: UUID,
        scheduleTime: DateComponents,
        doseDate: Date,
        intakeLogs: [IntakeLog],
        allowNilScheduleKey: Bool,
        calendar: Calendar = .current
    ) -> Bool {
        latestDoseOutcome(
            medicationID: medicationID,
            scheduleTime: scheduleTime,
            doseDate: doseDate,
            intakeLogs: intakeLogs,
            allowNilScheduleKey: allowNilScheduleKey,
            calendar: calendar
        ) == nil
    }

    static func latestDoseOutcome(
        medicationID: UUID,
        scheduleTime: DateComponents,
        doseDate: Date,
        intakeLogs: [IntakeLog],
        allowNilScheduleKey: Bool,
        calendar: Calendar = .current
    ) -> IntakeStatus? {
        guard let h = scheduleTime.hour, let m = scheduleTime.minute else { return nil }
        let key = String(format: "%02d:%02d", h, m)
        let dayStart = calendar.startOfDay(for: doseDate)
        guard let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) else { return nil }

        return intakeLogs
            .filter { log in
                log.medicationID == medicationID
                    && log.date >= dayStart
                    && log.date < dayEnd
                    && (log.scheduleKey == key || (allowNilScheduleKey && log.scheduleKey == nil))
            }
            .sorted { $0.effectiveRecordedAt > $1.effectiveRecordedAt }
            .first?
            .status
    }
}
