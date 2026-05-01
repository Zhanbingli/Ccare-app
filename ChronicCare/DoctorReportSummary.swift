import Foundation

struct DoctorReportSummary {
    struct MedicationLine: Identifiable {
        let id: UUID
        let source: MedicationSource
        let name: String
        let dose: String
        let schedule: String
        let caption: String?
    }

    struct AdherenceGap: Identifiable {
        let id: UUID
        let medicationName: String
        let missedDays: [Date]
    }

    struct MeasurementHighlight: Identifiable {
        let id: MeasurementType
        let type: MeasurementType
        let latestValue: String
        let latestDate: Date
        let entryCount: Int
        let outOfRangeCount: Int
        let series: [Measurement]
    }

    struct SymptomHighlight: Identifiable {
        let id: UUID
        let date: Date
        let severity: SymptomSeverity
        let summary: String
        let note: String?
    }

    let generatedAt: Date
    let days: Int
    let visit: DoctorVisit?
    let allergies: String?
    let redFlags: [String]
    let medications: [MedicationLine]
    let adherenceGaps: [AdherenceGap]
    let measurements: [MeasurementHighlight]
    let symptoms: [SymptomHighlight]
    let talkingPoints: [String]
}

enum DoctorReportSummaryBuilder {
    @MainActor
    static func build(store: DataStore, days: Int = 30, visit: DoctorVisit? = nil, now: Date = Date()) -> DoctorReportSummary {
        let resolvedVisit = visit ?? store.nextDoctorVisit
        let allergies = store.emergencyInfo?.allergies?.trimmedNilIfEmpty
        let medications = medicationLines(from: store.medications)
        let adherenceGaps = missedDoseGaps(store: store, days: days, now: now)
        let measurements = measurementHighlights(store: store, days: days, now: now)
        let symptoms = symptomHighlights(store: store, days: days, now: now)
        let redFlags = redFlags(
            allergies: allergies,
            medications: store.medications,
            adherenceGaps: adherenceGaps,
            measurements: measurements,
            symptoms: symptoms
        )
        let talkingPoints = talkingPoints(
            visit: resolvedVisit,
            medicationCount: store.medications.count,
            adherenceGaps: adherenceGaps,
            measurements: measurements,
            symptoms: symptoms
        )

        return DoctorReportSummary(
            generatedAt: now,
            days: days,
            visit: resolvedVisit,
            allergies: allergies,
            redFlags: redFlags,
            medications: medications,
            adherenceGaps: adherenceGaps,
            measurements: measurements,
            symptoms: symptoms,
            talkingPoints: talkingPoints
        )
    }

    private static func medicationLines(from medications: [Medication]) -> [DoctorReportSummary.MedicationLine] {
        let sourceOrder: [MedicationSource] = [.prescribed, .external, .otc, .supplement, .unknown]
        return medications.sorted { lhs, rhs in
            let lhsSource = lhs.source ?? .unknown
            let rhsSource = rhs.source ?? .unknown
            let lhsIndex = sourceOrder.firstIndex(of: lhsSource) ?? sourceOrder.count
            let rhsIndex = sourceOrder.firstIndex(of: rhsSource) ?? sourceOrder.count
            if lhsIndex != rhsIndex { return lhsIndex < rhsIndex }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
        .map { med in
            DoctorReportSummary.MedicationLine(
                id: med.id,
                source: med.source ?? .unknown,
                name: med.name,
                dose: med.dose,
                schedule: medicationSchedule(med),
                caption: medicationCaption(med)
            )
        }
    }

    private static func medicationCaption(_ med: Medication) -> String? {
        var parts: [String] = []
        if med.startDate > .distantPast {
            parts.append(String(format: NSLocalizedString("Since %@", comment: "Visit summary medication start date"), shortDateFormatter.string(from: med.startDate)))
        }
        if let hospital = med.hospital?.trimmingCharacters(in: .whitespacesAndNewlines), !hospital.isEmpty {
            parts.append(hospital)
        }
        let caption = parts.joined(separator: " · ")
        return caption.isEmpty ? nil : caption
    }

    private static func medicationSchedule(_ med: Medication) -> String {
        if med.isAsNeeded == true {
            return NSLocalizedString("PRN", comment: "As needed")
        }
        guard !med.timesOfDay.isEmpty else {
            return NSLocalizedString("No time set", comment: "Medication schedule missing")
        }
        return med.timesOfDay.map { comps in
            String(format: "%02d:%02d", comps.hour ?? 0, comps.minute ?? 0)
        }
        .joined(separator: " / ")
    }

    @MainActor
    private static func missedDoseGaps(store: DataStore, days: Int, now: Date) -> [DoctorReportSummary.AdherenceGap] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: now)
        var results: [DoctorReportSummary.AdherenceGap] = []

