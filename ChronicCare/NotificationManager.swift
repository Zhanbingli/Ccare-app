import Foundation
import UserNotifications
import UIKit

final class NotificationManager {
    static let shared = NotificationManager()
    private init() {}

    static let categoryId = "MED_REMINDER"
    static let actionTaken = "MED_TAKEN"
    // Backward compatibility (10m)
    static let actionSnooze = "MED_SNOOZE"
    static let actionSnooze10 = "MED_SNOOZE_10"
    static let actionSnooze30 = "MED_SNOOZE_30"
    static let actionSnooze60 = "MED_SNOOZE_60"
    static let actionSkip = "MED_SKIP"
    private let maxAdaptiveFollowUpCount = 3

    // MARK: - Snooze escalation (count tracking only — rules come from MedicationRuleStore)
    private let snoozeCountKey = "snooze.today.counts"
    private let snoozeCountDateKey = "snooze.today.date"

    func snoozeCount(for medicationID: UUID, scheduleTime: DateComponents?) -> Int {
        resetSnoozeCountsIfNewDay()
        let key = snoozeTrackingKey(for: medicationID, scheduleTime: scheduleTime)
        let dict = defaults.dictionary(forKey: snoozeCountKey) as? [String: Int] ?? [:]
        return dict[key] ?? 0
    }

    func incrementSnoozeCount(for medicationID: UUID, scheduleTime: DateComponents?) {
        resetSnoozeCountsIfNewDay()
        let key = snoozeTrackingKey(for: medicationID, scheduleTime: scheduleTime)
        var dict = defaults.dictionary(forKey: snoozeCountKey) as? [String: Int] ?? [:]
        dict[key] = (dict[key] ?? 0) + 1
        defaults.set(dict, forKey: snoozeCountKey)
        defaults.set(todayKey(), forKey: snoozeCountDateKey)
    }

    func resetSnoozeCount(for medicationID: UUID, scheduleTime: DateComponents?) {
        let key = snoozeTrackingKey(for: medicationID, scheduleTime: scheduleTime)
        var dict = defaults.dictionary(forKey: snoozeCountKey) as? [String: Int] ?? [:]
        dict.removeValue(forKey: key)
        defaults.set(dict, forKey: snoozeCountKey)
    }

    private func snoozeTrackingKey(for medicationID: UUID, scheduleTime: DateComponents?) -> String {
        guard let h = scheduleTime?.hour, let m = scheduleTime?.minute else {
            return medicationID.uuidString
        }
        return "\(medicationID.uuidString)_\(String(format: "%02d", h))_\(String(format: "%02d", m))"
    }

    private func resetSnoozeCountsIfNewDay() {
        let day = todayKey()
        if defaults.string(forKey: snoozeCountDateKey) != day {
            defaults.removeObject(forKey: snoozeCountKey)
            defaults.set(day, forKey: snoozeCountDateKey)
        }
    }

    // MARK: - Behavioral feedback notifications
    private static let behaviorCategoryId = "BEHAVIOR_FEEDBACK"

