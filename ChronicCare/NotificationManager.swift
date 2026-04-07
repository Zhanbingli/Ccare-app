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

    func sendCaregiverReminder(caregiverName: String, medicationName: String, missedDays: Int) {
        let content = UNMutableNotificationContent()
        content.title = NSLocalizedString("Share with Caregiver?", comment: "")
        content.body = String(format: NSLocalizedString("You haven't taken %@ for %lld days. Would you like to share your status with %@?", comment: ""), medicationName, missedDays, caregiverName)
        content.sound = .default
        if #available(iOS 15.0, *) { content.interruptionLevel = .active }
        let id = "caregiver_\(caregiverName.hashValue)_\(todayKey())"
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 2, repeats: false)
        let req = UNNotificationRequest(identifier: id, content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(req, withCompletionHandler: nil)
    }

    // MARK: - Same-day suppression (to avoid duplicate reminders after early Taken/Skip)
    private let defaults = UserDefaults.standard
    private let suppressKey = "suppress.today.ids"
    private let suppressDateKey = "suppress.today.date"
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
        // also check short pattern "<medID>_HH_MM"
        let parts = requestIdentifier.split(separator: "_")
        if parts.count >= 3 {
            let short = parts.count >= 4 ? "\(parts[0])_\(parts[2])_\(parts[3])" : requestIdentifier
            return set.contains(short)
        }
        return false
    }

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

    private let scheduleHorizonDays = 14

    func schedule(for medication: Medication, now: Date = Date()) {
        let center = UNUserNotificationCenter.current()
        let prefix = medication.id.uuidString
        center.getPendingNotificationRequests { list in
            // Remove base schedule IDs, snoozes, and follow-ups for this medication
            let ids = list.map { $0.identifier }.filter { $0.contains(prefix) }
            if !ids.isEmpty { center.removePendingNotificationRequests(withIdentifiers: ids) }

            // Clean delivered notifications to avoid stale banners/badges
            center.getDeliveredNotifications { notes in
                let delivered = notes.map { $0.request.identifier }.filter { $0.contains(prefix) }
                if !delivered.isEmpty { center.removeDeliveredNotifications(withIdentifiers: delivered) }
            }

            guard medication.remindersEnabled else { return }
            for t in medication.timesOfDay {
                self.scheduleUpcomingInstances(for: medication, timeComponents: t, horizonDays: self.scheduleHorizonDays, now: now)
            }
        }
    }

    // MARK: - Instance-level scheduling (non-repeating)
    private func upcomingFireDates(for time: DateComponents, horizonDays: Int, from now: Date = Date(), calendar: Calendar = .current) -> [Date] {
        guard let h = time.hour, let m = time.minute, horizonDays > 0 else { return [] }
        let startOfToday = calendar.startOfDay(for: now)
        var result: [Date] = []
        for offset in 0..<horizonDays {
            guard let day = calendar.date(byAdding: .day, value: offset, to: startOfToday),
                  let scheduled = calendar.date(bySettingHour: h, minute: m, second: 0, of: day),
                  scheduled >= now else { continue }
            result.append(scheduled)
        }
        return result
    }

    // Follow-up intervals in minutes after original scheduled time
    private let followUpIntervals = [10, 30, 60]

    private func scheduleUpcomingInstances(for medication: Medication, timeComponents: DateComponents, horizonDays: Int, now: Date = Date()) {
        let fireDates = upcomingFireDates(for: timeComponents, horizonDays: horizonDays, from: now)
        guard !fireDates.isEmpty else { return }
        let calendar = Calendar.current
        let center = UNUserNotificationCenter.current()
        fireDates.forEach { fireDate in
            let comps = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: fireDate)
            let id = instanceId(for: medication.id, date: fireDate, comps: timeComponents)
            let content = makeContent(for: medication, scheduleTime: timeComponents, scheduledDate: fireDate)
            let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
            let req = UNNotificationRequest(identifier: id, content: content, trigger: trigger)
            center.add(req) { error in
                if let error = error { print("Notification schedule error: \(error)") }
            }

            // Schedule follow-up reminders at increasing intervals
            for (index, minutes) in followUpIntervals.enumerated() {
                let followUpDate = fireDate.addingTimeInterval(TimeInterval(minutes * 60))
                guard followUpDate > now else { continue }
                let fuId = followUpId(index: index + 1, for: medication.id, date: fireDate, comps: timeComponents)
                let fuContent = makeFollowUpContent(for: medication, scheduleTime: timeComponents, scheduledDate: fireDate, attempt: index + 1)
                let fuComps = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: followUpDate)
                let fuTrigger = UNCalendarNotificationTrigger(dateMatching: fuComps, repeats: false)
                let fuReq = UNNotificationRequest(identifier: fuId, content: fuContent, trigger: fuTrigger)
                center.add(fuReq, withCompletionHandler: nil)
            }
        }
    }

    private func followUpId(index: Int, for medID: UUID, date: Date, comps: DateComponents) -> String {
        "followup_\(index)_\(instanceId(for: medID, date: date, comps: comps))"
    }

    /// Cancel all follow-up reminders for a specific dose instance
    func cancelFollowUps(for medicationID: UUID, timeComponents: DateComponents, now: Date = Date()) {
        let cal = Calendar.current
        let today = cal.startOfDay(for: now)
        let baseId = instanceId(for: medicationID, date: today, comps: timeComponents)
        let ids = followUpIntervals.indices.map { "followup_\($0 + 1)_\(baseId)" }
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ids)
        // Also remove any already-delivered follow-ups
        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: ids)
    }

    private func makeFollowUpContent(for medication: Medication, scheduleTime: DateComponents?, scheduledDate: Date?, attempt: Int) -> UNMutableNotificationContent {
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
        if #available(iOS 15.0, *) { content.interruptionLevel = .timeSensitive }
        if #available(iOS 15.0, *) { content.relevanceScore = min(0.9 + Double(attempt) * 0.03, 1.0) }
        return content
    }

    private func makeContent(for medication: Medication, scheduleTime: DateComponents?, scheduledDate: Date? = nil, isSnooze: Bool = false) -> UNMutableNotificationContent {
        let content = UNMutableNotificationContent()
        content.title = medication.name
        // Include scheduled time in body so elderly users know which dose this is
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
        if #available(iOS 15.0, *) { content.interruptionLevel = .timeSensitive }
        if #available(iOS 15.0, *) { content.relevanceScore = 0.9 }
        return content
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

    func scheduleSnooze(for medicationID: UUID, minutes: Int = 10, scheduleTime: DateComponents? = nil) {
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
        info["scheduledDate"] = isoFormatter.string(from: fireDate)
        content.userInfo = info
        content.threadIdentifier = medicationID.uuidString
        if #available(iOS 15.0, *) { content.interruptionLevel = .timeSensitive }
        if #available(iOS 15.0, *) { content.relevanceScore = 0.8 }

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: TimeInterval(minutes * 60), repeats: false)
        let req = UNNotificationRequest(identifier: snoozeId, content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(req, withCompletionHandler: nil)
    }

    func scheduleSnooze(for medication: Medication, minutes: Int = 10, scheduleTime: DateComponents? = nil) {
        let snoozeId = Self.snoozeIdentifier(for: medication.id, scheduleTime: scheduleTime)
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [snoozeId])
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ["snooze_\(medication.id.uuidString)"])

        let content = makeContent(for: medication, scheduleTime: scheduleTime, scheduledDate: Date().addingTimeInterval(TimeInterval(minutes * 60)), isSnooze: true)

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: TimeInterval(minutes * 60), repeats: false)
        let req = UNNotificationRequest(identifier: snoozeId, content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(req, withCompletionHandler: nil)
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

    static func computeOutstandingCount(medications: [Medication], intakeLogs: [IntakeLog], graceMinutes: Int, activeSnoozes: Set<String> = []) -> Int {
        let cal = Calendar.current
        let now = Date()
        let todayStart = cal.startOfDay(for: now)
        var total = 0
        for med in medications where med.remindersEnabled {
            let times = med.timesOfDay.compactMap { comps -> (Int, Int)? in
                guard let h = comps.hour, let m = comps.minute else { return nil }
                return (h, m)
            }
            for (h, m) in times {
                guard let sched = cal.date(bySettingHour: h, minute: m, second: 0, of: now) else { continue }
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
                meds.filter({ $0.remindersEnabled }).forEach { self?.schedule(for: $0) }
            }
        }
        center.addObserver(forName: NSNotification.Name.NSCalendarDayChanged, object: nil, queue: .main) { [weak self] _ in
            self?.updateBadge(store: store)
            Task { @MainActor in
                let meds = store.medications
                meds.filter({ $0.remindersEnabled }).forEach { self?.schedule(for: $0) }
            }
        }
        center.addObserver(forName: NSNotification.Name.NSSystemTimeZoneDidChange, object: nil, queue: .main) { [weak self] _ in
            self?.updateBadge(store: store)
            Task { @MainActor in
                let meds = store.medications
                meds.filter({ $0.remindersEnabled }).forEach { self?.schedule(for: $0) }
            }
        }
    }

    // MARK: - Refill Reminders
    private static let refillCategoryId = "MED_REFILL"

    private func refillIdentifier(for medID: UUID) -> String {
        "refill_\(medID.uuidString)"
    }

    func scheduleRefillReminder(for medication: Medication) {
        guard let days = medication.daysOfSupplyRemaining else { return }
        let threshold = UserDefaults.standard.object(forKey: "prefs.refillThresholdDays") as? Int ?? 7
        let id = refillIdentifier(for: medication.id)
        let center = UNUserNotificationCenter.current()

        if days > threshold {
            // Not low yet — cancel any existing refill reminder
            center.removePendingNotificationRequests(withIdentifiers: [id])
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
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [refillIdentifier(for: medID)])
    }

    /// Check all medications for low supply and schedule refill reminders
    func checkRefillReminders(medications: [Medication]) {
        for med in medications {
            scheduleRefillReminder(for: med)
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
                    // Check if any valid medication ID appears in the identifier
                    !validStrings.contains(where: { id.contains($0) })
                }
            if !orphanIds.isEmpty { center.removePendingNotificationRequests(withIdentifiers: orphanIds) }
        }
        center.getDeliveredNotifications { notes in
            let orphanIds = notes
                .map { $0.request.identifier }
                .filter { id in
                    !validStrings.contains(where: { id.contains($0) })
                }
            if !orphanIds.isEmpty { center.removeDeliveredNotifications(withIdentifiers: orphanIds) }
        }
    }
}

extension NotificationManager {
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
