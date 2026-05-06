import Foundation

struct DiabetesFollowUpReport: Identifiable, Codable {
    struct GlucoseSummary: Codable {
        let totalReadings: Int
        let averageGlucose: Double?
        let morningAverageGlucose: Double?
        let eveningAverageGlucose: Double?
        let lowReadingsCount: Int
        let veryLowReadingsCount: Int
        let highReadingsCount: Int
        let measurementGapDays: Int?
        let latestReading: String?
    }

    struct AdherenceSummary: Codable {
        let medicationCount: Int
        let scheduledDoseCount: Int
        let takenDoseCount: Int
        let missedDoseCount: Int
        let adherenceRate: Double?
        let worstMissedTimeLabel: String?
    }

    struct SymptomSummary: Codable {
        let count: Int
        let severeCount: Int
        let summaries: [String]
    }

    struct RawGlucoseRow: Identifiable, Codable {
        var id: UUID = UUID()
        let date: Date
        let glucose: Double
        let note: String?
    }

    let id: UUID
    let generatedAt: Date
    let periodStart: Date
    let periodEnd: Date
    let visitTitle: String?
    let glucose: GlucoseSummary
    let adherence: AdherenceSummary
    let symptoms: SymptomSummary
    let redFlags: [RedFlagRuleResult]
    let patientInsights: [AgentInsight]
    let doctorSummaryLines: [String]
    let doctorQuestions: [AgentQuestion]
    let rawGlucoseRows: [RawGlucoseRow]
    let disclaimer: String
}

enum DiabetesRuleEngine {
    static func evaluate(
        glucoseReadings: [Measurement],
        symptoms: [SymptomEntry],
        now: Date = Date()
    ) -> [RedFlagRuleResult] {
        var results: [RedFlagRuleResult] = []

        if let veryLow = glucoseReadings.sorted(by: { $0.date > $1.date }).first(where: { $0.value <= 54 }) {
            results.append(
                RedFlagRuleResult(
                    title: NSLocalizedString("Severely low glucose reading", comment: "Diabetes red flag"),
                    detail: NSLocalizedString("A glucose reading at or below 54 mg/dL was recorded. This can be dangerous. Follow your clinician's low-glucose plan and seek urgent help if confusion, fainting, seizure, or inability to self-treat is present.", comment: "Diabetes red flag detail"),
                    severity: .urgent,
                    triggeredAt: veryLow.date,
                    sourceRule: "glucose_very_low_54"
                )
            )
        } else if let low = glucoseReadings.sorted(by: { $0.date > $1.date }).first(where: { $0.value < 70 }) {
            let nearbySymptoms = symptoms.filter { abs($0.date.timeIntervalSince(low.date)) <= 24 * 60 * 60 }
            let severeSymptoms = nearbySymptoms.contains { containsSevereLowGlucoseSymptom($0) }
            results.append(
                RedFlagRuleResult(
                    title: severeSymptoms
                        ? NSLocalizedString("Low glucose with concerning symptoms", comment: "Diabetes red flag")
                        : NSLocalizedString("Low glucose reading", comment: "Diabetes red flag"),
                    detail: severeSymptoms
                        ? NSLocalizedString("A low glucose reading was recorded near symptoms such as confusion, fainting, seizure, or trouble walking. Seek urgent medical help if these symptoms are present now.", comment: "Diabetes red flag detail")
                        : NSLocalizedString("A glucose reading below 70 mg/dL was recorded. Use your clinician's low-glucose plan and discuss repeated lows at follow-up.", comment: "Diabetes red flag detail"),
                    severity: severeSymptoms ? .urgent : .caution,
                    triggeredAt: low.date,
                    sourceRule: "glucose_low_70"
                )
            )
        }

        if let high = glucoseReadings.sorted(by: { $0.date > $1.date }).first(where: { $0.value >= 240 }) {
            let nearbySymptoms = symptoms.filter { abs($0.date.timeIntervalSince(high.date)) <= 24 * 60 * 60 }
            let dkaLikeSymptoms = nearbySymptoms.contains { containsDKALikeSymptom($0) }
            results.append(
                RedFlagRuleResult(
                    title: dkaLikeSymptoms
                        ? NSLocalizedString("High glucose with concerning symptoms", comment: "Diabetes red flag")
                        : NSLocalizedString("High glucose reading", comment: "Diabetes red flag"),
                    detail: dkaLikeSymptoms
                        ? NSLocalizedString("A glucose reading at or above 240 mg/dL was recorded near symptoms that can be urgent. Seek urgent medical help if vomiting, abdominal pain, deep or fast breathing, confusion, or severe weakness is present now.", comment: "Diabetes red flag detail")
                        : NSLocalizedString("A glucose reading at or above 240 mg/dL was recorded. If you are sick, follow your clinician's sick-day plan and consider ketone testing if advised.", comment: "Diabetes red flag detail"),
                    severity: dkaLikeSymptoms ? .urgent : .caution,
                    triggeredAt: high.date,
                    sourceRule: "glucose_high_240"
                )
            )
        }

        return results
    }

