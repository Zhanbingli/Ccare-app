import Foundation

enum AgentInsightSeverity: String, Codable {
    case information
    case caution
    case urgent
}

enum AgentInsightSource: String, Codable {
    case rule
    case localSummary
    case llmDraft
}

struct AgentInsight: Identifiable, Codable {
    var id: UUID = UUID()
    let title: String
    let detail: String
    let severity: AgentInsightSeverity
    let source: AgentInsightSource
}

struct AgentQuestion: Identifiable, Codable {
    var id: UUID = UUID()
    let prompt: String
    let reason: String?
}

struct RedFlagRuleResult: Identifiable, Codable {
    var id: UUID = UUID()
    let title: String
    let detail: String
    let severity: AgentInsightSeverity
    let triggeredAt: Date?
    let sourceRule: String
}

struct HypertensionFollowUpReport: Identifiable, Codable {
    struct BloodPressureSummary: Codable {
        let totalReadings: Int
        let averageSystolic: Double?
        let averageDiastolic: Double?
        let morningAverageSystolic: Double?
        let morningAverageDiastolic: Double?
        let eveningAverageSystolic: Double?
        let eveningAverageDiastolic: Double?
        let aboveTargetCount: Int
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

    struct RawBloodPressureRow: Identifiable, Codable {
        var id: UUID = UUID()
        let date: Date
        let systolic: Int
        let diastolic: Int?
        let note: String?
    }

    let id: UUID
    let generatedAt: Date
    let periodStart: Date
    let periodEnd: Date
    let visitTitle: String?
    let bloodPressure: BloodPressureSummary
    let adherence: AdherenceSummary
    let symptoms: SymptomSummary
    let redFlags: [RedFlagRuleResult]
    let patientInsights: [AgentInsight]
    let doctorSummaryLines: [String]
    let doctorQuestions: [AgentQuestion]
    let rawBloodPressureRows: [RawBloodPressureRow]
    let disclaimer: String
}

struct HypertensionFollowUpLLMContext: Codable {
    let report: HypertensionFollowUpReport
}

struct HypertensionFollowUpLLMDraft: Codable {
    let patientSummary: String?
    let doctorSummary: String?
    let questions: [String]
}

protocol HypertensionFollowUpReasoningClient {
    func draftFollowUpText(context: HypertensionFollowUpLLMContext) async throws -> HypertensionFollowUpLLMDraft
}

struct LocalOnlyHypertensionReasoningClient: HypertensionFollowUpReasoningClient {
    func draftFollowUpText(context: HypertensionFollowUpLLMContext) async throws -> HypertensionFollowUpLLMDraft {
        HypertensionFollowUpLLMDraft(patientSummary: nil, doctorSummary: nil, questions: [])
    }
}

enum HypertensionRuleEngine {
    static func evaluate(
        bloodPressureReadings: [Measurement],
        symptoms: [SymptomEntry],
        now: Date = Date()
    ) -> [RedFlagRuleResult] {
        var results: [RedFlagRuleResult] = []

        let crisisReadings = bloodPressureReadings.filter { reading in
            reading.value >= 180 || (reading.diastolic ?? 0) >= 120
        }
        if let latestCrisis = crisisReadings.sorted(by: { $0.date > $1.date }).first {
            let nearbySymptoms = symptoms.filter { abs($0.date.timeIntervalSince(latestCrisis.date)) <= 24 * 60 * 60 }
            let hasEmergencySymptom = nearbySymptoms.contains { containsEmergencySymptom($0) }
            results.append(
                RedFlagRuleResult(
                    title: hasEmergencySymptom
                        ? NSLocalizedString("Very high blood pressure with concerning symptoms", comment: "Hypertension red flag")
                        : NSLocalizedString("Very high blood pressure reading", comment: "Hypertension red flag"),
                    detail: hasEmergencySymptom
                        ? NSLocalizedString("A very high blood pressure reading was recorded near symptoms that can be urgent. Seek emergency medical help if these symptoms are present now.", comment: "Hypertension red flag detail")
                        : NSLocalizedString("A reading at or above 180 systolic or 120 diastolic should be rechecked and discussed with a clinician. Seek urgent help if symptoms such as chest pain, shortness of breath, weakness, confusion, vision change, or fainting occur.", comment: "Hypertension red flag detail"),
                    severity: hasEmergencySymptom ? .urgent : .caution,
                    triggeredAt: latestCrisis.date,
                    sourceRule: "bp_180_120"
                )
            )
        }

        if let symptom = symptoms.sorted(by: { $0.date > $1.date }).first(where: { containsStrokeLikeSymptom($0) }) {
            results.append(
                RedFlagRuleResult(
                    title: NSLocalizedString("Stroke-like symptom recorded", comment: "Hypertension red flag"),
                    detail: NSLocalizedString("Weakness on one side, trouble speaking, confusion, vision change, or fainting can be urgent. Seek emergency medical help if this is happening now.", comment: "Hypertension red flag detail"),
                    severity: .urgent,
                    triggeredAt: symptom.date,
                    sourceRule: "stroke_like_symptom"
                )
            )
        }

        return results
    }

