import Foundation
import SwiftUI

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
        case reminderNotWorking
        case correlationTrend

        var icon: String {
            switch self {
            case .skippedFrequently: return "exclamationmark.triangle.fill"
            case .timeAdjustmentSuggestion: return "clock.arrow.circlepath"
            case .adherenceImprovement: return "chart.line.uptrend.xyaxis"
            case .reminderNotWorking: return "bell.slash.fill"
            case .correlationTrend: return "chart.xyaxis.line"
            }
        }

        var color: Color {
            switch self {
            case .skippedFrequently: return .orange
            case .timeAdjustmentSuggestion: return .blue
            case .adherenceImprovement: return .purple
            case .reminderNotWorking: return .gray
            case .correlationTrend: return .teal
            }
        }
    }
}

@MainActor
class MedicationInsightsEngine {

    static func generateInsights(
        medications: [Medication],
        intakeLogs: [IntakeLog],
        measurements: [Measurement] = [],
        store: DataStore
    ) -> [MedicationInsight] {
        var insights: [MedicationInsight] = []

        for medication in medications where medication.remindersEnabled && medication.isAsNeeded != true {
            // Check for frequent skips
            if let skipInsight = checkFrequentSkips(medication: medication, logs: intakeLogs) {
                insights.append(skipInsight)
            }

            // Check for low adherence
            if let adherenceInsight = checkLowAdherence(medication: medication, logs: intakeLogs) {
                insights.append(adherenceInsight)
            }

            // Check for reminder time optimization
            if let timeInsight = suggestBetterTime(medication: medication, logs: intakeLogs) {
                insights.append(timeInsight)
            }

            // Check for medication-measurement correlation
            if let corrInsight = checkCorrelationTrend(medication: medication, logs: intakeLogs, measurements: measurements) {
                insights.append(corrInsight)
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
                action: {
                    NotificationCenter.default.post(name: Notification.Name("openMedicationDetail"), object: medication.id)
                }
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
                action: {
                    NotificationCenter.default.post(name: Notification.Name("openMedicationDetail"), object: medication.id)
                }
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
        let avgHour = Int(round(Double(actualTimes.reduce(0, +)) / Double(actualTimes.count)))

        // Get scheduled times
        let scheduledHours = medication.timesOfDay.compactMap { $0.hour }
        guard !scheduledHours.isEmpty else { return nil }

        let avgScheduledHour = Int(round(Double(scheduledHours.reduce(0, +)) / Double(scheduledHours.count)))

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

    // MARK: - Medication-Measurement Correlation

    private static func checkCorrelationTrend(medication: Medication, logs: [IntakeLog], measurements: [Measurement]) -> MedicationInsight? {
        guard let category = medication.category else { return nil }
        let correlatedTypes = category.correlatedMeasurementTypes
        guard !correlatedTypes.isEmpty else { return nil }

        let cal = Calendar.current
        let now = Date()
        // Need at least 14 days of data
        guard let firstLog = logs.filter({ $0.medicationID == medication.id && $0.status == .taken }).sorted(by: { $0.date < $1.date }).first,
              cal.dateComponents([.day], from: firstLog.date, to: now).day ?? 0 >= 14 else { return nil }

        for mType in correlatedTypes {
            let typeMeasurements = measurements.filter { $0.type == mType }.sorted { $0.date < $1.date }
            guard typeMeasurements.count >= 4 else { continue }

            // Compare first week average vs last week average
            let sevenDaysAgo = cal.date(byAdding: .day, value: -7, to: now)!
            let fourteenDaysAgo = cal.date(byAdding: .day, value: -14, to: now)!

            let recentValues = typeMeasurements.filter { $0.date >= sevenDaysAgo }.map { $0.value }
            let earlierValues = typeMeasurements.filter { $0.date >= fourteenDaysAgo && $0.date < sevenDaysAgo }.map { $0.value }

            guard recentValues.count >= 2, earlierValues.count >= 2 else { continue }

            let recentAvg = recentValues.reduce(0, +) / Double(recentValues.count)
            let earlierAvg = earlierValues.reduce(0, +) / Double(earlierValues.count)
            guard earlierAvg != 0 else { continue }
            let change = recentAvg - earlierAvg
            let pctChange = abs(change / earlierAvg) * 100

            // Only report if change is meaningful (>5%)
            guard pctChange > 5 else { continue }

            let direction = change < 0
                ? NSLocalizedString("decreased", comment: "")
                : NSLocalizedString("increased", comment: "")
            let message = String(format: NSLocalizedString("While taking %@, your %@ has %@ by %.0f%% over the past week.", comment: ""),
                                 medication.name, mType.rawValue, direction, pctChange)

            return MedicationInsight(
                medicationID: medication.id,
                type: .correlationTrend,
                message: message,
                actionTitle: NSLocalizedString("View Trends", comment: ""),
                action: nil
            )
        }
        return nil
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