    private static func containsSevereLowGlucoseSymptom(_ entry: SymptomEntry) -> Bool {
        containsAny(entry, keywords: [
            "confusion", "fainting", "seizure", "trouble walking", "trouble seeing",
            "weak", "weakness", "sweating", "shaking", "dizzy", "dizziness",
            "意识", "混乱", "昏厥", "晕厥", "抽搐", "癫痫", "走路困难", "视物不清",
            "无力", "出汗", "手抖", "发抖", "头晕"
        ])
    }

    private static func containsDKALikeSymptom(_ entry: SymptomEntry) -> Bool {
        containsAny(entry, keywords: [
            "vomiting", "throwing up", "nausea", "abdominal pain", "stomach pain",
            "deep breathing", "fast breathing", "shortness of breath", "confusion",
            "very tired", "severe weakness", "fruity breath",
            "呕吐", "恶心", "腹痛", "胃痛", "深大呼吸", "呼吸急促", "气短",
            "意识", "混乱", "极度乏力", "严重无力", "烂苹果味"
        ])
    }

    private static func containsAny(_ entry: SymptomEntry, keywords: [String]) -> Bool {
        let text = (entry.tags + [entry.note ?? ""])
            .joined(separator: " ")
            .lowercased()
        return keywords.contains { text.contains($0.lowercased()) }
    }
}

