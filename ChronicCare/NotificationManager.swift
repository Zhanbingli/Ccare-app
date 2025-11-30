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
            // Remove only base schedule IDs (not snooze_)
            let ids = list.map { $0.identifier }.filter { $0.hasPrefix(prefix + "_") }
            if !ids.isEmpty { center.removePendingNotificationRequests(withIdentifiers: ids) }
            // Also remove lingering snoozes when regenerating full schedule
            let snoozeIds = list.map { $0.identifier }.filter { $0.hasPrefix("snooze_\(prefix)") }
            if !snoozeIds.isEmpty { center.removePendingNotificationRequests(withIdentifiers: snoozeIds) }

            // Clean delivered notifications with same prefix to avoid stale banners/badges
            center.getDeliveredNotifications { notes in
                let delivered = notes.map { $0.request.identifier }.filter { $0.hasPrefix(prefix) || $0.hasPrefix("snooze_\(prefix)") }
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

    private func scheduleUpcomingInstances(for medication: Medication, timeComponents: DateComponents, horizonDays: Int, now: Date = Date()) {
        let fireDates = upcomingFireDates(for: timeComponents, horizonDays: horizonDays, from: now)
        guard !fireDates.isEmpty else { return }
        let calendar = Calendar.current
        fireDates.forEach { fireDate in
            let comps = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: fireDate)
            let id = instanceId(for: medication.id, date: fireDate, comps: timeComponents)
            let content = makeContent(for: medication, scheduleTime: timeComponents, scheduledDate: fireDate)
            let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
            let req = UNNotificationRequest(identifier: id, content: content, trigger: trigger)
            UNUserNotificationCenter.current().add(req) { error in
                if let error = error { print("Notification schedule error: \(error)") }
            }
        }
    }

    private func makeContent(for medication: Medication, scheduleTime: DateComponents?, scheduledDate: Date? = nil, isSnooze: Bool = false) -> UNMutableNotificationContent {
        let content = UNMutableNotificationContent()
        content.title = medication.name
        content.body = String(format: NSLocalizedString(isSnooze ? "Snoozed: %@" : "Dose: %@", comment: ""), medication.dose)
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
            let ids = list.map { $0.identifier }.filter { $0.hasPrefix(prefix) || $0.hasPrefix("snooze_\(prefix)") }
            center.removePendingNotificationRequests(withIdentifiers: ids)
        }
        // Remove delivered notifications with same prefix by enumerating
        center.getDeliveredNotifications { notes in
            let ids = notes.map { $0.request.identifier }.filter { $0.hasPrefix(prefix) || $0.hasPrefix("snooze_\(prefix)") }
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

    // Remove pending/delivered notifications that no longer match current medications
    func cleanOrphanedRequests(validMedicationIDs: Set<UUID>) {
        let center = UNUserNotificationCenter.current()
        center.getPendingNotificationRequests { list in
            let orphanIds = list
                .map { $0.identifier }
                .filter { id in
                    // identifiers use medID prefix before first "_"
                    let prefix = id.split(separator: "_").first
                    guard let pref = prefix, let uuid = UUID(uuidString: String(pref)) else { return false }
                    return !validMedicationIDs.contains(uuid)
                }
            if !orphanIds.isEmpty { center.removePendingNotificationRequests(withIdentifiers: orphanIds) }
        }
        center.getDeliveredNotifications { notes in
            let orphanIds = notes
                .map { $0.request.identifier }
                .filter { id in
                    let prefix = id.split(separator: "_").first
                    guard let pref = prefix, let uuid = UUID(uuidString: String(pref)) else { return false }
                    return !validMedicationIDs.contains(uuid)
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