        for med in store.medications where med.isAsNeeded != true && !med.timesOfDay.isEmpty {
            var missedDays: [Date] = []
            for offset in 1...days {
                guard let day = cal.date(byAdding: .day, value: -offset, to: today) else { continue }
                guard med.startDate <= (cal.date(byAdding: .day, value: 1, to: day) ?? day) else { continue }
                if let courseEnd = med.courseEndDate, day > cal.startOfDay(for: courseEnd) { continue }

                let counts = AdherenceCalculator.dayCounts(dayKey: day, medications: [med], logs: store.intakeLogs)
                if counts.total > 0 && counts.taken == 0 {
                    missedDays.append(day)
                }
            }
            if !missedDays.isEmpty {
                results.append(DoctorReportSummary.AdherenceGap(id: med.id, medicationName: med.name, missedDays: missedDays))
            }
        }

        return results.sorted { $0.missedDays.count > $1.missedDays.count }
    }

    @MainActor
    private static func measurementHighlights(store: DataStore, days: Int, now: Date) -> [DoctorReportSummary.MeasurementHighlight] {
        let cal = Calendar.current
        guard let cutoff = cal.date(byAdding: .day, value: -days, to: now) else { return [] }

        return MeasurementType.allCases.compactMap { type in
            let series = store.measurements
                .filter { $0.type == type && $0.date >= cutoff }
                .sorted { $0.date < $1.date }
            guard let latest = series.last else { return nil }

            return DoctorReportSummary.MeasurementHighlight(
                id: type,
                type: type,
                latestValue: formattedValue(latest),
                latestDate: latest.date,
                entryCount: series.count,
                outOfRangeCount: countAnomalies(type: type, series: series, store: store),
                series: series
            )
        }
    }

    @MainActor
    private static func countAnomalies(type: MeasurementType, series: [Measurement], store: DataStore) -> Int {
        switch type {
        case .bloodGlucose, .heartRate:
            guard let range = store.customGoalRange(for: type) else { return 0 }
            return series.filter { $0.value < range.lowerBound || $0.value > range.upperBound }.count
        case .bloodPressure:
            let thresholds = store.bpThresholds()
            return series.filter { $0.value > thresholds.systolicHigh || ($0.diastolic ?? 0) > thresholds.diastolicHigh }.count
        case .weight:
            return 0
        }
    }

    private static func formattedValue(_ measurement: Measurement) -> String {
        if measurement.type == .bloodPressure, let diastolic = measurement.diastolic {
            return "\(Int(measurement.value))/\(Int(diastolic)) \(measurement.type.unit)"
        }
        if measurement.type == .bloodGlucose {
            let value = UnitPreferences.mgdlToPreferred(measurement.value)
            let formatted = UnitPreferences.glucoseUnit == .mgdL
                ? String(format: "%.0f", value)
                : String(format: "%.1f", value)
            return "\(formatted) \(UnitPreferences.glucoseUnit.rawValue)"
        }
        if measurement.type == .heartRate {
            return "\(Int(measurement.value)) \(measurement.type.unit)"
        }
        return "\(String(format: "%.1f", measurement.value)) \(measurement.type.unit)"
    }

    @MainActor
    private static func symptomHighlights(store: DataStore, days: Int, now: Date) -> [DoctorReportSummary.SymptomHighlight] {
        let cal = Calendar.current
        guard let cutoff = cal.date(byAdding: .day, value: -days, to: now) else { return [] }

        return store.symptomEntries
            .filter { $0.date >= cutoff }
            .sorted { lhs, rhs in
                if lhs.severity.priority != rhs.severity.priority {
                    return lhs.severity.priority > rhs.severity.priority
                }
                return lhs.date > rhs.date
            }
            .prefix(5)
            .map { entry in
                DoctorReportSummary.SymptomHighlight(
                    id: entry.id,
                    date: entry.date,
                    severity: entry.severity,
                    summary: entry.tags.joined(separator: ", "),
                    note: entry.note
                )
            }
    }

    private static func redFlags(
        allergies: String?,
        medications: [Medication],
        adherenceGaps: [DoctorReportSummary.AdherenceGap],
        measurements: [DoctorReportSummary.MeasurementHighlight],
        symptoms: [DoctorReportSummary.SymptomHighlight]
    ) -> [String] {
        var flags: [String] = []
        if let allergies {
            flags.append(String(format: NSLocalizedString("Allergy: %@", comment: "PDF doctor summary red flag"), allergies))
        }
        let lowSupply = medications.filter { $0.isLowSupply }.map(\.name)
        if !lowSupply.isEmpty {
            flags.append(String(format: NSLocalizedString("Low supply: %@", comment: "PDF doctor summary red flag"), lowSupply.joined(separator: ", ")))
        }
        let missedTotal = adherenceGaps.reduce(0) { $0 + $1.missedDays.count }
        if missedTotal > 0 {
            flags.append(String(format: NSLocalizedString("%lld missed-dose days in the report window.", comment: "PDF doctor summary red flag"), missedTotal))
        }
        let abnormalReadings = measurements.reduce(0) { $0 + $1.outOfRangeCount }
        if abnormalReadings > 0 {
            flags.append(String(format: NSLocalizedString("%lld out-of-range home readings.", comment: "PDF doctor summary red flag"), abnormalReadings))
        }
        let severeSymptoms = symptoms.filter { $0.severity == .severe }
        if !severeSymptoms.isEmpty {
            flags.append(String(format: NSLocalizedString("%lld severe symptom notes.", comment: "PDF doctor summary red flag"), severeSymptoms.count))
        }
        return flags
    }

    private static func talkingPoints(
        visit: DoctorVisit?,
        medicationCount: Int,
        adherenceGaps: [DoctorReportSummary.AdherenceGap],
        measurements: [DoctorReportSummary.MeasurementHighlight],
        symptoms: [DoctorReportSummary.SymptomHighlight]
    ) -> [String] {
        var points: [String] = []
        if let visit {
            points.append(String(format: NSLocalizedString("Prepared for %@.", comment: "PDF doctor summary talking point"), visit.displayTitle))
        }
        if medicationCount > 0 {
            points.append(String(format: NSLocalizedString("Review %lld current medications and whether the schedule is still correct.", comment: "PDF doctor summary talking point"), medicationCount))
        }
        if let worstGap = adherenceGaps.first {
            points.append(String(format: NSLocalizedString("Discuss missed doses for %@.", comment: "PDF doctor summary talking point"), worstGap.medicationName))
        }
        if let abnormal = measurements.first(where: { $0.outOfRangeCount > 0 }) {
            points.append(String(format: NSLocalizedString("Review %@ readings with %lld out-of-range values.", comment: "PDF doctor summary talking point"), abnormal.type.displayName, abnormal.outOfRangeCount))
        }
        if let symptom = symptoms.first {
            points.append(String(format: NSLocalizedString("Discuss recent symptom: %@.", comment: "PDF doctor summary talking point"), symptom.summary))
        }
        if points.isEmpty {
            points.append(NSLocalizedString("No major issues were logged; use the detail pages as supporting context.", comment: "PDF doctor summary fallback talking point"))
        }
        return points
    }

    private static let shortDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("Md")
        return formatter
    }()
}

private extension String {
    var trimmedNilIfEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

private extension SymptomSeverity {
    var priority: Int {
        switch self {
        case .mild: return 1
        case .moderate: return 2
        case .severe: return 3
        }
    }
}