    func sendStreakMilestone(streak: Int, medicationName: String) {
        guard streak > 0 && (streak == 3 || streak == 7 || streak == 14 || streak == 30 || streak % 30 == 0) else { return }
        let content = UNMutableNotificationContent()
        content.title = "🔥 \(streak) " + NSLocalizedString("day streak", comment: "")
        content.body = String(format: NSLocalizedString("Great job taking %@ consistently!", comment: ""), medicationName)
        content.sound = .default
        if #available(iOS 15.0, *) { content.interruptionLevel = .passive }
        let id = "streak_\(streak)_\(todayKey())"
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        let req = UNNotificationRequest(identifier: id, content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(req, withCompletionHandler: nil)
    }

    func sendMissWarning(for medicationID: UUID, missedDays: Int, medicationName: String) {
        guard missedDays >= 2 else { return }
        let content = UNMutableNotificationContent()
        content.title = NSLocalizedString("Missed Medication", comment: "")
        content.body = String(format: NSLocalizedString("You haven't taken %@ for %lld days. Please take it or talk to your doctor.", comment: ""), medicationName, missedDays)
        content.sound = .default
        if #available(iOS 15.0, *) { content.interruptionLevel = .timeSensitive }
        let id = "miss_warn_\(medicationID.uuidString)_\(todayKey())"
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        let req = UNNotificationRequest(identifier: id, content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(req, withCompletionHandler: nil)
    }

    func sendCaregiverReminder(caregiverID: UUID, caregiverName: String, medicationName: String, missedDays: Int) {
        let content = UNMutableNotificationContent()
        content.title = NSLocalizedString("Share with Caregiver?", comment: "")
        content.body = String(format: NSLocalizedString("You haven't taken %@ for %lld days. Would you like to share your status with %@?", comment: ""), medicationName, missedDays, caregiverName)
        content.sound = .default
        if #available(iOS 15.0, *) { content.interruptionLevel = .active }
        let id = "caregiver_\(caregiverID.uuidString)_\(todayKey())"
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 2, repeats: false)
        let req = UNNotificationRequest(identifier: id, content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(req, withCompletionHandler: nil)
    }

    // MARK: - Same-day suppression (to avoid duplicate reminders after early Taken/Skip)
    private let defaults = UserDefaults.standard
    private let suppressKey = "suppress.today.ids"
    private let suppressDateKey = "suppress.today.date"
    private let dueCatchUpWindow: TimeInterval = 90
    private let isoFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private func todayKey(for date: Date = Date()) -> String {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; return f.string(from: date)
    }

    private func loadSuppressedIds() -> Set<String> {
        let day = todayKey()
        if defaults.string(forKey: suppressDateKey) != day { defaults.removeObject(forKey: suppressKey); defaults.set(day, forKey: suppressDateKey) }
        let arr = defaults.array(forKey: suppressKey) as? [String] ?? []
        return Set(arr)
    }

    private func saveSuppressedIds(_ set: Set<String>) {
        defaults.set(Array(set), forKey: suppressKey)
        defaults.set(todayKey(), forKey: suppressDateKey)
    }

    func suppressToday(for medicationID: UUID, timeComponents: DateComponents) {
        guard let h = timeComponents.hour, let m = timeComponents.minute else { return }
        let short = "\(medicationID.uuidString)_\(String(format: "%02d", h))_\(String(format: "%02d", m))"
        let today = Calendar.current.startOfDay(for: Date())
        let full = instanceId(for: medicationID, date: today, comps: timeComponents)
        var s = loadSuppressedIds(); s.insert(short); s.insert(full); saveSuppressedIds(s)
    }

    func isSuppressedToday(requestIdentifier: String) -> Bool {
        let set = loadSuppressedIds()
        if set.contains(requestIdentifier) { return true }
        guard let short = Self.suppressionKey(for: requestIdentifier) else { return false }
        return set.contains(short)
    }

    func requestAuthorization() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            if let error = error {
                #if DEBUG
                print("Notification auth error: \(error)")
                #endif
            } else {
                #if DEBUG
                print("Notifications granted: \(granted)")
                #endif
            }
        }
    }