enum DiabetesFollowUpReportBuilder {
    @MainActor
    static func build(
        store: DataStore,
        visit: DoctorVisit? = nil,
        days: Int = 30,
        now: Date = Date()
    ) -> DiabetesFollowUpReport {
        let calendar = Calendar.current
        let periodStart = calendar.date(byAdding: .day, value: -(days - 1), to: calendar.startOfDay(for: now)) ?? now
        let glucoseReadings = store.measurements
            .filter { $0.type == .bloodGlucose && $0.date >= periodStart && $0.date <= now }
            .sorted { $0.date < $1.date }
        let symptoms = store.symptomEntries
            .filter { $0.date >= periodStart && $0.date <= now }
            .sorted { $0.date > $1.date }
        let antidiabetics = store.medications.filter { $0.category == .antidiabetic }
        let glucoseSummary = glucoseSummary(readings: glucoseReadings, now: now, calendar: calendar)
        let adherenceSummary = adherenceSummary(
            medications: antidiabetics,
            logs: store.intakeLogs,
            days: days,
            now: now,
            calendar: calendar
        )
        let symptomSummary = DiabetesFollowUpReport.SymptomSummary(
            count: symptoms.count,
            severeCount: symptoms.filter { $0.severity == .severe }.count,
            summaries: symptoms.prefix(5).map { symptomLine($0) }
        )
        let redFlags = DiabetesRuleEngine.evaluate(
            glucoseReadings: glucoseReadings,
            symptoms: symptoms,
            now: now
        )
        let insights = patientInsights(
            glucose: glucoseSummary,
            adherence: adherenceSummary,
            symptoms: symptomSummary
        )
        let questions = doctorQuestions(
            glucose: glucoseSummary,
            adherence: adherenceSummary,
            symptoms: symptomSummary,
            redFlags: redFlags
        )
        let rows = glucoseReadings.suffix(20).reversed().map {
            DiabetesFollowUpReport.RawGlucoseRow(date: $0.date, glucose: $0.value, note: $0.note)
        }

        return DiabetesFollowUpReport(
            id: UUID(),
            generatedAt: now,
            periodStart: periodStart,
            periodEnd: now,
            visitTitle: visit?.displayTitle,
            glucose: glucoseSummary,
            adherence: adherenceSummary,
            symptoms: symptomSummary,
            redFlags: redFlags,
            patientInsights: insights,
            doctorSummaryLines: doctorSummaryLines(
                days: days,
                glucose: glucoseSummary,
                adherence: adherenceSummary,
                symptoms: symptomSummary,
                redFlags: redFlags
            ),
            doctorQuestions: questions,
            rawGlucoseRows: rows,
            disclaimer: NSLocalizedString("This report organizes patient-entered diabetes information for clinical follow-up. It does not diagnose, change medication, or replace professional medical care.", comment: "Diabetes report disclaimer")
        )
    }

    private static func glucoseSummary(
        readings: [Measurement],
        now: Date,
        calendar: Calendar
    ) -> DiabetesFollowUpReport.GlucoseSummary {
        let values = readings.map(\.value)
        let morning = readings.filter { (5..<12).contains(calendar.component(.hour, from: $0.date)) }.map(\.value)
        let evening = readings.filter {
            let hour = calendar.component(.hour, from: $0.date)
            return hour >= 18 || hour < 5
        }.map(\.value)
        let lastDate = readings.map(\.date).max()
        let gap = lastDate.map { calendar.dateComponents([.day], from: calendar.startOfDay(for: $0), to: calendar.startOfDay(for: now)).day ?? 0 }
        let latest = readings.last.map { formattedGlucose($0.value) }

        return DiabetesFollowUpReport.GlucoseSummary(
            totalReadings: readings.count,
            averageGlucose: average(values),
            morningAverageGlucose: average(morning),
            eveningAverageGlucose: average(evening),
            lowReadingsCount: readings.filter { $0.value < 70 }.count,
            veryLowReadingsCount: readings.filter { $0.value <= 54 }.count,
            highReadingsCount: readings.filter { $0.value >= 240 }.count,
            measurementGapDays: gap,
            latestReading: latest
        )
    }

    private static func adherenceSummary(
        medications: [Medication],
        logs: [IntakeLog],
        days: Int,
        now: Date,
        calendar: Calendar
    ) -> DiabetesFollowUpReport.AdherenceSummary {
        let start = calendar.date(byAdding: .day, value: -(days - 1), to: calendar.startOfDay(for: now)) ?? now
        var total = 0
        var taken = 0
        var missedByTime: [String: Int] = [:]

        for medication in medications where medication.isAsNeeded != true {
            var day = calendar.startOfDay(for: start)
            let end = calendar.startOfDay(for: now)
            while day <= end {
                for comps in medication.timesOfDay {
                    guard let hour = comps.hour,
                          let minute = comps.minute,
                          let scheduled = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day),
                          scheduled <= now,
                          medication.isDoseActive(on: scheduled, calendar: calendar) else { continue }
                    total += 1
                    let key = String(format: "%02d:%02d", hour, minute)
                    let dayEnd = calendar.date(byAdding: .day, value: 1, to: day) ?? day.addingTimeInterval(24 * 60 * 60)
                    let latest = logs
                        .filter {
                            $0.medicationID == medication.id &&
                            $0.date >= day &&
                            $0.date < dayEnd &&
                            ($0.scheduleKey == key || (medication.timesOfDay.count == 1 && $0.scheduleKey == nil))
                        }
                        .sorted { $0.effectiveRecordedAt > $1.effectiveRecordedAt }
                        .first
                    if latest?.status == .taken {
                        taken += 1
                    } else if latest?.status != .skipped {
                        missedByTime[key, default: 0] += 1
                    }
                }
                day = calendar.date(byAdding: .day, value: 1, to: day) ?? day.addingTimeInterval(24 * 60 * 60)
            }
        }

