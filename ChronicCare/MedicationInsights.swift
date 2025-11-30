import Foundation

struct MedicationInsight: Identifiable {
    let id = UUID()
    let medicationID: UUID
    let type: InsightType
    let message: String
    let actionTitle: String?
    let action: (() -> Void)?

    enum InsightType {
        case skippedFrequently
        case timeAdjustmentSuggestion
        case adherenceImprovement
        case effectivenessLow
        case reminderNotWorking
    }
}

@MainActor
class MedicationInsightsEngine {

    static func generateInsights(
        medications: [Medication],
        intakeLogs: [IntakeLog],
        store: DataStore
    ) -> [MedicationInsight] {
        var insights: [MedicationInsight] = []

        for medication in medications where medication.remindersEnabled {
            // Check for frequent skips
            if let skipInsight = checkFrequentSkips(medication: medication, logs: intakeLogs) {
                insights.append(skipInsight)
            }

            // Check for low adherence
            if let adherenceInsight = checkLowAdherence(medication: medication, logs: intakeLogs) {
                insights.append(adherenceInsight)
            }

            // Check for medication effectiveness
            if let category = medication.category, category != .unspecified {
                if let effectivenessInsight = checkEffectiveness(medication: medication, store: store) {
                    insights.append(effectivenessInsight)
                }
            }

            // Check for reminder time optimization
            if let timeInsight = suggestBetterTime(medication: medication, logs: intakeLogs) {
                insights.append(timeInsight)
            }
        }

        return insights
    }

    // MARK: - Skip Analysis

    private static func checkFrequentSkips(medication: Medication, logs: [IntakeLog]) -> MedicationInsight? {
        let stats = calculateAdherenceStats(medication: medication, logs: logs, days: 30)
        guard stats.taken + stats.skipped + stats.missed >= 10 else { return nil }
        let skipRate = Double(stats.skipped) / Double(max(1, stats.taken + stats.skipped + stats.missed))

        if skipRate > 0.3 {
            return MedicationInsight(
                medicationID: medication.id,
                type: .skippedFrequently,
                message: String(format: NSLocalizedString("You've skipped %@ %d times in the past 30 days (%d%%). Consider adjusting the reminder time or discussing with your doctor.", comment: ""), medication.name, stats.skipped, Int(skipRate * 100)),
                actionTitle: NSLocalizedString("Adjust Time", comment: ""),
                action: nil
            )
        }

        return nil
    }

    // MARK: - Adherence Analysis

    private static func checkLowAdherence(medication: Medication, logs: [IntakeLog]) -> MedicationInsight? {
        let stats = calculateAdherenceStats(medication: medication, logs: logs, days: 7)
        let expected = max(1, stats.taken + stats.skipped + stats.missed)
        let adherenceRate = Double(stats.taken) / Double(expected)

        if adherenceRate < 0.7 {
            return MedicationInsight(
                medicationID: medication.id,
                type: .adherenceImprovement,
                message: String(format: NSLocalizedString("Your adherence to %@ is %d%% in the past week. Consistent use is important for best results.", comment: ""), medication.name, Int(adherenceRate * 100)),
                actionTitle: NSLocalizedString("Set Reminder", comment: ""),
                action: nil
            )
        }

        return nil
    }

    // MARK: - Effectiveness Analysis

    private static func checkEffectiveness(medication: Medication, store: DataStore) -> MedicationInsight? {
        let result = store.effectiveness(for: medication)

        if result.verdict == .likelyIneffective && result.confidence > 50 {
            return MedicationInsight(
                medicationID: medication.id,
                type: .effectivenessLow,
                message: String(format: NSLocalizedString("%@ may not be as effective as expected (confidence: %d%%). Consider discussing with your healthcare provider.", comment: ""), medication.name, result.confidence),
                actionTitle: NSLocalizedString("View Details", comment: ""),
                action: nil
            )
        }

        return nil
    }

    // MARK: - Time Optimization

    private static func suggestBetterTime(medication: Medication, logs: [IntakeLog]) -> MedicationInsight? {
        let cal = Calendar.current
        let thirtyDaysAgo = cal.date(byAdding: .day, value: -30, to: Date())!

        let recentLogs = logs.filter {
            $0.medicationID == medication.id &&
            $0.date >= thirtyDaysAgo &&
            $0.status == .taken
        }

        guard recentLogs.count >= 10 else { return nil }

        // Analyze when user actually takes the medication
        let actualTimes = recentLogs.map { cal.component(.hour, from: $0.date) }
        guard !actualTimes.isEmpty else { return nil }

        // Calculate average hour
        let avgHour = actualTimes.reduce(0, +) / actualTimes.count

        // Get scheduled times
        let scheduledHours = medication.timesOfDay.compactMap { $0.hour }
        guard !scheduledHours.isEmpty else { return nil }

        let avgScheduledHour = scheduledHours.reduce(0, +) / scheduledHours.count

        // If average actual time is more than 2 hours different
        if abs(avgHour - avgScheduledHour) >= 2 {
            return MedicationInsight(
                medicationID: medication.id,
                type: .timeAdjustmentSuggestion,
                message: String(format: NSLocalizedString("You typically take %@ around %d:00, but it's scheduled for %d:00. Would you like to adjust the reminder time?", comment: ""), medication.name, avgHour, avgScheduledHour),
                actionTitle: NSLocalizedString("Adjust Time", comment: ""),
                action: nil
            )
        }

        return nil
    }

    // MARK: - Adherence Statistics

    static func calculateAdherenceStats(
        medication: Medication,
        logs: [IntakeLog],
        days: Int = 30
    ) -> (taken: Int, missed: Int, skipped: Int, adherenceRate: Double) {
        let cal = Calendar.current
        let startDate = cal.date(byAdding: .day, value: -days, to: Date())!

        let relevantLogs = logs.filter {
            $0.medicationID == medication.id &&
            $0.date >= startDate
        }

        let taken = relevantLogs.filter { $0.status == .taken }.count
        let skipped = relevantLogs.filter { $0.status == .skipped }.count

        let expectedDoses = days * medication.timesOfDay.count
        let missed = max(0, expectedDoses - taken - skipped)

        let adherenceRate = expectedDoses > 0 ? Double(taken) / Double(expectedDoses) : 0.0

        return (taken, missed, skipped, adherenceRate)
    }

    // MARK: - Smart Suggestions

    static func suggestMedicationTimeSlots(currentLogs: [IntakeLog]) -> [DateComponents] {
        // Analyze when user is most likely to take medications
        let cal = Calendar.current

        let hourCounts = currentLogs.reduce(into: [Int: Int]()) { counts, log in
            let hour = cal.component(.hour, from: log.date)
            counts[hour, default: 0] += 1
        }

        // Find the top 3 most common hours
        let topHours = hourCounts.sorted { $0.value > $1.value }
            .prefix(3)
            .map { $0.key }
            .sorted()

        return topHours.map { hour in
            DateComponents(hour: hour, minute: 0)
        }
    }
}