    private static func containsEmergencySymptom(_ entry: SymptomEntry) -> Bool {
        containsAny(entry, keywords: [
            "chest pain", "chest tightness", "shortness of breath", "trouble breathing",
            "sweating", "fainting", "weakness", "confusion", "vision", "blurred vision",
            "slurred speech", "胸痛", "胸闷", "气短", "呼吸困难", "大汗", "冷汗",
            "晕厥", "昏厥", "无力", "意识", "视物", "模糊", "言语"
        ])
    }

    private static func containsStrokeLikeSymptom(_ entry: SymptomEntry) -> Bool {
        containsAny(entry, keywords: [
            "face droop", "facial droop", "one side", "arm weakness", "leg weakness",
            "slurred speech", "trouble speaking", "confusion", "vision loss", "fainting",
            "口角", "面瘫", "一侧", "偏瘫", "无力", "言语不清", "说话困难", "意识混乱",
            "视力下降", "晕厥", "昏厥"
        ])
    }

    private static func containsAny(_ entry: SymptomEntry, keywords: [String]) -> Bool {
        let text = (entry.tags + [entry.note ?? ""])
            .joined(separator: " ")
            .lowercased()
        return keywords.contains { text.contains($0.lowercased()) }
    }
}

enum HypertensionFollowUpReportBuilder {
    @MainActor
    static func build(
        store: DataStore,
        visit: DoctorVisit? = nil,
        days: Int = 30,
        now: Date = Date()
    ) -> HypertensionFollowUpReport {
        let calendar = Calendar.current
        let periodStart = calendar.date(byAdding: .day, value: -(days - 1), to: calendar.startOfDay(for: now)) ?? now
        let bpReadings = store.measurements
            .filter { $0.type == .bloodPressure && $0.date >= periodStart && $0.date <= now }
            .sorted { $0.date < $1.date }
        let symptoms = store.symptomEntries
            .filter { $0.date >= periodStart && $0.date <= now }
            .sorted { $0.date > $1.date }
        let antihypertensives = store.medications.filter { $0.category == .antihypertensive }
        let thresholds = store.bpThresholds()
        let bpSummary = bloodPressureSummary(
            readings: bpReadings,
            thresholds: thresholds,
            now: now,
            calendar: calendar
        )
        let adherenceSummary = adherenceSummary(
            medications: antihypertensives,
            logs: store.intakeLogs,
            days: days,
            now: now,
            calendar: calendar
        )
        let symptomSummary = HypertensionFollowUpReport.SymptomSummary(
            count: symptoms.count,
            severeCount: symptoms.filter { $0.severity == .severe }.count,
            summaries: symptoms.prefix(5).map { symptomLine($0) }
        )
        let redFlags = HypertensionRuleEngine.evaluate(
            bloodPressureReadings: bpReadings,
            symptoms: symptoms,
            now: now
        )
        let insights = patientInsights(
            bp: bpSummary,
            adherence: adherenceSummary,
            symptoms: symptomSummary,
            redFlags: redFlags
        )
        let questions = doctorQuestions(
            bp: bpSummary,
            adherence: adherenceSummary,
            symptoms: symptomSummary,
            redFlags: redFlags
        )
        let rows = bpReadings.suffix(20).reversed().map {
            HypertensionFollowUpReport.RawBloodPressureRow(
                date: $0.date,
                systolic: Int($0.value),
                diastolic: $0.diastolic.map(Int.init),
                note: $0.note
            )
        }

        return HypertensionFollowUpReport(
            id: UUID(),
            generatedAt: now,
            periodStart: periodStart,
            periodEnd: now,
            visitTitle: visit?.displayTitle,
            bloodPressure: bpSummary,
            adherence: adherenceSummary,
            symptoms: symptomSummary,
            redFlags: redFlags,
            patientInsights: insights,
            doctorSummaryLines: doctorSummaryLines(
                days: days,
                bp: bpSummary,
                adherence: adherenceSummary,
                symptoms: symptomSummary,
                redFlags: redFlags
            ),
            doctorQuestions: questions,
            rawBloodPressureRows: Array(rows),
            disclaimer: NSLocalizedString("This report organizes patient-entered health information for clinical follow-up. It does not diagnose, change medication, or replace professional medical care.", comment: "Hypertension report disclaimer")
        )
    }

