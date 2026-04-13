import Foundation
import UserNotifications

// MARK: - Snooze Count Tracking
// Tracks per-medication per-time snooze escalation counts within a single day.
// Counts are reset automatically when the calendar day changes.

extension NotificationManager {

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

    // MARK: - Internal helpers

    func snoozeTrackingKey(for medicationID: UUID, scheduleTime: DateComponents?) -> String {
        guard let h = scheduleTime?.hour, let m = scheduleTime?.minute else {
            return medicationID.uuidString
        }
        return "\(medicationID.uuidString)_\(String(format: "%02d", h))_\(String(format: "%02d", m))"
    }

    func resetSnoozeCountsIfNewDay() {
        let day = todayKey()
        if defaults.string(forKey: snoozeCountDateKey) != day {
            defaults.removeObject(forKey: snoozeCountKey)
            defaults.set(day, forKey: snoozeCountDateKey)
        }
    }
}
