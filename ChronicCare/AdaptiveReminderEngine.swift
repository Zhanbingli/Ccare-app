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

struct AdaptiveReminderSuggestion: Identifiable, Equatable {
    enum Kind: String, Equatable {
        case increaseSupport
        case shiftEarlier
        case reduceNoise
    }

    let medicationID: UUID
    let medicationName: String
    let kind: Kind
    let title: String
    let detail: String
    let effectSummary: String
    let profile: AdherenceProfile
    let proposedStrategy: AdaptiveReminderStrategy

    var id: String { "\(medicationID.uuidString).\(kind.rawValue)" }
}

enum AdaptiveReminderPreferenceStore {
    private static let enabledPrefix = "adaptiveReminder.enabled."
    private static let dismissedPrefix = "adaptiveReminder.dismissed."
    private static let defaults = UserDefaults.standard

    static func isAdaptiveSchedulingEnabled(for medicationID: UUID) -> Bool {
        defaults.bool(forKey: enabledKey(for: medicationID))
    }

    static func setAdaptiveSchedulingEnabled(_ enabled: Bool, for medicationID: UUID) {
        defaults.set(enabled, forKey: enabledKey(for: medicationID))
    }

    static func dismissSuggestion(
        _ kind: AdaptiveReminderSuggestion.Kind,
        for medicationID: UUID,
        until date: Date = Calendar.current.date(byAdding: .day, value: 14, to: Date()) ?? Date().addingTimeInterval(14 * 24 * 60 * 60)
    ) {
        defaults.set(date, forKey: dismissedKey(for: medicationID, kind: kind))
    }

    static func clearDismissal(_ kind: AdaptiveReminderSuggestion.Kind, for medicationID: UUID) {
        defaults.removeObject(forKey: dismissedKey(for: medicationID, kind: kind))
    }

    static func isSuggestionDismissed(
        _ kind: AdaptiveReminderSuggestion.Kind,
        for medicationID: UUID,
        now: Date = Date()
    ) -> Bool {
        guard let until = defaults.object(forKey: dismissedKey(for: medicationID, kind: kind)) as? Date else {
            return false
        }
        if until <= now {
            defaults.removeObject(forKey: dismissedKey(for: medicationID, kind: kind))
            return false
        }
        return true
    }

    static func clearAll(for medicationID: UUID) {
        defaults.removeObject(forKey: enabledKey(for: medicationID))
        for kind in [AdaptiveReminderSuggestion.Kind.increaseSupport, .shiftEarlier, .reduceNoise] {
            defaults.removeObject(forKey: dismissedKey(for: medicationID, kind: kind))
        }
    }

    private static func enabledKey(for medicationID: UUID) -> String {
        "\(enabledPrefix)\(medicationID.uuidString)"
    }

    private static func dismissedKey(for medicationID: UUID, kind: AdaptiveReminderSuggestion.Kind) -> String {
        "\(dismissedPrefix)\(medicationID.uuidString).\(kind.rawValue)"
    }
}

enum AdaptiveReminderEngine {
    private static let minimumAdaptiveSampleCount = 6

    static let standardStrategy = AdaptiveReminderStrategy(
        leadMinutes: 0,
        followUpIntervals: [10, 30],
        riskLevel: .medium
    )

    private enum DoseOutcome {
        case taken(delayMinutes: Int)
        case snoozed
        case missed
        case skipped
    }

    // MARK: - Time Period Classification

    private enum TimePeriod {
        case morning   // 05:00 - 11:59
        case afternoon // 12:00 - 17:59
        case evening   // 18:00 - 04:59

        init(hour: Int) {
            switch hour {
            case 5..<12: self = .morning
            case 12..<18: self = .afternoon
            default: self = .evening
            }
        }
    }