    private static func bloodPressureSummary(
        readings: [Measurement],
        thresholds: (systolicHigh: Double, diastolicHigh: Double),
        now: Date,
        calendar: Calendar
    ) -> HypertensionFollowUpReport.BloodPressureSummary {
        let morning = readings.filter { (5..<12).contains(calendar.component(.hour, from: $0.date)) }
        let evening = readings.filter { (18..<24).contains(calendar.component(.hour, from: $0.date)) }
        let latest = readings.last
        let latestDay = latest.map { calendar.startOfDay(for: $0.date) }
        let nowDay = calendar.startOfDay(for: now)
        let gap = latestDay.flatMap { calendar.dateComponents([.day], from: $0, to: nowDay).day }

        return HypertensionFollowUpReport.BloodPressureSummary(
            totalReadings: readings.count,
            averageSystolic: average(readings.map(\.value)),
            averageDiastolic: average(readings.compactMap(\.diastolic)),
            morningAverageSystolic: average(morning.map(\.value)),
            morningAverageDiastolic: average(morning.compactMap(\.diastolic)),
            eveningAverageSystolic: average(evening.map(\.value)),
            eveningAverageDiastolic: average(evening.compactMap(\.diastolic)),
            aboveTargetCount: readings.filter { $0.value > thresholds.systolicHigh || ($0.diastolic ?? 0) > thresholds.diastolicHigh }.count,
            measurementGapDays: gap,
            latestReading: latest.map { formatBP($0) }
        )
    }

    private static func adherenceSummary(
        medications: [Medication],
        logs: [IntakeLog],
        days: Int,
        now: Date,
        calendar: Calendar
    ) -> HypertensionFollowUpReport.AdherenceSummary {
        let today = calendar.startOfDay(for: now)
        let start = calendar.date(byAdding: .day, value: -(days - 1), to: today) ?? today
        var taken = 0
        var total = 0
        var missedByTime: [String: Int] = [:]

        for offset in 0..<days {
            guard let day = calendar.date(byAdding: .day, value: offset, to: start) else { continue }
            let dayKey = calendar.startOfDay(for: day)
            let counts = AdherenceCalculator.dayCounts(dayKey: dayKey, medications: medications, logs: logs, now: now, calendar: calendar)
            taken += counts.taken
            total += counts.total

            for med in medications where med.isAsNeeded != true {
                let times = med.timesOfDay.compactMap { components -> (Int, Int)? in
                    guard let hour = components.hour, let minute = components.minute else { return nil }
                    return (hour, minute)
                }
                for (hour, minute) in times {
                    guard let scheduled = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: dayKey),
                          scheduled <= now,
                          med.isDoseActive(on: scheduled) else { continue }
                    let key = String(format: "%02d:%02d", hour, minute)
                    let status = AdherenceCalculator.latestStatus(
                        on: dayKey,
                        medID: med.id,
                        scheduleKey: key,
                        medTimesCount: times.count,
                        logs: logs,
                        calendar: calendar
                    )
                    if status != .taken {
                        missedByTime[key, default: 0] += 1
                    }
                }
            }
        }

