import Foundation

/// Pure-function adherence calculator. Takes medications and logs as inputs,
/// making it easy to test without needing a DataStore instance.
enum AdherenceCalculator {

    // MARK: - Core log matching

    /// Find the latest intake status for a given day/medication/scheduleKey.
    static func latestStatus(
        on dayStart: Date,
        medID: UUID,
        scheduleKey: String?,
        medTimesCount: Int,
        logs: [IntakeLog],
        calendar: Calendar = .current
    ) -> IntakeStatus? {
        let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart)!
        let candidates = logs.filter { log in
            guard log.medicationID == medID && log.date >= dayStart && log.date < dayEnd else { return false }
            if let key = scheduleKey {
                return log.scheduleKey == key || (medTimesCount == 1 && log.scheduleKey == nil)
            } else {
                return log.scheduleKey == nil
            }
        }.sorted(by: { $0.date > $1.date })
        return candidates.first?.status
    }

    // MARK: - Day counts

    /// Compute (taken, total) counts for a single day.
    static func dayCounts(
        dayKey: Date,
        medications: [Medication],
        logs: [IntakeLog],
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> (taken: Int, total: Int) {
        let isToday = calendar.isDateInToday(dayKey)
        let meds = medications.filter { $0.isAsNeeded != true }
        var taken = 0, total = 0

        for med in meds {
            let times = med.timesOfDay.compactMap { c -> (Int, Int)? in
                guard let h = c.hour, let m = c.minute else { return nil }
                return (h, m)
            }
            for (h, m) in times {
                if isToday, let sched = calendar.date(bySettingHour: h, minute: m, second: 0, of: now), sched > now { continue }
                guard let scheduled = calendar.date(bySettingHour: h, minute: m, second: 0, of: dayKey),
                      med.isDoseActive(on: scheduled) else { continue }
                total += 1
                let key = String(format: "%02d:%02d", h, m)
                if latestStatus(on: dayKey, medID: med.id, scheduleKey: key, medTimesCount: times.count, logs: logs, calendar: calendar) == .taken {
                    taken += 1
                }
            }
        }
        return (taken, total)
    }

    // MARK: - Weekly adherence

    static func weeklyAdherence(
        for medicationID: UUID? = nil,
        endingOn endDate: Date = Date(),
        medications: [Medication],
        intakeLogs: [IntakeLog],
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> [(Date, Double)] {
        let endDay = calendar.startOfDay(for: endDate)
        let startDay = calendar.date(byAdding: .day, value: -6, to: endDay)!

        let filteredMeds = filterMeds(medications, for: medicationID)
        let logsWindow = filterLogs(intakeLogs, from: startDay, to: endDay, medicationID: medicationID, calendar: calendar)

        var byDay: [Date: (taken: Int, total: Int)] = [:]
        for i in 0..<7 {
            let day = calendar.date(byAdding: .day, value: i, to: startDay)!
            let dayKey = calendar.startOfDay(for: day)
            let counts = dayCounts(dayKey: dayKey, medications: filteredMeds, logs: logsWindow, now: now, calendar: calendar)
            byDay[dayKey] = counts
        }

        return byDay.keys.sorted().map { day in
            let v = byDay[day] ?? (0, 0)
            let pct = v.total > 0 ? Double(v.taken) / Double(v.total) : 0
            return (day, pct)
        }
    }

    // MARK: - Monthly adherence

    static func monthlyAdherence(
        for medicationID: UUID? = nil,
        year: Int,
        month: Int,
        medications: [Medication],
        intakeLogs: [IntakeLog],
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> [Date: (taken: Int, total: Int)] {
        guard let monthStart = calendar.date(from: DateComponents(year: year, month: month, day: 1)),
              let monthRange = calendar.range(of: .day, in: .month, for: monthStart) else { return [:] }
        let today = calendar.startOfDay(for: now)

        let filteredMeds = filterMeds(medications, for: medicationID)
        let monthEnd = calendar.date(byAdding: .month, value: 1, to: monthStart)!
        let logsWindow = intakeLogs.filter { log in
            let day = calendar.startOfDay(for: log.date)
            guard day >= monthStart && day < monthEnd else { return false }
            if let mid = medicationID { return log.medicationID == mid }
            return true
        }

        var result: [Date: (taken: Int, total: Int)] = [:]
        for dayNum in monthRange {
            guard let day = calendar.date(from: DateComponents(year: year, month: month, day: dayNum)) else { continue }
            let dayKey = calendar.startOfDay(for: day)
            if dayKey > today { continue }
            let counts = dayCounts(dayKey: dayKey, medications: filteredMeds, logs: logsWindow, now: now, calendar: calendar)
            result[dayKey] = counts
        }
        return result
    }

    // MARK: - Adherence percentage

    static func adherencePercent(
        for medicationID: UUID? = nil,
        days: Int = 30,
        medications: [Medication],
        intakeLogs: [IntakeLog],
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> Double {
        let endDay = calendar.startOfDay(for: now)
        let startDay = calendar.date(byAdding: .day, value: -(days - 1), to: endDay)!

        let filteredMeds = filterMeds(medications, for: medicationID)
        var taken = 0, total = 0
        for i in 0..<days {
            let day = calendar.date(byAdding: .day, value: i, to: startDay)!
            let dayKey = calendar.startOfDay(for: day)
            if dayKey > endDay { continue }
            let counts = dayCounts(dayKey: dayKey, medications: filteredMeds, logs: intakeLogs, now: now, calendar: calendar)
            taken += counts.taken
            total += counts.total
        }
        return total > 0 ? Double(taken) / Double(total) : 0
    }

    // MARK: - Current streak

    static func currentStreak(
        for medicationID: UUID,
        medications: [Medication],
        intakeLogs: [IntakeLog],
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> Int {
        guard let med = medications.first(where: { $0.id == medicationID }),
              med.isAsNeeded != true else { return 0 }
        let today = calendar.startOfDay(for: now)
        var streak = 0
        for offset in 0..<365 {
            let day = calendar.date(byAdding: .day, value: -offset, to: today)!
            let dayKey = calendar.startOfDay(for: day)
            let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayKey)!
            let times = med.timesOfDay.compactMap { c -> (Int, Int)? in
                guard let h = c.hour, let m = c.minute else { return nil }
                return (h, m)
            }
            if times.isEmpty { break }
            if dayKey < calendar.startOfDay(for: med.startDate) { break }
            let isToday = calendar.isDateInToday(dayKey)
            var allTaken = true
            var hasDue = false
            for (h, m) in times {
                if isToday, let sched = calendar.date(bySettingHour: h, minute: m, second: 0, of: now), sched > now { continue }
                guard let scheduled = calendar.date(bySettingHour: h, minute: m, second: 0, of: dayKey),
                      med.isDoseActive(on: scheduled) else { continue }
                hasDue = true
                let key = String(format: "%02d:%02d", h, m)
                let match = intakeLogs.filter { log in
                    guard log.medicationID == medicationID && log.date >= dayKey && log.date < dayEnd else { return false }
                    return log.scheduleKey == key || (times.count == 1 && log.scheduleKey == nil)
                }.sorted(by: { $0.date > $1.date }).first
                if match?.status != .taken { allTaken = false; break }
            }
            if !hasDue && offset == 0 { continue }
            if !hasDue || !allTaken { break }
            streak += 1
        }
        return streak
    }

    // MARK: - Consecutive missed days

    static func consecutiveMissedDays(
        for medicationID: UUID,
        medications: [Medication],
        intakeLogs: [IntakeLog],
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> Int {
        let today = calendar.startOfDay(for: now)
        let medLogs = intakeLogs.filter { $0.medicationID == medicationID }
        guard let earliest = medLogs.min(by: { $0.date < $1.date }) else { return 0 }
        let earliestDay = calendar.startOfDay(for: earliest.date)

        guard let med = medications.first(where: { $0.id == medicationID }) else { return 0 }
        let times = med.timesOfDay.compactMap { c -> (Int, Int)? in
            guard let h = c.hour, let m = c.minute else { return nil }
            return (h, m)
        }
        if times.isEmpty { return 0 }

        var missed = 0
        for offset in 1..<60 {
            guard let day = calendar.date(byAdding: .day, value: -offset, to: today) else { break }
            if day < earliestDay { break }
            let dayEnd = calendar.date(byAdding: .day, value: 1, to: day)!
            let dayLogs = intakeLogs.filter { $0.medicationID == medicationID && $0.date >= day && $0.date < dayEnd }
            let hasTaken = dayLogs.contains { $0.status == .taken }
            if hasTaken { break }
            missed += 1
        }
        return missed
    }

    // MARK: - Day logs

    static func intakeLogs(
        for date: Date,
        medicationID: UUID? = nil,
        intakeLogs: [IntakeLog],
        calendar: Calendar = .current
    ) -> [IntakeLog] {
        let dayStart = calendar.startOfDay(for: date)
        let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart)!
        return intakeLogs.filter { log in
            guard log.date >= dayStart && log.date < dayEnd else { return false }
            if let mid = medicationID { return log.medicationID == mid }
            return true
        }.sorted(by: { $0.date < $1.date })
    }

    // MARK: - Helpers

    private static func filterMeds(_ medications: [Medication], for medicationID: UUID?) -> [Medication] {
        let filtered: [Medication]
        if let mid = medicationID {
            filtered = medications.filter { $0.id == mid }
        } else {
            filtered = medications
        }
        return filtered
    }

    private static func filterLogs(
        _ logs: [IntakeLog],
        from startDay: Date,
        to endDay: Date,
        medicationID: UUID?,
        calendar: Calendar
    ) -> [IntakeLog] {
        logs.filter { log in
            let day = calendar.startOfDay(for: log.date)
            guard day >= startDay && day <= endDay else { return false }
            if let mid = medicationID { return log.medicationID == mid }
            return true
        }
    }
}