    static func strategy(
        for medication: Medication,
        intakeLogs: [IntakeLog],
        now: Date = Date(),
        scheduleTime: DateComponents? = nil
    ) -> AdaptiveReminderStrategy {
        let profile: AdherenceProfile
        if let h = scheduleTime?.hour {
            // Use time-period-specific profile when a specific dose time is provided
            profile = periodProfile(for: medication, intakeLogs: intakeLogs, period: TimePeriod(hour: h), now: now)
        } else {
            profile = self.profile(for: medication, intakeLogs: intakeLogs, now: now)
        }

        guard profile.sampleCount >= minimumAdaptiveSampleCount else {
            return standardStrategy
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

        // High risk
        if profile.missRate >= 0.35 {
            return AdaptiveReminderStrategy(leadMinutes: max(leadMinutes, 15), followUpIntervals: [10, 20, 45], riskLevel: .high)
        }

        // Medium risk
        if profile.missRate >= 0.2 || profile.snoozeRate >= 0.3 {
            return AdaptiveReminderStrategy(leadMinutes: max(leadMinutes, 10), followUpIntervals: [10, 25, 50], riskLevel: .medium)
        }

        // Low risk — gradual reward based on streak length
        if profile.missRate <= 0.1 {
            if profile.perfectDayStreak >= 14 {
                // 14+ day streak: minimal follow-up
                return AdaptiveReminderStrategy(leadMinutes: 0, followUpIntervals: [30], riskLevel: .low)
            }
            if profile.perfectDayStreak >= 7 {
                // 7-13 day streak: reduced but not minimal
                return AdaptiveReminderStrategy(leadMinutes: 0, followUpIntervals: [15, 45], riskLevel: .low)
            }
        }

        return AdaptiveReminderStrategy(leadMinutes: leadMinutes, followUpIntervals: [10, 30, 60], riskLevel: .medium)
    }

    static func schedulingStrategy(
        for medication: Medication,
        intakeLogs: [IntakeLog],
        now: Date = Date(),
        scheduleTime: DateComponents? = nil
    ) -> AdaptiveReminderStrategy {
        guard AdaptiveReminderPreferenceStore.isAdaptiveSchedulingEnabled(for: medication.id) else {
            return standardStrategy
        }
        return strategy(for: medication, intakeLogs: intakeLogs, now: now, scheduleTime: scheduleTime)
    }

    static func suggestions(
        for medications: [Medication],
        intakeLogs: [IntakeLog],
        now: Date = Date()
    ) -> [AdaptiveReminderSuggestion] {
        medications
            .compactMap { suggestion(for: $0, intakeLogs: intakeLogs, now: now) }
            .sorted { lhs, rhs in
                if lhs.kind.sortPriority != rhs.kind.sortPriority {
                    return lhs.kind.sortPriority < rhs.kind.sortPriority
                }
                return lhs.medicationName.localizedCaseInsensitiveCompare(rhs.medicationName) == .orderedAscending
            }
    }

    static func suggestion(
        for medication: Medication,
        intakeLogs: [IntakeLog],
        now: Date = Date()
    ) -> AdaptiveReminderSuggestion? {
        guard medication.remindersEnabled,
              medication.isAsNeeded != true,
              !medication.timesOfDay.isEmpty,
              !AdaptiveReminderPreferenceStore.isAdaptiveSchedulingEnabled(for: medication.id) else {
            return nil
        }

        let profile = profile(for: medication, intakeLogs: intakeLogs, now: now)
        guard profile.sampleCount >= minimumAdaptiveSampleCount else { return nil }

        let proposed = strategy(for: medication, intakeLogs: intakeLogs, now: now)
        let kind: AdaptiveReminderSuggestion.Kind
        if profile.missRate >= 0.35 {
            kind = .increaseSupport
        } else if profile.meanDelayMinutes >= 10 || profile.snoozeRate >= 0.3 {
            kind = .shiftEarlier
        } else if profile.missRate <= 0.1 && profile.perfectDayStreak >= 7 && proposed.followUpIntervals.count < standardStrategy.followUpIntervals.count {
            kind = .reduceNoise
        } else {
            return nil
        }

        guard !AdaptiveReminderPreferenceStore.isSuggestionDismissed(kind, for: medication.id, now: now) else {
            return nil
        }

        return AdaptiveReminderSuggestion(
            medicationID: medication.id,
            medicationName: medication.name,
            kind: kind,
            title: suggestionTitle(kind: kind, medicationName: medication.name),
            detail: suggestionDetail(kind: kind, profile: profile),
            effectSummary: strategySummary(proposed),
            profile: profile,
            proposedStrategy: proposed
        )
    }

    static func strategySummary(_ strategy: AdaptiveReminderStrategy) -> String {
        let followUps = formattedMinutesList(strategy.followUpIntervals)
        if strategy.leadMinutes > 0 {
            return String(
                format: NSLocalizedString("If you confirm, the first reminder can move %lld minutes earlier and follow-ups can use %@. This only changes reminder pressure, not medication dose.", comment: "Adaptive reminder effect summary with lead"),
                Int64(strategy.leadMinutes),
                followUps
            )
        }
        return String(
            format: NSLocalizedString("If you confirm, follow-ups can use %@. This only changes reminder pressure, not medication dose.", comment: "Adaptive reminder effect summary"),
            followUps
        )
    }

    static func confirmedStrategySummary(_ strategy: AdaptiveReminderStrategy) -> String {
        let followUps = formattedMinutesList(strategy.followUpIntervals)
        if strategy.leadMinutes > 0 {
            return String(
                format: NSLocalizedString("Current adaptive pattern: the first reminder may move %lld minutes earlier and follow-ups use %@. This does not change medication dose.", comment: "Adaptive reminder enabled summary with lead"),
                Int64(strategy.leadMinutes),
                followUps
            )
        }
        return String(
            format: NSLocalizedString("Current adaptive pattern: follow-ups use %@. This does not change medication dose.", comment: "Adaptive reminder enabled summary"),
            followUps
        )
    }

    // MARK: - Overall Profile

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
        return buildProfile(from: outcomesByDay, today: today)
    }