        let missed = max(total - taken, 0)
        let worstTime = missedByTime.max(by: { $0.value < $1.value })?.key

        return HypertensionFollowUpReport.AdherenceSummary(
            medicationCount: medications.count,
            scheduledDoseCount: total,
            takenDoseCount: taken,
            missedDoseCount: missed,
            adherenceRate: total > 0 ? Double(taken) / Double(total) : nil,
            worstMissedTimeLabel: worstTime
        )
    }

    private static func patientInsights(
        bp: HypertensionFollowUpReport.BloodPressureSummary,
        adherence: HypertensionFollowUpReport.AdherenceSummary,
        symptoms: HypertensionFollowUpReport.SymptomSummary,
        redFlags: [RedFlagRuleResult]
    ) -> [AgentInsight] {
        var insights: [AgentInsight] = []

        if redFlags.contains(where: { $0.severity == .urgent }) {
            insights.append(AgentInsight(
                title: NSLocalizedString("Rule-based safety signal", comment: "Hypertension report insight"),
                detail: NSLocalizedString("One or more urgent symptoms or very high readings were recorded. If these are happening now, seek emergency medical help.", comment: "Hypertension report insight detail"),
                severity: .urgent,
                source: .rule
            ))
        }

        if let morning = bp.morningAverageSystolic,
           let evening = bp.eveningAverageSystolic,
           morning - evening >= 10 {
            insights.append(AgentInsight(
                title: NSLocalizedString("Morning blood pressure pattern", comment: "Hypertension report insight"),
                detail: NSLocalizedString("Morning readings were higher than evening readings. This pattern may be worth discussing with your doctor.", comment: "Hypertension report insight detail"),
                severity: .caution,
                source: .localSummary
            ))
        }

        if adherence.missedDoseCount >= 3 {
            let detail = adherence.worstMissedTimeLabel.map {
                String(format: NSLocalizedString("Missed doses clustered around %@. Ask your doctor how to handle missed doses; do not change medication on your own.", comment: "Hypertension report insight detail"), $0)
            } ?? NSLocalizedString("Several scheduled doses were not recorded as taken. This may be worth discussing during follow-up.", comment: "Hypertension report insight detail")
            insights.append(AgentInsight(
                title: NSLocalizedString("Medication adherence pattern", comment: "Hypertension report insight"),
                detail: detail,
                severity: .caution,
                source: .localSummary
            ))
        }

        if bp.totalReadings < 7 {
            insights.append(AgentInsight(
                title: NSLocalizedString("Limited home BP data", comment: "Hypertension report insight"),
                detail: NSLocalizedString("There are few blood pressure readings in this period, so trends may be unreliable.", comment: "Hypertension report insight detail"),
                severity: .information,
                source: .localSummary
            ))
        } else if bp.aboveTargetCount > 0 {
            insights.append(AgentInsight(
                title: NSLocalizedString("Above-target readings", comment: "Hypertension report insight"),
                detail: String(format: NSLocalizedString("%lld readings were above the configured target. This does not diagnose poor control, but it is useful follow-up context.", comment: "Hypertension report insight detail"), Int64(bp.aboveTargetCount)),
                severity: .caution,
                source: .localSummary
            ))
        }

        if symptoms.count > 0 {
            insights.append(AgentInsight(
                title: NSLocalizedString("Symptoms to mention", comment: "Hypertension report insight"),
                detail: String(format: NSLocalizedString("%lld symptom notes were recorded in this period.", comment: "Hypertension report insight detail"), Int64(symptoms.count)),
                severity: symptoms.severeCount > 0 ? .caution : .information,
                source: .localSummary
            ))
        }

        return insights
    }