        let missed = max(total - taken, 0)
        let worstTime = missedByTime.max(by: { $0.value < $1.value })?.key
        return DiabetesFollowUpReport.AdherenceSummary(
            medicationCount: medications.count,
            scheduledDoseCount: total,
            takenDoseCount: taken,
            missedDoseCount: missed,
            adherenceRate: total > 0 ? Double(taken) / Double(total) : nil,
            worstMissedTimeLabel: worstTime
        )
    }

    private static func patientInsights(
        glucose: DiabetesFollowUpReport.GlucoseSummary,
        adherence: DiabetesFollowUpReport.AdherenceSummary,
        symptoms: DiabetesFollowUpReport.SymptomSummary
    ) -> [AgentInsight] {
        var insights: [AgentInsight] = []

        if glucose.lowReadingsCount > 0 {
            insights.append(
                AgentInsight(
                    title: NSLocalizedString("Low glucose pattern", comment: "Diabetes report insight"),
                    detail: String(format: NSLocalizedString("%lld readings were below 70 mg/dL. Repeated lows are important to discuss with your clinician.", comment: "Diabetes report insight detail"), Int64(glucose.lowReadingsCount)),
                    severity: glucose.veryLowReadingsCount > 0 ? .urgent : .caution,
                    source: .localSummary
                )
            )
        }

        if glucose.highReadingsCount > 0 {
            insights.append(
                AgentInsight(
                    title: NSLocalizedString("High glucose pattern", comment: "Diabetes report insight"),
                    detail: String(format: NSLocalizedString("%lld readings were at or above 240 mg/dL. This may be worth discussing with your clinician, especially if you were sick.", comment: "Diabetes report insight detail"), Int64(glucose.highReadingsCount)),
                    severity: .caution,
                    source: .localSummary
                )
            )
        }

        if adherence.missedDoseCount >= 3 {
            let detail = adherence.worstMissedTimeLabel.map {
                String(format: NSLocalizedString("Missed doses clustered around %@. Ask your clinician how to handle missed diabetes medication; do not change medication on your own.", comment: "Diabetes report insight detail"), $0)
            } ?? NSLocalizedString("Several scheduled diabetes medication doses were not recorded as taken. This may be worth discussing during follow-up.", comment: "Diabetes report insight detail")
            insights.append(
                AgentInsight(
                    title: NSLocalizedString("Medication adherence pattern", comment: "Diabetes report insight"),
                    detail: detail,
                    severity: .caution,
                    source: .localSummary
                )
            )
        }

        if symptoms.severeCount > 0 {
            insights.append(
                AgentInsight(
                    title: NSLocalizedString("Severe symptoms recorded", comment: "Diabetes report insight"),
                    detail: NSLocalizedString("Severe symptom entries should be reviewed during follow-up. Seek urgent help if severe symptoms are happening now.", comment: "Diabetes report insight detail"),
                    severity: .caution,
                    source: .localSummary
                )
            )
        }

        if let gap = glucose.measurementGapDays, gap >= 7 {
            insights.append(
                AgentInsight(
                    title: NSLocalizedString("Measurement gap", comment: "Diabetes report insight"),
                    detail: String(format: NSLocalizedString("No glucose reading was recorded for %lld days. Ask your clinician what monitoring frequency is appropriate for you.", comment: "Diabetes report insight detail"), Int64(gap)),
                    severity: .information,
                    source: .localSummary
                )
            )
        }

        return insights
    }

    private static func doctorSummaryLines(
        days: Int,
        glucose: DiabetesFollowUpReport.GlucoseSummary,
        adherence: DiabetesFollowUpReport.AdherenceSummary,
        symptoms: DiabetesFollowUpReport.SymptomSummary,
        redFlags: [RedFlagRuleResult]
    ) -> [String] {
        [
            String(format: NSLocalizedString("Period reviewed: last %lld days", comment: "Diabetes report doctor summary"), Int64(days)),
            String(format: NSLocalizedString("Home glucose readings: %lld", comment: "Diabetes report doctor summary"), Int64(glucose.totalReadings)),
            String(format: NSLocalizedString("Average glucose: %@", comment: "Diabetes report doctor summary"), glucose.averageGlucose.map { formattedGlucose($0) } ?? NSLocalizedString("not enough data", comment: "Diabetes report missing value")),
            String(format: NSLocalizedString("Low / high glucose readings: %lld below 70, %lld at or above 240", comment: "Diabetes report doctor summary"), Int64(glucose.lowReadingsCount), Int64(glucose.highReadingsCount)),
            String(format: NSLocalizedString("Antidiabetic adherence: %@", comment: "Diabetes report doctor summary"), adherence.adherenceRate.map { "\(Int($0 * 100))%" } ?? NSLocalizedString("not enough scheduled data", comment: "Diabetes report missing value")),
            String(format: NSLocalizedString("Symptoms recorded: %lld total, %lld severe", comment: "Diabetes report doctor summary"), Int64(symptoms.count), Int64(symptoms.severeCount)),
            String(format: NSLocalizedString("Rule-based safety signals: %lld", comment: "Diabetes report doctor summary"), Int64(redFlags.count))
        ]
    }

    private static func doctorQuestions(
        glucose: DiabetesFollowUpReport.GlucoseSummary,
        adherence: DiabetesFollowUpReport.AdherenceSummary,
        symptoms: DiabetesFollowUpReport.SymptomSummary,
        redFlags: [RedFlagRuleResult]
    ) -> [AgentQuestion] {
        var questions: [AgentQuestion] = []
        if glucose.lowReadingsCount > 0 {
            questions.append(AgentQuestion(
                prompt: NSLocalizedString("What should I do when my glucose is below 70 mg/dL?", comment: "Diabetes report doctor question"),
                reason: NSLocalizedString("Generated from low-glucose records.", comment: "Diabetes report question reason")
            ))
        }
        if glucose.highReadingsCount > 0 {
            questions.append(AgentQuestion(
                prompt: NSLocalizedString("When should I check ketones or contact the clinic for high glucose?", comment: "Diabetes report doctor question"),
                reason: NSLocalizedString("Generated from high-glucose records.", comment: "Diabetes report question reason")
            ))
        }
        if adherence.missedDoseCount > 0 {
            questions.append(AgentQuestion(
                prompt: NSLocalizedString("How should I handle missed diabetes medication doses?", comment: "Diabetes report doctor question"),
                reason: NSLocalizedString("Generated from missed-dose records.", comment: "Diabetes report question reason")
            ))
        }
        if symptoms.count > 0 || !redFlags.isEmpty {
            questions.append(AgentQuestion(
                prompt: NSLocalizedString("Which symptoms should make me seek urgent care?", comment: "Diabetes report doctor question"),
                reason: NSLocalizedString("Generated from symptom or safety-signal records.", comment: "Diabetes report question reason")
            ))
        }
        questions.append(AgentQuestion(
            prompt: NSLocalizedString("What glucose target range should I use for home follow-up tracking?", comment: "Diabetes report doctor question"),
            reason: NSLocalizedString("Default follow-up preparation question.", comment: "Diabetes report question reason")
        ))
        return Array(questions.prefix(4))
    }

    private static func symptomLine(_ symptom: SymptomEntry) -> String {
        let tags = symptom.tags.isEmpty ? NSLocalizedString("No symptom tag", comment: "Diabetes report symptom fallback") : symptom.tags.joined(separator: ", ")
        return "\(symptom.date.formatted(date: .abbreviated, time: .shortened)): \(tags) (\(symptom.severity.displayName))"
    }

    private static func average(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }

    static func formattedGlucose(_ value: Double) -> String {
        let preferred = UnitPreferences.mgdlToPreferred(value)
        let formatted = UnitPreferences.glucoseUnit == .mgdL
            ? String(format: "%.0f", preferred)
            : String(format: "%.1f", preferred)
        return "\(formatted) \(UnitPreferences.glucoseUnit.rawValue)"
    }
}