    // MARK: - Time-Period-Specific Profile

    private static func periodProfile(
        for medication: Medication,
        intakeLogs: [IntakeLog],
        period: TimePeriod,
        now: Date = Date()
    ) -> AdherenceProfile {
        guard medication.isAsNeeded != true else {
            return AdherenceProfile(sampleCount: 0, meanDelayMinutes: 0, missRate: 0, snoozeRate: 0, onTimeRate: 0, perfectDayStreak: 0)
        }

        let cal = Calendar.current
        let today = cal.startOfDay(for: now)
        let startDay = cal.date(byAdding: .day, value: -13, to: today) ?? today
        let effectiveStartDay = max(startDay, cal.startOfDay(for: medication.startDate))

        // Filter medication times to only those in the given period
        let periodTimes = medication.timesOfDay.filter { comps in
            guard let h = comps.hour else { return false }
            return TimePeriod(hour: h) == period
        }
        guard !periodTimes.isEmpty else {
            return AdherenceProfile(sampleCount: 0, meanDelayMinutes: 0, missRate: 0, snoozeRate: 0, onTimeRate: 0, perfectDayStreak: 0)
        }

        let outcomesByDay = outcomes(for: medication, intakeLogs: intakeLogs, startDay: effectiveStartDay, endDate: now, filterTimes: periodTimes)
        return buildProfile(from: outcomesByDay, today: today)
    }

    // MARK: - Build Profile from Outcomes