    private static func doctorSummaryLines(
        days: Int,
        bp: HypertensionFollowUpReport.BloodPressureSummary,
        adherence: HypertensionFollowUpReport.AdherenceSummary,
        symptoms: HypertensionFollowUpReport.SymptomSummary,
        redFlags: [RedFlagRuleResult]
    ) -> [String] {
        [
            String(format: NSLocalizedString("Period reviewed: last %lld days", comment: "Hypertension report doctor summary"), Int64(days)),
            String(format: NSLocalizedString("Home BP readings: %lld", comment: "Hypertension report doctor summary"), Int64(bp.totalReadings)),
            String(format: NSLocalizedString("Average home BP: %@", comment: "Hypertension report doctor summary"), formatAverageBP(bp.averageSystolic, bp.averageDiastolic)),
            String(format: NSLocalizedString("Morning average: %@; evening average: %@", comment: "Hypertension report doctor summary"), formatAverageBP(bp.morningAverageSystolic, bp.morningAverageDiastolic), formatAverageBP(bp.eveningAverageSystolic, bp.eveningAverageDiastolic)),
            String(format: NSLocalizedString("Antihypertensive adherence: %@", comment: "Hypertension report doctor summary"), adherence.adherenceRate.map { "\(Int($0 * 100))%" } ?? NSLocalizedString("not enough scheduled data", comment: "Hypertension report missing value")),
            String(format: NSLocalizedString("Missed scheduled doses: %lld", comment: "Hypertension report doctor summary"), Int64(adherence.missedDoseCount)),
            String(format: NSLocalizedString("Symptoms logged: %lld", comment: "Hypertension report doctor summary"), Int64(symptoms.count)),
            String(format: NSLocalizedString("Rule-based red flags: %lld", comment: "Hypertension report doctor summary"), Int64(redFlags.count))
        ]
    }

    private static func doctorQuestions(
        bp: HypertensionFollowUpReport.BloodPressureSummary,
        adherence: HypertensionFollowUpReport.AdherenceSummary,
        symptoms: HypertensionFollowUpReport.SymptomSummary,
        redFlags: [RedFlagRuleResult]
    ) -> [AgentQuestion] {
        var questions: [AgentQuestion] = []

        if let morning = bp.morningAverageSystolic,
           let evening = bp.eveningAverageSystolic,
           morning - evening >= 10 {
            questions.append(AgentQuestion(
                prompt: NSLocalizedString("My morning readings are higher than evening readings. Should we review medication timing or monitoring targets?", comment: "Hypertension report doctor question"),
                reason: NSLocalizedString("Generated from home BP timing pattern; no dose change is suggested by the app.", comment: "Hypertension report question reason")
            ))
        }

        if adherence.missedDoseCount > 0 {
            questions.append(AgentQuestion(
                prompt: NSLocalizedString("What should I do if I miss a blood pressure medication dose?", comment: "Hypertension report doctor question"),
                reason: NSLocalizedString("Generated from missed-dose records.", comment: "Hypertension report question reason")
            ))
        }

        if symptoms.count > 0 {
            questions.append(AgentQuestion(
                prompt: NSLocalizedString("Which symptoms should make me contact you sooner before the next visit?", comment: "Hypertension report doctor question"),
                reason: NSLocalizedString("Generated from symptom logs.", comment: "Hypertension report question reason")
            ))
        }

        if redFlags.isEmpty && questions.isEmpty {
            questions.append(AgentQuestion(
                prompt: NSLocalizedString("What home blood pressure range should I use for follow-up tracking?", comment: "Hypertension report doctor question"),
                reason: NSLocalizedString("Default follow-up preparation question.", comment: "Hypertension report question reason")
            ))
        }

        return Array(questions.prefix(3))
    }

    private static func symptomLine(_ symptom: SymptomEntry) -> String {
        let tags = symptom.tags.joined(separator: ", ")
        if let note = symptom.note?.trimmingCharacters(in: .whitespacesAndNewlines), !note.isEmpty {
            return "\(symptom.severity.displayName): \(tags) - \(note)"
        }
        return "\(symptom.severity.displayName): \(tags)"
    }

    private static func average(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }

    static func formatAverageBP(_ systolic: Double?, _ diastolic: Double?) -> String {
        guard let systolic else { return NSLocalizedString("not enough data", comment: "Hypertension report missing value") }
        if let diastolic {
            return "\(Int(systolic.rounded()))/\(Int(diastolic.rounded())) mmHg"
        }
        return "\(Int(systolic.rounded())) mmHg"
    }