enum DiabetesFollowUpReportTextExporter {
    static func plainText(_ report: DiabetesFollowUpReport) -> String {
        var lines: [String] = []
        lines.append(NSLocalizedString("Diabetes follow-up report", comment: "Diabetes report heading"))
        lines.append(String(format: NSLocalizedString("Generated: %@", comment: "Diabetes report share generated"), dateTime(report.generatedAt)))
        lines.append(String(format: NSLocalizedString("Period: %@ to %@", comment: "Diabetes report share period"), date(report.periodStart), date(report.periodEnd)))
        if let visitTitle = report.visitTitle {
            lines.append(String(format: NSLocalizedString("Visit: %@", comment: "Diabetes report share visit"), visitTitle))
        }
        lines.append("")

        appendSection(NSLocalizedString("Rule-Based Safety Signals", comment: "Diabetes report section"), to: &lines)
        if report.redFlags.isEmpty {
            lines.append("- \(NSLocalizedString("No rule-based diabetes safety signal in this report period.", comment: "Diabetes report share empty safety"))")
        } else {
            for flag in report.redFlags {
                lines.append("- \(flag.title): \(flag.detail)")
            }
        }

        appendSection(NSLocalizedString("Doctor-Facing Summary", comment: "Diabetes report section"), to: &lines)
        report.doctorSummaryLines.forEach { lines.append("- \($0)") }

        appendSection(NSLocalizedString("Patient Prep", comment: "Diabetes report section"), to: &lines)
        if report.patientInsights.isEmpty {
            lines.append("- \(NSLocalizedString("No strong pattern detected yet. Keep recording glucose, diabetes medication intake, and symptoms before the visit.", comment: "Diabetes report empty insights"))")
        } else {
            report.patientInsights.forEach { lines.append("- \($0.title): \($0.detail)") }
        }

        appendSection(NSLocalizedString("Questions for Doctor", comment: "Diabetes report section"), to: &lines)
        report.doctorQuestions.forEach { lines.append("- \($0.prompt)") }

        appendSection(NSLocalizedString("Glucose Appendix", comment: "Diabetes report section"), to: &lines)
        if report.rawGlucoseRows.isEmpty {
            lines.append("- \(NSLocalizedString("No glucose readings in this report period.", comment: "Diabetes report empty raw data"))")
        } else {
            for row in report.rawGlucoseRows {
                let note = row.note?.trimmingCharacters(in: .whitespacesAndNewlines)
                let suffix = note.flatMap { $0.isEmpty ? nil : " - \($0)" } ?? ""
                lines.append("- \(dateTime(row.date)): \(DiabetesFollowUpReportBuilder.formattedGlucose(row.glucose))\(suffix)")
            }
        }

        lines.append("")
        lines.append(report.disclaimer)
        return lines.joined(separator: "\n")
    }

    private static func appendSection(_ title: String, to lines: inout [String]) {
        lines.append("")
        lines.append(title.uppercased())
    }

    private static func date(_ value: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: value)
    }

    private static func dateTime(_ value: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: value)
    }
}