    private static func buildProfile(from outcomesByDay: [Date: [DoseOutcome]], today: Date) -> AdherenceProfile {
        let flatOutcomes = outcomesByDay.keys.sorted().flatMap { outcomesByDay[$0] ?? [] }
        let delays = flatOutcomes.compactMap { outcome -> Int? in
            if case .taken(let delayMinutes) = outcome { return delayMinutes }
            return nil
        }

        // Count only actionable outcomes (exclude skipped from denominator)
        let actionableOutcomes = flatOutcomes.filter {
            if case .skipped = $0 { return false }
            return true
        }
        let dueCount = actionableOutcomes.count
        let missCount = actionableOutcomes.reduce(into: 0) { count, outcome in
            if case .missed = outcome { count += 1 }
        }
        let snoozeCount = actionableOutcomes.reduce(into: 0) { count, outcome in
            if case .snoozed = outcome { count += 1 }
        }
        let onTimeCount = actionableOutcomes.reduce(into: 0) { count, outcome in
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

    // MARK: - Outcome Computation

    private static func outcomes(
        for medication: Medication,
        intakeLogs: [IntakeLog],
        startDay: Date,
        endDate: Date,
        filterTimes: [DateComponents]? = nil
    ) -> [Date: [DoseOutcome]] {
        let cal = Calendar.current
        let medicationLogs = intakeLogs.filter { $0.medicationID == medication.id }
        let times = (filterTimes ?? medication.timesOfDay)
            .sorted { ($0.hour ?? 0, $0.minute ?? 0) < ($1.hour ?? 0, $1.minute ?? 0) }
        guard !times.isEmpty else { return [:] }

        var result: [Date: [DoseOutcome]] = [:]
        var day = startDay
        let endDay = cal.startOfDay(for: endDate)
        let todayStart = cal.startOfDay(for: endDate)

        while day <= endDay {
            let dayStart = cal.startOfDay(for: day)
            let dayEnd = cal.date(byAdding: .day, value: 1, to: dayStart) ?? dayStart
            let isPastDay = dayStart < todayStart
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
                    // Snoozed with no final resolution on a past day counts as missed
                    outcome = isPastDay ? .missed : .snoozed
                case .skipped:
                    outcome = .skipped
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
            // Perfect day: all doses taken or intentionally skipped (not missed)
            let allHandled = dayOutcomes.allSatisfy {
                switch $0 {
                case .taken, .skipped: return true
                default: return false
                }
            }
            if !allHandled { break }
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

    private static func suggestionTitle(kind: AdaptiveReminderSuggestion.Kind, medicationName: String) -> String {
        switch kind {
        case .increaseSupport:
            return String(format: NSLocalizedString("Strengthen reminders for %@", comment: "Adaptive reminder suggestion title"), medicationName)
        case .shiftEarlier:
            return String(format: NSLocalizedString("Shift reminders earlier for %@", comment: "Adaptive reminder suggestion title"), medicationName)
        case .reduceNoise:
            return String(format: NSLocalizedString("Reduce reminder noise for %@", comment: "Adaptive reminder suggestion title"), medicationName)
        }
    }

    private static func suggestionDetail(kind: AdaptiveReminderSuggestion.Kind, profile: AdherenceProfile) -> String {
        switch kind {
        case .increaseSupport:
            return String(
                format: NSLocalizedString("Recent scheduled logs show a %lld%% missed-dose pattern. The app can make reminder follow-up more persistent after you confirm.", comment: "Adaptive reminder suggestion detail"),
                Int64((profile.missRate * 100).rounded())
            )
        case .shiftEarlier:
            return String(
                format: NSLocalizedString("Recent scheduled logs show an average delay of %lld minutes or repeated snoozes. The app can gently move reminder pressure earlier after you confirm.", comment: "Adaptive reminder suggestion detail"),
                Int64(profile.meanDelayMinutes)
            )
        case .reduceNoise:
            return String(
                format: NSLocalizedString("Recent history shows a %lld-day handled-dose streak. The app can reduce follow-up reminders after you confirm.", comment: "Adaptive reminder suggestion detail"),
                Int64(profile.perfectDayStreak)
            )
        }
    }

    private static func formattedMinutesList(_ minutes: [Int]) -> String {
        guard !minutes.isEmpty else {
            return NSLocalizedString("no follow-ups", comment: "Adaptive reminder no follow-ups")
        }
        let values = minutes.map {
            String(format: NSLocalizedString("%lld min", comment: "Adaptive reminder minute list item"), Int64($0))
        }
        return values.joined(separator: ", ")
    }
}

private extension AdaptiveReminderSuggestion.Kind {
    var sortPriority: Int {
        switch self {
        case .increaseSupport: return 0
        case .shiftEarlier: return 1
        case .reduceNoise: return 2
        }
    }
}