    static func formatBP(_ reading: Measurement) -> String {
        if let diastolic = reading.diastolic {
            return "\(Int(reading.value))/\(Int(diastolic)) mmHg"
        }
        return "\(Int(reading.value)) mmHg"
    }
}

enum HypertensionFollowUpReportTextExporter {
    static func plainText(_ report: HypertensionFollowUpReport, aiDraft: HypertensionFollowUpLLMDraft? = nil) -> String {
        var lines: [String] = []

        lines.append(NSLocalizedString("Hypertension follow-up report", comment: "Hypertension report heading"))
        lines.append(String(format: NSLocalizedString("Generated: %@", comment: "Hypertension report share generated"), dateTime(report.generatedAt)))
        lines.append(String(format: NSLocalizedString("Period: %@ to %@", comment: "Hypertension report share period"), date(report.periodStart), date(report.periodEnd)))
        if let visitTitle = report.visitTitle {
            lines.append(String(format: NSLocalizedString("Visit: %@", comment: "Hypertension report share visit"), visitTitle))
        }
        lines.append("")

        appendSection(NSLocalizedString("Rule-Based Safety Signals", comment: "Hypertension report section"), to: &lines)
        if report.redFlags.isEmpty {
            lines.append("- \(NSLocalizedString("No rule-based safety signal in this report period.", comment: "Hypertension report share empty safety"))")
        } else {
            for flag in report.redFlags {
                lines.append("- \(flag.title): \(flag.detail)")
            }
        }
        lines.append("")

        if let aiDraft {
            appendSection(NSLocalizedString("AI Draft", comment: "Hypertension report AI section"), to: &lines)
            if let patientSummary = aiDraft.patientSummary {
                lines.append("\(NSLocalizedString("Patient summary", comment: "Hypertension report AI draft label")): \(patientSummary)")
            }
            if let doctorSummary = aiDraft.doctorSummary {
                lines.append("\(NSLocalizedString("Doctor summary", comment: "Hypertension report AI draft label")): \(doctorSummary)")
            }
            if !aiDraft.questions.isEmpty {
                lines.append(NSLocalizedString("Questions", comment: "Hypertension report AI draft label"))
                for question in aiDraft.questions {
                    lines.append("- \(question)")
                }
            }
            lines.append("")
        }

        appendSection(NSLocalizedString("Doctor-Facing Summary", comment: "Hypertension report section"), to: &lines)
        for line in report.doctorSummaryLines {
            lines.append("- \(line)")
        }
        lines.append("")

        appendSection(NSLocalizedString("Patient Prep", comment: "Hypertension report section"), to: &lines)
        if report.patientInsights.isEmpty {
            lines.append("- \(NSLocalizedString("No strong pattern detected yet. Keep recording blood pressure, medication intake, and symptoms before the visit.", comment: "Hypertension report empty insights"))")
        } else {
            for insight in report.patientInsights {
                lines.append("- \(insight.title): \(insight.detail)")
            }
        }
        lines.append("")

        appendSection(NSLocalizedString("Questions for Doctor", comment: "Hypertension report section"), to: &lines)
        for question in report.doctorQuestions {
            lines.append("- \(question.prompt)")
        }
        lines.append("")

        appendSection(NSLocalizedString("Blood Pressure Appendix", comment: "Hypertension report section"), to: &lines)
        if report.rawBloodPressureRows.isEmpty {
            lines.append("- \(NSLocalizedString("No blood pressure readings in this report period.", comment: "Hypertension report empty raw data"))")
        } else {
            for row in report.rawBloodPressureRows {
                let value = row.diastolic.map { "\(row.systolic)/\($0) mmHg" } ?? "\(row.systolic) mmHg"
                let note = row.note?.trimmingCharacters(in: .whitespacesAndNewlines)
                let suffix = (note?.isEmpty == false) ? " - \(note!)" : ""
                lines.append("- \(dateTime(row.date)): \(value)\(suffix)")
            }
        }
        lines.append("")
        lines.append(report.disclaimer)

        return lines.joined(separator: "\n")
    }

    private static func appendSection(_ title: String, to lines: inout [String]) {
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