    func registerCategories() {
        let taken = UNNotificationAction(identifier: Self.actionTaken, title: NSLocalizedString("Taken", comment: ""), options: [])
        let snooze10 = UNNotificationAction(identifier: Self.actionSnooze10, title: NSLocalizedString("Snooze 10m", comment: ""), options: [])
        let snooze30 = UNNotificationAction(identifier: Self.actionSnooze30, title: NSLocalizedString("Snooze 30m", comment: ""), options: [])
        let snooze60 = UNNotificationAction(identifier: Self.actionSnooze60, title: NSLocalizedString("Snooze 60m", comment: ""), options: [])
        let skip = UNNotificationAction(identifier: Self.actionSkip, title: NSLocalizedString("Skip", comment: ""), options: [.destructive])
        let category = UNNotificationCategory(identifier: Self.categoryId, actions: [taken, snooze10, snooze30, snooze60, skip], intentIdentifiers: [])
        UNUserNotificationCenter.current().setNotificationCategories([category])
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

    private func timeKey(_ comps: DateComponents) -> String? {
        guard let h = comps.hour, let m = comps.minute else { return nil }
        return String(format: "%02d:%02d", h, m)
    }

    private let primarySchedulingHorizonDays = 120
    private let followUpSchedulingHorizonDays = 3
    private let maxPendingNotificationBudget = 64
    private let maxScheduledFollowUpRequests = 6
    private let manualActionReserveSlots = 2

    private struct ScheduledDoseCandidate {
        let medication: Medication
        let timeComponents: DateComponents
        let doseDate: Date
        let fireDate: Date
        let strategy: AdaptiveReminderStrategy
    }

    func isReminderEligible(_ medication: Medication) -> Bool {
        medication.remindersEnabled && medication.isAsNeeded != true && !medication.timesOfDay.isEmpty
    }

    func syncAll(medications: [Medication], intakeLogs: [IntakeLog], now: Date = Date()) {
        let validMedicationIDs = Set(medications.map { $0.id })
        cleanOrphanedRequests(validMedicationIDs: validMedicationIDs)

        let activeReminderIDs = Set(medications.filter(isReminderEligible).map { $0.id })
        let inactiveMedications = medications.filter { !activeReminderIDs.contains($0.id) }
        inactiveMedications.forEach { cancelAll(for: $0) }
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
            selectedPrimary.forEach { self.schedulePrimaryReminder(for: $0, center: center) }

            let followUpCandidates = self.buildFollowUpCandidates(from: selectedPrimary, now: now)
                .sorted { $0.fireDate < $1.fireDate }
            followUpCandidates.prefix(followUpBudget).forEach {
                self.scheduleFollowUpReminder(for: $0.candidate, attempt: $0.attempt, minutes: $0.minutes, fireDate: $0.fireDate, center: center)
            }
        }
    }

    // MARK: - Instance-level scheduling (non-repeating)
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
            let strategy = AdaptiveReminderEngine.strategy(for: medication, intakeLogs: intakeLogs, now: now)
            medication.timesOfDay.forEach { timeComponents in
                upcomingFireDates(
                    for: timeComponents,
                    horizonDays: primarySchedulingHorizonDays,
                    from: now,
                    catchUpWindow: dueCatchUpWindow
                )
                .filter { medication.isDoseActive(on: $0) }
                .forEach { doseDate in
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
        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
        let req = UNNotificationRequest(identifier: id, content: content, trigger: trigger)
        center.add(req) { error in
            #if DEBUG
            if let error = error { print("Notification schedule error: \(error)") }
            #endif
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
        let fuComps = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: fireDate)
        let fuTrigger = UNCalendarNotificationTrigger(dateMatching: fuComps, repeats: false)
        let fuReq = UNNotificationRequest(identifier: fuId, content: fuContent, trigger: fuTrigger)
        center.add(fuReq, withCompletionHandler: nil)
    }

    private func lifecycleReservationSlots(for medications: [Medication]) -> Int {
        let refillSlots = medications.reduce(into: 0) { partialResult, medication in
            if medication.daysOfSupplyRemaining != nil {
                partialResult += 1
            }
        }
        let courseSlots = medications.reduce(into: 0) { partialResult, medication in
            if medication.courseEndDate != nil {
                partialResult += 1
            }
        }
        return min(10, refillSlots + courseSlots)
    }

    private func followUpBudget(for medications: [Medication]) -> Int {
        let reserved = lifecycleReservationSlots(for: medications) + manualActionReserveSlots
        let remaining = max(0, maxPendingNotificationBudget - reserved)
        return min(maxScheduledFollowUpRequests, max(0, remaining / 6))
    }

    private func primaryBudget(for medications: [Medication], followUpBudget: Int) -> Int {
        let reserved = lifecycleReservationSlots(for: medications) + manualActionReserveSlots + followUpBudget
        return max(0, maxPendingNotificationBudget - reserved)
    }

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
        if desiredDate > now {
            return desiredDate
        }

        let age = now.timeIntervalSince(desiredDate)
        guard age >= 0,
              age <= catchUpWindow,
              calendar.isDate(desiredDate, inSameDayAs: now) else {
            return nil
        }

        return now.addingTimeInterval(2)
    }

