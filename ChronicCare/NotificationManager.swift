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

    private func todayKey() -> String {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; return f.string(from: Date())
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

    private func timeKey(_ comps: DateComponents) -> String? {
        guard let h = comps.hour, let m = comps.minute else { return nil }
        return String(format: "%02d:%02d", h, m)
    }

    func schedule(for medication: Medication) {
        let center = UNUserNotificationCenter.current()
        let prefix = medication.id.uuidString
        center.getPendingNotificationRequests { list in
            // Remove only base schedule IDs (not snooze_)
            let ids = list.map { $0.identifier }.filter { $0.hasPrefix(prefix + "_") }
            if !ids.isEmpty { center.removePendingNotificationRequests(withIdentifiers: ids) }

            guard medication.remindersEnabled else { return }
            for t in medication.timesOfDay {
                self.scheduleNextInstance(for: medication, timeComponents: t)
            }
        }
    }

    // MARK: - Instance-level scheduling (non-repeating)
    private func nextFireDate(for time: DateComponents, from now: Date = Date(), calendar: Calendar = .current) -> Date? {
        guard let h = time.hour, let m = time.minute else { return nil }
        let today = calendar.date(bySettingHour: h, minute: m, second: 0, of: now)!
        if today > now { return today }
        return calendar.date(byAdding: .day, value: 1, to: today)
    }

    private func makeContent(for medication: Medication, isSnooze: Bool = false) -> UNMutableNotificationContent {
        let content = UNMutableNotificationContent()
        content.title = medication.name
        content.body = String(format: NSLocalizedString(isSnooze ? "Snoozed: %@" : "Dose: %@", comment: ""), medication.dose)
        content.sound = .default
        content.categoryIdentifier = Self.categoryId
        content.userInfo = ["medicationID": medication.id.uuidString]
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

    func scheduleNextInstance(for medication: Medication, timeComponents: DateComponents) {
        guard let fireDate = nextFireDate(for: timeComponents) else { return }
        let comps = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: fireDate)
        let id = instanceId(for: medication.id, date: fireDate, comps: timeComponents)
        let content = makeContent(for: medication)
        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
        let req = UNNotificationRequest(identifier: id, content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(req) { error in
            if let error = error { print("Notification schedule error: \(error)") }
        }
    }

    func cancelTodayInstance(for medicationID: UUID, timeComponents: DateComponents, now: Date = Date()) {
        let cal = Calendar.current
        let today = cal.startOfDay(for: now)
        let id = instanceId(for: medicationID, date: today, comps: timeComponents)
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [id])
    }

    func cancel(for medication: Medication) {
        // Remove any pending requests that match this med's prefix
        let center = UNUserNotificationCenter.current()
        let prefix = medication.id.uuidString
        center.getPendingNotificationRequests { list in
            let ids = list.map { $0.identifier }.filter { $0.hasPrefix(prefix) }
            if !ids.isEmpty { center.removePendingNotificationRequests(withIdentifiers: ids) }
        }
    }

    func cancelAll(for medication: Medication) {
        let center = UNUserNotificationCenter.current()
        let prefix = medication.id.uuidString
        center.getPendingNotificationRequests { list in
            let ids = list.map { $0.identifier }.filter { $0.hasPrefix(prefix) || $0 == "snooze_\(prefix)" }
            center.removePendingNotificationRequests(withIdentifiers: ids)
        }
        // Remove delivered notifications with same prefix by enumerating
        center.getDeliveredNotifications { notes in
            let ids = notes.map { $0.request.identifier }.filter { $0.hasPrefix(prefix) || $0 == "snooze_\(prefix)" }
            if !ids.isEmpty { center.removeDeliveredNotifications(withIdentifiers: ids) }
        }
    }

    func scheduleSnooze(for medicationID: UUID, minutes: Int = 10) {
        // Avoid stacking multiple snooze notifications for the same medication
        let snoozeId = "snooze_\(medicationID.uuidString)"
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [snoozeId])

        let content = UNMutableNotificationContent()
        content.title = NSLocalizedString("Snoozed Reminder", comment: "")
        content.body = NSLocalizedString("Time to take your medication", comment: "")
        content.sound = .default
        content.categoryIdentifier = Self.categoryId
        content.userInfo = ["medicationID": medicationID.uuidString]
        content.threadIdentifier = medicationID.uuidString
        if #available(iOS 15.0, *) { content.interruptionLevel = .timeSensitive }
        if #available(iOS 15.0, *) { content.relevanceScore = 0.8 }

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: TimeInterval(minutes * 60), repeats: false)
        let req = UNNotificationRequest(identifier: snoozeId, content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(req, withCompletionHandler: nil)
    }

    func scheduleSnooze(for medication: Medication, minutes: Int = 10) {
        let snoozeId = "snooze_\(medication.id.uuidString)"
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [snoozeId])

        let content = makeContent(for: medication, isSnooze: true)

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
            let count = Self.computeOutstandingCount(medications: snapshot.0, intakeLogs: snapshot.1, graceMinutes: grace)
            await MainActor.run {
                UIApplication.shared.applicationIconBadgeNumber = count
            }
        }
    }

    static func computeOutstandingCount(medications: [Medication], intakeLogs: [IntakeLog], graceMinutes: Int) -> Int {
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
}
