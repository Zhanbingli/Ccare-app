import Foundation

// MARK: - Rule Data (configurable, not hardcoded)

/// A single medication's rule configuration.
/// Stored as data — the engine never hardcodes these values.
struct MedicationRuleConfig: Codable, Equatable {
    /// Minutes within which a second "taken" triggers a duplicate warning.
    var duplicateGuardMinutes: Int
    /// How far past scheduled time the user can still take a missed dose (fraction of interval to next dose, 0.0–1.0).
    var makeupWindowFraction: Double
    /// Minimum gap (minutes) before flagging a timing conflict with another medication.
    var timingConflictMinutes: Int
    /// Snooze intervals in minutes, applied in order. After exhausting all, dose is marked missed.
    var snoozeEscalation: [Int]
    /// Consecutive missed days thresholds: [gentle, urgent].
    var missEscalationThresholds: [Int]

    static let defaults = MedicationRuleConfig(
        duplicateGuardMinutes: 30,
        makeupWindowFraction: 0.5,
        timingConflictMinutes: 60,
        snoozeEscalation: [10, 5],
        missEscalationThresholds: [2, 3]
    )
}

/// Maps medication IDs to per-medication rule overrides.
/// Persisted to Documents/medication_rules.json.
@MainActor
final class MedicationRuleStore: ObservableObject {
    static let shared = MedicationRuleStore()

    /// Per-medication overrides. If absent, defaults apply.
    @Published private(set) var overrides: [UUID: MedicationRuleConfig] = [:]

    private let fileURL: URL

    private init() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        self.fileURL = docs.appendingPathComponent("medication_rules.json")
        load()
    }

    func rules(for medicationID: UUID) -> MedicationRuleConfig {
        overrides[medicationID] ?? MedicationRuleConfig.defaults
    }

    func setOverride(_ config: MedicationRuleConfig, for medicationID: UUID) {
        overrides[medicationID] = config
        save()
    }

    func removeOverride(for medicationID: UUID) {
        overrides.removeValue(forKey: medicationID)
        save()
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode([UUID: MedicationRuleConfig].self, from: data)
        else { return }
        overrides = decoded
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(overrides) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}

// MARK: - Rule Engine (reads data, executes deterministically)

/// Deterministic rule engine. Reads MedicationRuleConfig, returns clear results.
/// Zero AI. Zero hardcoded thresholds. All values come from rule data.
@MainActor
enum MedicationRules {

    // MARK: - Result Types

    enum DuplicateTakenResult {
        case allowed
        case blocked(minutesSinceLast: Int)
    }

    enum MakeupDoseResult {
        case canTakeLate
        case tooCloseToNext(next: Date)
        case noNextDose
    }

    enum TimingConflictResult {
        case ok
        case tooClose(med1: String, med2: String, gapMinutes: Int)
    }

    enum EscalationLevel {
        case none
        case gentle(missedDays: Int)
        case urgent(missedDays: Int)
    }

    enum SnoozeResult {
        case snooze(minutes: Int)   // schedule another reminder
        case exhausted              // no more snoozes — mark missed

        var isExhausted: Bool {
            if case .exhausted = self { return true }
            return false
        }
    }

    // MARK: - Rule 1: Duplicate Taken Guard

    static func checkDuplicateTaken(
        medicationID: UUID,
        scheduleTime: DateComponents?,
        intakeLogs: [IntakeLog],
        now: Date = Date()
    ) -> DuplicateTakenResult {
        let config = MedicationRuleStore.shared.rules(for: medicationID)
        let cal = Calendar.current
        let dayStart = cal.startOfDay(for: now)
        let dayEnd = cal.date(byAdding: .day, value: 1, to: dayStart)!
        let key: String? = {
            guard let h = scheduleTime?.hour, let m = scheduleTime?.minute else { return nil }
            return String(format: "%02d:%02d", h, m)
        }()

        let lastTaken = intakeLogs
            .filter { log in
                log.medicationID == medicationID &&
                log.status == .taken &&
                log.date >= dayStart && log.date < dayEnd &&
                (log.scheduleKey == key || key == nil)
            }
            .max(by: { $0.date < $1.date })

        guard let last = lastTaken else { return .allowed }

        let elapsed = Int(now.timeIntervalSince(last.date) / 60)
        if elapsed < config.duplicateGuardMinutes {
            return .blocked(minutesSinceLast: elapsed)
        }
        return .allowed
    }

    // MARK: - Rule 2: Makeup Dose

    static func checkMakeupDose(
        medication: Medication,
        missedTime: DateComponents,
        now: Date = Date()
    ) -> MakeupDoseResult {
        let config = MedicationRuleStore.shared.rules(for: medication.id)
        let cal = Calendar.current
        guard let h = missedTime.hour, let m = missedTime.minute,
              let scheduledDate = cal.date(bySettingHour: h, minute: m, second: 0, of: now)
        else { return .noNextDose }

        guard now > scheduledDate else { return .canTakeLate }

        let sortedTimes = medication.timesOfDay
            .compactMap { c -> (DateComponents, Date)? in
                guard let th = c.hour, let tm = c.minute,
                      let d = cal.date(bySettingHour: th, minute: tm, second: 0, of: now)
                else { return nil }
                return (c, d)
            }
            .sorted { $0.1 < $1.1 }

        let nextDose: Date? = {
            if let next = sortedTimes.first(where: { $0.1 > scheduledDate }) {
                return next.1
            }
            if let first = sortedTimes.first,
               let tomorrow = cal.date(byAdding: .day, value: 1, to: first.1) {
                return tomorrow
            }
            return nil
        }()

        guard let next = nextDose else { return .noNextDose }

        // Configurable window fraction (default 0.5 = midpoint)
        let interval = next.timeIntervalSince(scheduledDate)
        let cutoff = scheduledDate.addingTimeInterval(interval * config.makeupWindowFraction)

        if now < cutoff {
            return .canTakeLate
        } else {
            return .tooCloseToNext(next: next)
        }
    }

