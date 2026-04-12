import Foundation

struct AdaptiveReminderStrategy: Equatable {
    enum RiskLevel: String, Equatable {
        case low
        case medium
        case high
    }

    let leadMinutes: Int
    let followUpIntervals: [Int]
    let riskLevel: RiskLevel
}

struct AdherenceProfile: Equatable {
    let sampleCount: Int
    let meanDelayMinutes: Int
    let missRate: Double
    let snoozeRate: Double
    let onTimeRate: Double
    let perfectDayStreak: Int
}

enum AdaptiveReminderEngine {
    private static let minimumAdaptiveSampleCount = 6

    private enum DoseOutcome {
        case taken(delayMinutes: Int)
        case snoozed
        case missed
    }

    static func strategy(
        for medication: Medication,
        intakeLogs: [IntakeLog],
        now: Date = Date()
    ) -> AdaptiveReminderStrategy {
        let profile = profile(for: medication, intakeLogs: intakeLogs, now: now)

        guard profile.sampleCount >= minimumAdaptiveSampleCount else {
            return AdaptiveReminderStrategy(
                leadMinutes: 0,
                followUpIntervals: [10, 30],
                riskLevel: .medium
            )
        }

        var leadMinutes = 0
        if profile.meanDelayMinutes >= 20 {
            leadMinutes = 15
        } else if profile.meanDelayMinutes >= 10 {
            leadMinutes = 10
        }

        if profile.onTimeRate >= 0.7 {
            leadMinutes = 0
        }

        if profile.missRate >= 0.35 {
            return AdaptiveReminderStrategy(leadMinutes: max(leadMinutes, 15), followUpIntervals: [10, 20, 45], riskLevel: .high)
        }

        if profile.missRate >= 0.2 || profile.snoozeRate >= 0.3 {
            return AdaptiveReminderStrategy(leadMinutes: max(leadMinutes, 10), followUpIntervals: [10, 25, 50], riskLevel: .medium)
        }

        if profile.perfectDayStreak >= 7 && profile.missRate <= 0.1 {
            return AdaptiveReminderStrategy(leadMinutes: 0, followUpIntervals: [20], riskLevel: .low)
        }

        return AdaptiveReminderStrategy(leadMinutes: leadMinutes, followUpIntervals: [10, 30, 60], riskLevel: .medium)
    }

    static func profile(
        for medication: Medication,
        intakeLogs: [IntakeLog],
        now: Date = Date()
    ) -> AdherenceProfile {
        guard medication.isAsNeeded != true else {
            return AdherenceProfile(sampleCount: 0, meanDelayMinutes: 0, missRate: 0, snoozeRate: 0, onTimeRate: 0, perfectDayStreak: 0)
        }

        let cal = Calendar.current
        let today = cal.startOfDay(for: now)
        let startDay = cal.date(byAdding: .day, value: -13, to: today) ?? today
        let effectiveStartDay = max(startDay, cal.startOfDay(for: medication.startDate))
        let outcomesByDay = outcomes(for: medication, intakeLogs: intakeLogs, startDay: effectiveStartDay, endDate: now)
        let flatOutcomes = outcomesByDay.keys.sorted().flatMap { outcomesByDay[$0] ?? [] }
        let delays = flatOutcomes.compactMap { outcome -> Int? in
            if case .taken(let delayMinutes) = outcome { return delayMinutes }
            return nil
        }
        let dueCount = flatOutcomes.count
        let missCount = flatOutcomes.reduce(into: 0) { count, outcome in
            if case .missed = outcome { count += 1 }
        }
        let snoozeCount = flatOutcomes.reduce(into: 0) { count, outcome in
            if case .snoozed = outcome { count += 1 }
        }
        let onTimeCount = flatOutcomes.reduce(into: 0) { count, outcome in
            if case .taken(let delayMinutes) = outcome, delayMinutes <= 5 { count += 1 }
        }

        return AdherenceProfile(
            sampleCount: dueCount,
            meanDelayMinutes: mean(of: delays),
            missRate: dueCount > 0 ? Double(missCount) / Double(dueCount) : 0,
            snoozeRate: dueCount > 0 ? Double(snoozeCount) / Double(dueCount) : 0,
            onTimeRate: dueCount > 0 ? Double(onTimeCount) / Double(dueCount) : 0,
            perfectDayStreak: perfectDayStreak(from: outcomesByDay, today: today)
        )
    }

    private static func outcomes(
        for medication: Medication,
        intakeLogs: [IntakeLog],
        startDay: Date,
        endDate: Date
    ) -> [Date: [DoseOutcome]] {
        let cal = Calendar.current
        let medicationLogs = intakeLogs.filter { $0.medicationID == medication.id }
        let times = medication.timesOfDay.sorted { ($0.hour ?? 0, $0.minute ?? 0) < ($1.hour ?? 0, $1.minute ?? 0) }
        guard !times.isEmpty else { return [:] }

        var result: [Date: [DoseOutcome]] = [:]
        var day = startDay
        let endDay = cal.startOfDay(for: endDate)

        while day <= endDay {
            let dayStart = cal.startOfDay(for: day)
            let dayEnd = cal.date(byAdding: .day, value: 1, to: dayStart) ?? dayStart
            var dayOutcomes: [DoseOutcome] = []

            for comps in times {
                guard let hour = comps.hour,
                      let minute = comps.minute,
                      let scheduledDoseDate = cal.date(bySettingHour: hour, minute: minute, second: 0, of: dayStart),
                      scheduledDoseDate <= endDate else { continue }
                guard medication.isDoseActive(on: scheduledDoseDate, calendar: cal) else { continue }

                let key = String(format: "%02d:%02d", hour, minute)
                let latest = medicationLogs
                    .filter { log in
                        guard log.date >= dayStart && log.date < dayEnd else { return false }
                        return log.scheduleKey == key || (times.count == 1 && log.scheduleKey == nil)
                    }
                    .sorted { $0.effectiveRecordedAt > $1.effectiveRecordedAt }
                    .first

                let outcome: DoseOutcome
                switch latest?.status {
                case .taken:
                    let actual = latest?.effectiveRecordedAt ?? scheduledDoseDate
                    let delay = max(-30, Int(actual.timeIntervalSince(scheduledDoseDate) / 60))
                    outcome = .taken(delayMinutes: delay)
                case .snoozed:
                    outcome = .snoozed
                case .skipped:
                    outcome = .missed
                case .none:
                    outcome = .missed
                }
                dayOutcomes.append(outcome)
            }

            if !dayOutcomes.isEmpty {
                result[dayStart] = dayOutcomes
            }
            day = cal.date(byAdding: .day, value: 1, to: dayStart) ?? dayStart.addingTimeInterval(24 * 60 * 60)
        }

        return result
    }

    private static func perfectDayStreak(from outcomesByDay: [Date: [DoseOutcome]], today: Date) -> Int {
        let cal = Calendar.current
        var streak = 0
        var day = today

        if outcomesByDay[day]?.isEmpty ?? true {
            day = cal.date(byAdding: .day, value: -1, to: day) ?? day
        }

        while let dayOutcomes = outcomesByDay[day], !dayOutcomes.isEmpty {
            let allTaken = dayOutcomes.allSatisfy {
                if case .taken = $0 { return true }
                return false
            }
            if !allTaken { break }
            streak += 1
            guard let previous = cal.date(byAdding: .day, value: -1, to: day) else { break }
            day = previous
        }

        return streak
    }

    private static func mean(of values: [Int]) -> Int {
        guard !values.isEmpty else { return 0 }
        return Int((Double(values.reduce(0, +)) / Double(values.count)).rounded())
    }
}