    private func followUpId(index: Int, for medID: UUID, date: Date, comps: DateComponents) -> String {
        "followup_\(index)_\(instanceId(for: medID, date: date, comps: comps))"
    }

    /// Cancel all follow-up reminders for a specific dose instance
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
        // Also remove any already-delivered follow-ups
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
        case 1:
            urgency = NSLocalizedString("Haven't taken it yet?", comment: "follow-up reminder")
        case 2:
            urgency = NSLocalizedString("Reminder: still not taken", comment: "follow-up reminder")
        default:
            urgency = NSLocalizedString("Urgent: please take your medication", comment: "follow-up reminder")
        }
        var bodyText = "\(urgency) — \(medication.dose)"
        if let fi = medication.foodInstruction {
            bodyText += " · \(fi.shortLabel)"
        }
        content.body = bodyText
        content.sound = .default
        content.categoryIdentifier = Self.categoryId
        var info: [String: Any] = ["medicationID": medication.id.uuidString]
        if let comps = scheduleTime, let h = comps.hour, let m = comps.minute {
            info["scheduleHour"] = h
            info["scheduleMinute"] = m
        }
        if let scheduledDate {
            info["scheduledDate"] = isoFormatter.string(from: scheduledDate)
        }
        content.userInfo = info
        content.threadIdentifier = medication.id.uuidString
        if #available(iOS 15.0, *) { content.interruptionLevel = riskLevel == .low ? .active : .timeSensitive }
        if #available(iOS 15.0, *) { content.relevanceScore = min(baseRelevanceScore(for: riskLevel) + Double(attempt) * 0.03, 1.0) }
        return content
    }

    private func makeContent(
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
        if let fi = medication.foodInstruction {
            content.subtitle = "⚠ \(fi.displayName)"
        }
        content.body = bodyText
        content.sound = .default
        content.categoryIdentifier = Self.categoryId
        var info: [String: Any] = ["medicationID": medication.id.uuidString]
        if let comps = scheduleTime, let h = comps.hour, let m = comps.minute {
            info["scheduleHour"] = h
            info["scheduleMinute"] = m
        }
        if let scheduledDate {
            info["scheduledDate"] = isoFormatter.string(from: scheduledDate)
        }
        content.userInfo = info
        content.threadIdentifier = medication.id.uuidString
        if #available(iOS 15.0, *) { content.interruptionLevel = riskLevel == .low ? .active : .timeSensitive }
        if #available(iOS 15.0, *) { content.relevanceScore = baseRelevanceScore(for: riskLevel) }
        return content
    }

    private func baseRelevanceScore(for riskLevel: AdaptiveReminderStrategy.RiskLevel) -> Double {
        switch riskLevel {
        case .low:
            return 0.75
        case .medium:
            return 0.9
        case .high:
            return 1.0
        }
    }

    private func instanceId(for medID: UUID, date: Date, comps: DateComponents, calendar: Calendar = .current) -> String {
        let df = DateFormatter(); df.dateFormat = "yyyyMMdd"; let day = df.string(from: date)
        let h = String(format: "%02d", comps.hour ?? 0)
        let m = String(format: "%02d", comps.minute ?? 0)
        return "\(medID.uuidString)_\(day)_\(h)_\(m)"
    }

    func cancelTodayInstance(for medicationID: UUID, timeComponents: DateComponents, now: Date = Date()) {
        let cal = Calendar.current
        let today = cal.startOfDay(for: now)
        let id = instanceId(for: medicationID, date: today, comps: timeComponents)
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [id])
    }

    func cancelAll(for medication: Medication) {
        let center = UNUserNotificationCenter.current()
        let prefix = medication.id.uuidString
        center.getPendingNotificationRequests { list in
            let ids = list.map { $0.identifier }.filter {
                $0.hasPrefix(prefix) || $0.hasPrefix("snooze_\(prefix)") || $0.contains(prefix)
            }
            center.removePendingNotificationRequests(withIdentifiers: ids)
        }
        // Remove delivered notifications with same prefix by enumerating
        center.getDeliveredNotifications { notes in
            let ids = notes.map { $0.request.identifier }.filter {
                $0.hasPrefix(prefix) || $0.hasPrefix("snooze_\(prefix)") || $0.contains(prefix)
            }
            if !ids.isEmpty { center.removeDeliveredNotifications(withIdentifiers: ids) }
        }
    }

    static func snoozeIdentifier(for medicationID: UUID, scheduleTime: DateComponents?) -> String {
        let base = "snooze_\(medicationID.uuidString)"
        guard let h = scheduleTime?.hour, let m = scheduleTime?.minute else { return base }
        return "\(base)_\(String(format: "%02d", h))_\(String(format: "%02d", m))"
    }

    func scheduleSnooze(
        for medicationID: UUID,
        minutes: Int = 10,
        scheduleTime: DateComponents? = nil,
        scheduledDate: Date? = nil
    ) {
        let snoozeId = Self.snoozeIdentifier(for: medicationID, scheduleTime: scheduleTime)
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [snoozeId])
        // remove legacy identifier if it exists to avoid duplicates
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
        let req = UNNotificationRequest(identifier: snoozeId, content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(req, withCompletionHandler: nil)
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
        let req = UNNotificationRequest(identifier: snoozeId, content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(req, withCompletionHandler: nil)
    }

    private func inferredScheduledDate(for scheduleTime: DateComponents?, relativeTo date: Date) -> Date? {
        guard let hour = scheduleTime?.hour, let minute = scheduleTime?.minute else { return nil }
        return Calendar.current.date(bySettingHour: hour, minute: minute, second: 0, of: date)
    }

    // MARK: - Badge handling (overdue count after grace)
    func updateBadge(store: DataStore) {
        // Hop to MainActor to read actor-isolated store properties safely, then compute and set badge.
        Task {
            let snapshot: ([Medication], [IntakeLog]) = await MainActor.run { (store.medications, store.intakeLogs) }
            let defaults = UserDefaults.standard
            let grace = defaults.object(forKey: "prefs.graceMinutes") as? Int ?? 30
            let activeSnoozes = await pendingSnoozeIdentifiers()
            let count = Self.computeOutstandingCount(medications: snapshot.0, intakeLogs: snapshot.1, graceMinutes: grace, activeSnoozes: activeSnoozes)
            await MainActor.run {
                UIApplication.shared.applicationIconBadgeNumber = count
            }
        }
    }

    private func pendingSnoozeIdentifiers() async -> Set<String> {
        await withCheckedContinuation { continuation in
            UNUserNotificationCenter.current().getPendingNotificationRequests { list in
                let ids = list.map { $0.identifier }.filter { $0.hasPrefix("snooze_") }
                continuation.resume(returning: Set(ids))
            }
        }
    }

    static func computeOutstandingCount(medications: [Medication], intakeLogs: [IntakeLog], graceMinutes: Int, activeSnoozes: Set<String> = [], now: Date = Date()) -> Int {
        let cal = Calendar.current
        let todayStart = cal.startOfDay(for: now)
        var total = 0
        for med in medications where med.remindersEnabled {
            let times = med.timesOfDay.compactMap { comps -> (Int, Int)? in
                guard let h = comps.hour, let m = comps.minute else { return nil }
                return (h, m)
            }
            for (h, m) in times {
                guard let sched = cal.date(bySettingHour: h, minute: m, second: 0, of: now) else { continue }
                guard med.isDoseActive(on: sched) else { continue }
                // Only count when overdue after grace
                if now < sched.addingTimeInterval(TimeInterval(graceMinutes * 60)) { continue }
                let key = String(format: "%02d:%02d", h, m)
                let allowNil = times.count <= 1
                // Find latest log today for this key
                let logs = intakeLogs
                    .filter { log in
                        guard log.medicationID == med.id else { return false }
                        let d = log.date
                        return d >= todayStart && d < cal.date(byAdding: .day, value: 1, to: todayStart)! &&
                            (log.scheduleKey == key || (allowNil && log.scheduleKey == nil))
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

    // MARK: - Observers
    private var observersInstalled = false
    func startBadgeAutoRefresh(store: DataStore) {
        guard !observersInstalled else { return }
        observersInstalled = true
        let center = NotificationCenter.default
        center.addObserver(forName: UIApplication.significantTimeChangeNotification, object: nil, queue: .main) { [weak self] _ in
            self?.updateBadge(store: store)
            Task { @MainActor in
                let meds = store.medications
                let logs = store.intakeLogs
                self?.syncAll(medications: meds, intakeLogs: logs)
            }
        }
        center.addObserver(forName: NSNotification.Name.NSCalendarDayChanged, object: nil, queue: .main) { [weak self] _ in
            self?.updateBadge(store: store)
            Task { @MainActor in
                let meds = store.medications
                let logs = store.intakeLogs
                self?.syncAll(medications: meds, intakeLogs: logs)
            }
        }
        center.addObserver(forName: NSNotification.Name.NSSystemTimeZoneDidChange, object: nil, queue: .main) { [weak self] _ in
            self?.updateBadge(store: store)
            Task { @MainActor in
                let meds = store.medications
                let logs = store.intakeLogs
                self?.syncAll(medications: meds, intakeLogs: logs)
            }
        }
    }

    // MARK: - Inventory & Course Reminders
    private static let refillCategoryId = "MED_REFILL"
    private static let courseCategoryId = "MED_COURSE_END"
    private let courseCatchUpTokensKey = "course.reminder.catchup.tokens"

    private func refillIdentifier(for medID: UUID) -> String {
        "refill_\(medID.uuidString)"
    }

    private func courseIdentifier(for medID: UUID) -> String {
        "course_\(medID.uuidString)"
    }

    private func courseToken(for medication: Medication, calendar: Calendar = .current) -> String? {
        guard let courseEndDate = medication.courseEndDate else { return nil }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd"
        let day = formatter.string(from: calendar.startOfDay(for: courseEndDate))
        return "\(medication.id.uuidString)_\(day)"
    }

    private func storedCourseCatchUpToken(for medicationID: UUID) -> String? {
        let dict = defaults.dictionary(forKey: courseCatchUpTokensKey) as? [String: String] ?? [:]
        return dict[medicationID.uuidString]
    }

    private func setStoredCourseCatchUpToken(_ token: String?, for medicationID: UUID) {
        var dict = defaults.dictionary(forKey: courseCatchUpTokensKey) as? [String: String] ?? [:]
        dict[medicationID.uuidString] = token
        if token == nil { dict.removeValue(forKey: medicationID.uuidString) }
        defaults.set(dict, forKey: courseCatchUpTokensKey)
    }

    private func removeLifecycleNotifications(identifier: String) {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [identifier])
        center.removeDeliveredNotifications(withIdentifiers: [identifier])
    }

    func scheduleRefillReminder(for medication: Medication) {
        let id = refillIdentifier(for: medication.id)
        guard let days = medication.daysOfSupplyRemaining else {
            removeLifecycleNotifications(identifier: id)
            return
        }
        let threshold = UserDefaults.standard.object(forKey: "prefs.refillThresholdDays") as? Int ?? 7
        let center = UNUserNotificationCenter.current()

        if days > threshold {
            // Not low yet — cancel any existing refill reminder
            removeLifecycleNotifications(identifier: id)
            return
        }

        let content = UNMutableNotificationContent()
        content.title = NSLocalizedString("Refill Reminder", comment: "")
        if days == 0 {
            content.body = String(format: NSLocalizedString("%@ has run out. Time to refill!", comment: ""), medication.name)
        } else {
            content.body = String(format: NSLocalizedString("%@ has %lld days of supply left. Consider refilling soon.", comment: ""), medication.name, days)
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

        let req = UNNotificationRequest(identifier: id, content: content, trigger: trigger)
        center.add(req, withCompletionHandler: nil)
    }

    func cancelRefillReminder(for medID: UUID) {
        removeLifecycleNotifications(identifier: refillIdentifier(for: medID))
    }

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
            content.body = String(format: NSLocalizedString("%@ reached its end date %lld days ago. Review whether it should continue.", comment: ""), medication.name, daysPast)
        case .endsToday:
            content.body = String(format: NSLocalizedString("%@ is scheduled to end today. Review whether it should continue.", comment: ""), medication.name)
        case .endingSoon(let daysRemaining):
            content.body = String(format: NSLocalizedString("%@ is scheduled to end in %lld days. Review the plan soon.", comment: ""), medication.name, daysRemaining)
        case .scheduled(let daysRemaining):
            content.body = String(format: NSLocalizedString("%@ is scheduled to end in %lld days. Review the plan soon.", comment: ""), medication.name, daysRemaining)
        }
        content.sound = .default
        content.categoryIdentifier = Self.courseCategoryId
        content.userInfo = ["medicationID": medication.id.uuidString]

        let comps = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: fireDate)
        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
        let req = UNNotificationRequest(identifier: id, content: content, trigger: trigger)
        if fireDate != preferredFire {
            setStoredCourseCatchUpToken(currentToken, for: medication.id)
        } else {
            setStoredCourseCatchUpToken(nil, for: medication.id)
        }
        UNUserNotificationCenter.current().add(req, withCompletionHandler: nil)
    }

    func cancelCourseReminder(for medID: UUID) {
        setStoredCourseCatchUpToken(nil, for: medID)
        removeLifecycleNotifications(identifier: courseIdentifier(for: medID))
    }

    /// Keep inventory and course reminders aligned with the current medication list.
    func checkLifecycleReminders(medications: [Medication], now: Date = Date()) {
        for med in medications {
            scheduleRefillReminder(for: med)
            scheduleCourseReminder(for: med, now: now)
        }
    }

    // Remove pending/delivered notifications that no longer match current medications
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

extension NotificationManager {
    static func suppressionKey(for requestIdentifier: String) -> String? {
        let parts = requestIdentifier.split(separator: "_")

        if parts.count >= 4, parts[0] == "snooze" {
            return "\(parts[1])_\(parts[2])_\(parts[3])"
        }

        if parts.count >= 6, parts[0] == "followup" {
            return "\(parts[2])_\(parts[4])_\(parts[5])"
        }

        if parts.count >= 4 {
            return "\(parts[0])_\(parts[2])_\(parts[3])"
        }

        return nil
    }

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
        if let medicationID = medicationID(from: identifier), !validMedicationIDs.contains(medicationID) {
            return false
        }

        if let medicationID = medicationID(from: identifier) {
            if identifier.hasPrefix("\(medicationID)_") { return true }
            if identifier.hasPrefix("followup_"), identifier.contains("_\(medicationID)_") { return true }
        }

        return false
    }

    static func scheduleComponents(from userInfo: [AnyHashable: Any]) -> DateComponents? {
        guard let hour = userInfo["scheduleHour"] as? Int,
              let minute = userInfo["scheduleMinute"] as? Int,
              (0..<24).contains(hour),
              (0..<60).contains(minute) else {
            return nil
        }
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
        guard parts.count >= 3 else { return nil }
        // Pattern: <medID>_yyyyMMdd_HH_MM
        let maybeDate = parts[1]
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd"
        return formatter.date(from: String(maybeDate))
    }
}
