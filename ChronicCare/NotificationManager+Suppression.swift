import Foundation
import UserNotifications

// MARK: - Same-Day Suppression
// Prevents duplicate reminders from firing on the same day once a dose has been
// marked as Taken or Skipped. Suppressed IDs are stored in UserDefaults and
// automatically cleared at the start of each new calendar day.

extension NotificationManager {

    func suppressToday(for medicationID: UUID, timeComponents: DateComponents) {
        guard let h = timeComponents.hour, let m = timeComponents.minute else { return }
        let short = "\(medicationID.uuidString)_\(String(format: "%02d", h))_\(String(format: "%02d", m))"
        let today = Calendar.current.startOfDay(for: Date())
        let full = instanceId(for: medicationID, date: today, comps: timeComponents)
        var s = loadSuppressedIds()
        s.insert(short)
        s.insert(full)
        saveSuppressedIds(s)
    }

    func isSuppressedToday(requestIdentifier: String) -> Bool {
        let set = loadSuppressedIds()
        if set.contains(requestIdentifier) { return true }
        guard let short = Self.suppressionKey(for: requestIdentifier) else { return false }
        return set.contains(short)
    }

    // MARK: - Internal helpers

    func loadSuppressedIds() -> Set<String> {
        let day = todayKey()
        if defaults.string(forKey: suppressDateKey) != day {
            defaults.removeObject(forKey: suppressKey)
            defaults.set(day, forKey: suppressDateKey)
        }
        let arr = defaults.array(forKey: suppressKey) as? [String] ?? []
        return Set(arr)
    }

    func saveSuppressedIds(_ set: Set<String>) {
        defaults.set(Array(set), forKey: suppressKey)
        defaults.set(todayKey(), forKey: suppressDateKey)
    }
}

// MARK: - Suppression Key Parsing (static)

extension NotificationManager {

    /// Derives the short suppression key from a full notification request identifier,
    /// enabling cross-type matching (primary / snooze / follow-up all share the same key).
    static func suppressionKey(for requestIdentifier: String) -> String? {
        let parts = requestIdentifier.split(separator: "_")

        // snooze_<UUID>_HH_MM
        if parts.count >= 4, parts[0] == "snooze" {
            return "\(parts[1])_\(parts[2])_\(parts[3])"
        }

        // followup_<attempt>_<UUID>_yyyyMMdd_HH_MM
        if parts.count >= 6, parts[0] == "followup" {
            return "\(parts[2])_\(parts[4])_\(parts[5])"
        }

        // <UUID>_yyyyMMdd_HH_MM
        if parts.count >= 4 {
            return "\(parts[0])_\(parts[2])_\(parts[3])"
        }

        return nil
    }
}