    // MARK: - Rule 3: Timing Conflict

    static func checkTimingConflicts(
        medications: [Medication]
    ) -> [TimingConflictResult] {
        var conflicts: [TimingConflictResult] = []

        struct MedTime {
            let medID: UUID
            let medName: String
            let minutesSinceMidnight: Int
        }

        let allTimes: [MedTime] = medications
            .filter { $0.remindersEnabled }
            .flatMap { med in
                med.timesOfDay.compactMap { c -> MedTime? in
                    guard let h = c.hour, let m = c.minute else { return nil }
                    return MedTime(medID: med.id, medName: med.name, minutesSinceMidnight: h * 60 + m)
                }
            }
            .sorted { $0.minutesSinceMidnight < $1.minutesSinceMidnight }

        for i in 0..<allTimes.count {
            for j in (i+1)..<allTimes.count {
                let a = allTimes[i], b = allTimes[j]
                guard a.medID != b.medID else { continue }
                let gap = b.minutesSinceMidnight - a.minutesSinceMidnight
                // Use the stricter (larger) conflict threshold of the two medications
                let configA = MedicationRuleStore.shared.rules(for: a.medID)
                let configB = MedicationRuleStore.shared.rules(for: b.medID)
                let threshold = max(configA.timingConflictMinutes, configB.timingConflictMinutes)
                if gap < threshold {
                    conflicts.append(.tooClose(med1: a.medName, med2: b.medName, gapMinutes: gap))
                }
            }
        }

        return conflicts
    }

    // MARK: - Rule 4: Miss Escalation

    static func escalationLevel(for medicationID: UUID, consecutiveMissedDays: Int) -> EscalationLevel {
        let config = MedicationRuleStore.shared.rules(for: medicationID)
        let thresholds = config.missEscalationThresholds.sorted()
        guard !thresholds.isEmpty else { return .none }

        let gentle = thresholds[0]
        let urgent = thresholds.count > 1 ? thresholds[1] : gentle

        if consecutiveMissedDays >= urgent {
            return .urgent(missedDays: consecutiveMissedDays)
        } else if consecutiveMissedDays >= gentle {
            return .gentle(missedDays: consecutiveMissedDays)
        }
        return .none
    }

    // MARK: - Rule 5: Snooze Escalation

    /// Returns the next snooze action based on how many times the user has already snoozed.
    static func nextSnooze(for medicationID: UUID, currentSnoozeCount: Int) -> SnoozeResult {
        let config = MedicationRuleStore.shared.rules(for: medicationID)
        if currentSnoozeCount < config.snoozeEscalation.count {
            return .snooze(minutes: config.snoozeEscalation[currentSnoozeCount])
        }
        return .exhausted
    }

    // MARK: - Daily Safety Summary

    struct DailySafetySummary {
        let timingConflicts: [String]
        let makeupAvailable: [String]
        let missEscalations: [String]

        var hasIssues: Bool {
            !timingConflicts.isEmpty || !missEscalations.isEmpty
        }
    }

    static func dailySafetyCheck(
        medications: [Medication],
        intakeLogs: [IntakeLog],
        consecutiveMissedDaysProvider: (UUID) -> Int,
        now: Date = Date()
    ) -> DailySafetySummary {
        var makeupAvailable: [String] = []
        var missEscalations: [String] = []

        let cal = Calendar.current

        for med in medications where med.remindersEnabled {
            // Miss escalation
            let missed = consecutiveMissedDaysProvider(med.id)
            switch escalationLevel(for: med.id, consecutiveMissedDays: missed) {
            case .gentle(let days), .urgent(let days):
                missEscalations.append(String(format: NSLocalizedString("You haven't taken %@ for %lld days. Please take it or talk to your doctor.", comment: ""), med.name, days))
            case .none:
                break
            }

            // Makeup doses
            let dayStart = cal.startOfDay(for: now)
            let dayEnd = cal.date(byAdding: .day, value: 1, to: dayStart)!
            for t in med.timesOfDay {
                guard let h = t.hour, let m = t.minute,
                      let sched = cal.date(bySettingHour: h, minute: m, second: 0, of: now),
                      now > sched else { continue }

                let key = String(format: "%02d:%02d", h, m)
                let alreadyHandled = intakeLogs.contains { log in
                    log.medicationID == med.id &&
                    log.date >= dayStart && log.date < dayEnd &&
                    log.scheduleKey == key &&
                    (log.status == .taken || log.status == .skipped)
                }
                guard !alreadyHandled else { continue }

                if case .canTakeLate = checkMakeupDose(medication: med, missedTime: t, now: now) {
                    let formatter = DateFormatter()
                    formatter.timeStyle = .short
                    let timeStr = formatter.string(from: sched)
                    makeupAvailable.append(String(format: NSLocalizedString("%@ (%@) — you can still take it now", comment: ""), med.name, timeStr))
                }
            }
        }

        // Timing conflicts
        let conflicts = checkTimingConflicts(medications: medications)
        let conflictMessages = conflicts.compactMap { result -> String? in
            if case .tooClose(let m1, let m2, let gap) = result {
                return String(format: NSLocalizedString("%@ and %@ are only %lld minutes apart", comment: ""), m1, m2, gap)
            }
            return nil
        }

        return DailySafetySummary(
            timingConflicts: conflictMessages,
            makeupAvailable: makeupAvailable,
            missEscalations: missEscalations
        )
    }
}
