import Foundation

enum FollowUpAgentTaskCategory: String, Codable {
    case safety
    case missingData
    case adherence
    case clarification
    case report
    case caregiver
}

enum FollowUpAgentTaskAction: String, Codable {
    case none
    case logBloodPressure
    case logBloodGlucose
    case openHypertensionReport
    case openDiabetesReport
    case openVisitPrep
    case openCaregivers
    case openMedications
    case clarifySymptom
}

enum FollowUpAgentTaskStatus: String, Codable {
    case open
    case dismissed
}

struct FollowUpAgentTask: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    let stableKey: String
    let title: String
    let detail: String
    let category: FollowUpAgentTaskCategory
    let severity: AgentInsightSeverity
    let source: AgentInsightSource
    let action: FollowUpAgentTaskAction
    let relatedID: UUID?
    let generatedAt: Date
    let updatedAt: Date
    var status: FollowUpAgentTaskStatus = .open

    var isOpen: Bool { status == .open }
}

enum FollowUpAgentTaskGenerator {
    @MainActor
    static func generate(store: DataStore, now: Date = Date()) -> [FollowUpAgentTask] {
        let calendar = Calendar.current
        let periodStart = calendar.date(byAdding: .day, value: -29, to: calendar.startOfDay(for: now)) ?? now
        let recentMeasurements = store.measurements.filter { $0.date >= periodStart && $0.date <= now }
        let recentSymptoms = store.symptomEntries.filter { $0.date >= periodStart && $0.date <= now }
        let bpReadings = recentMeasurements.filter { $0.type == .bloodPressure }
        let glucoseReadings = recentMeasurements.filter { $0.type == .bloodGlucose }
        let hasHypertensionContext = store.medications.contains { $0.category == .antihypertensive } || store.measurements.contains { $0.type == .bloodPressure }
        let hasDiabetesContext = store.medications.contains { $0.category == .antidiabetic } || store.measurements.contains { $0.type == .bloodGlucose }

        var items: [FollowUpAgentTask] = []
        items.append(contentsOf: hypertensionSafetyItems(bpReadings: bpReadings, symptoms: recentSymptoms, now: now))
        items.append(contentsOf: diabetesSafetyItems(glucoseReadings: glucoseReadings, symptoms: recentSymptoms, now: now))

        if hasHypertensionContext {
            if let item = measurementGapItem(
                key: "measurement_gap.bp",
                type: .bloodPressure,
                latest: store.measurements.filter { $0.type == .bloodPressure }.map(\.date).max(),
                thresholdDays: 7,
                now: now,
                title: NSLocalizedString("Blood pressure record is stale", comment: "Follow-up agent item title"),
                noDataDetail: NSLocalizedString("No home blood pressure has been recorded yet. Add a reading so the follow-up report has useful context.", comment: "Follow-up agent item detail"),
                gapDetail: NSLocalizedString("No home blood pressure has been recorded for %lld days. Add a reading before the next follow-up report.", comment: "Follow-up agent item detail"),
                action: .logBloodPressure
            ) {
                items.append(item)
            }
        }

        if hasDiabetesContext {
            if let item = measurementGapItem(
                key: "measurement_gap.glucose",
                type: .bloodGlucose,
                latest: store.measurements.filter { $0.type == .bloodGlucose }.map(\.date).max(),
                thresholdDays: 7,
                now: now,
                title: NSLocalizedString("Glucose record is stale", comment: "Follow-up agent item title"),
                noDataDetail: NSLocalizedString("No home glucose has been recorded yet. Add a reading so the follow-up report has useful context.", comment: "Follow-up agent item detail"),
                gapDetail: NSLocalizedString("No home glucose has been recorded for %lld days. Add a reading before the next follow-up report.", comment: "Follow-up agent item detail"),
                action: .logBloodGlucose
            ) {
                items.append(item)
            }
        }

        items.append(contentsOf: adherenceItems(store: store, now: now))
        items.append(contentsOf: symptomClarificationItems(
            symptoms: store.symptomEntries,
            clarifications: store.symptomClarifications,
            now: now,
            calendar: calendar
        ))
        items.append(contentsOf: reportPreparationItems(store: store, hasHypertensionContext: hasHypertensionContext, hasDiabetesContext: hasDiabetesContext, now: now, calendar: calendar))

        return deduplicated(items).sorted(by: sort)
    }

    static func merge(generated: [FollowUpAgentTask], existing: [FollowUpAgentTask], now: Date = Date()) -> [FollowUpAgentTask] {
        let existingByKey = Dictionary(uniqueKeysWithValues: existing.map { ($0.stableKey, $0) })
        return generated.map { item in
            guard let previous = existingByKey[item.stableKey] else { return item }
            return FollowUpAgentTask(
                id: previous.id,
                stableKey: item.stableKey,
                title: item.title,
                detail: item.detail,
                category: item.category,
                severity: item.severity,
                source: item.source,
                action: item.action,
                relatedID: item.relatedID,
                generatedAt: previous.generatedAt,
                updatedAt: now,
                status: previous.status
            )
        }
    }

    private static func hypertensionSafetyItems(bpReadings: [Measurement], symptoms: [SymptomEntry], now: Date) -> [FollowUpAgentTask] {
        HypertensionRuleEngine.evaluate(bloodPressureReadings: bpReadings, symptoms: symptoms, now: now).map { flag in
            FollowUpAgentTask(
                stableKey: "safety.hypertension.\(flag.sourceRule).\(dayKey(flag.triggeredAt ?? now))",
                title: flag.title,
                detail: flag.detail,
                category: .safety,
                severity: flag.severity,
                source: .rule,
                action: .openHypertensionReport,
                relatedID: nil,
                generatedAt: now,
                updatedAt: now
            )
        }
    }

    private static func diabetesSafetyItems(glucoseReadings: [Measurement], symptoms: [SymptomEntry], now: Date) -> [FollowUpAgentTask] {
        DiabetesRuleEngine.evaluate(glucoseReadings: glucoseReadings, symptoms: symptoms, now: now).map { flag in
            FollowUpAgentTask(
                stableKey: "safety.diabetes.\(flag.sourceRule).\(dayKey(flag.triggeredAt ?? now))",
                title: flag.title,
                detail: flag.detail,
                category: .safety,
                severity: flag.severity,
                source: .rule,
                action: .openDiabetesReport,
                relatedID: nil,
                generatedAt: now,
                updatedAt: now
            )
        }
    }

    private static func measurementGapItem(
        key: String,
        type: MeasurementType,
        latest: Date?,
        thresholdDays: Int,
        now: Date,
        title: String,
        noDataDetail: String,
        gapDetail: String,
        action: FollowUpAgentTaskAction
    ) -> FollowUpAgentTask? {
        let calendar = Calendar.current
        let gapDays: Int
        let detail: String
        if let latest {
            gapDays = calendar.dateComponents([.day], from: calendar.startOfDay(for: latest), to: calendar.startOfDay(for: now)).day ?? 0
            guard gapDays >= thresholdDays else { return nil }
            detail = String(format: gapDetail, Int64(gapDays))
        } else {
            gapDays = thresholdDays
            detail = noDataDetail
        }
        return FollowUpAgentTask(
            stableKey: key,
            title: title,
            detail: detail,
            category: .missingData,
            severity: gapDays >= 14 ? .caution : .information,
            source: .localSummary,
            action: action,
            relatedID: nil,
            generatedAt: now,
            updatedAt: now
        )
    }

    @MainActor
    private static func adherenceItems(store: DataStore, now: Date) -> [FollowUpAgentTask] {
        store.medications.compactMap { medication in
            let missedDays = store.consecutiveMissedDays(for: medication.id)
            guard missedDays >= 2 else { return nil }
            let hasCaregiverSupport = store.caregivers.contains(where: \.notifyOnMiss)
            return FollowUpAgentTask(
                stableKey: "adherence.missed.\(medication.id.uuidString)",
                title: NSLocalizedString("Repeated missed doses", comment: "Follow-up agent item title"),
                detail: String(format: NSLocalizedString("%@ has been missed for %lld days. Prepare a status update or review the medication routine.", comment: "Follow-up agent item detail"), medication.name, Int64(missedDays)),
                category: hasCaregiverSupport ? .caregiver : .adherence,
                severity: missedDays >= 3 ? .caution : .information,
                source: .localSummary,
                action: hasCaregiverSupport ? .openCaregivers : .openMedications,
                relatedID: medication.id,
                generatedAt: now,
                updatedAt: now
            )
        }
    }

    private static func symptomClarificationItems(
        symptoms: [SymptomEntry],
        clarifications: [SymptomClarification],
        now: Date,
        calendar: Calendar
    ) -> [FollowUpAgentTask] {
        let start = calendar.date(byAdding: .day, value: -6, to: calendar.startOfDay(for: now)) ?? now
        let clarifiedIDs = Set(clarifications.filter(\.hasUsefulContext).map(\.symptomEntryID))
        return symptoms
            .filter { $0.date >= start }
            .filter { !clarifiedIDs.contains($0.id) }
            .filter { symptomNeedsClarification($0) }
            .prefix(3)
            .map { symptom in
                let label = symptom.tags.first ?? NSLocalizedString("Symptom", comment: "Follow-up agent symptom fallback")
                return FollowUpAgentTask(
                    stableKey: "clarification.symptom.\(symptom.id.uuidString)",
                    title: NSLocalizedString("Clarify symptom context", comment: "Follow-up agent item title"),
                    detail: String(format: NSLocalizedString("Add timing, relation to medication, nearby measurement, or red-flag symptoms for %@.", comment: "Follow-up agent item detail"), label),
                    category: .clarification,
                    severity: symptom.severity == .severe ? .caution : .information,
                    source: .localSummary,
                    action: .clarifySymptom,
                    relatedID: symptom.id,
                    generatedAt: now,
                    updatedAt: now
                )
            }
    }

    @MainActor
    private static func reportPreparationItems(
        store: DataStore,
        hasHypertensionContext: Bool,
        hasDiabetesContext: Bool,
        now: Date,
        calendar: Calendar
    ) -> [FollowUpAgentTask] {
        guard let visit = store.nextDoctorVisit,
              let daysUntil = visit.daysUntil(now: now, calendar: calendar),
              daysUntil <= 14 else {
            return []
        }
        var items: [FollowUpAgentTask] = []
        if hasHypertensionContext {
            items.append(FollowUpAgentTask(
                stableKey: "report.hypertension.\(visit.id.uuidString)",
                title: NSLocalizedString("Hypertension follow-up report is ready", comment: "Follow-up agent item title"),
                detail: reportDetail(visit: visit, daysUntil: daysUntil),
                category: .report,
                severity: daysUntil <= 3 ? .caution : .information,
                source: .localSummary,
                action: .openHypertensionReport,
                relatedID: visit.id,
                generatedAt: now,
                updatedAt: now
            ))
        }
        if hasDiabetesContext {
            items.append(FollowUpAgentTask(
                stableKey: "report.diabetes.\(visit.id.uuidString)",
                title: NSLocalizedString("Diabetes follow-up report is ready", comment: "Follow-up agent item title"),
                detail: reportDetail(visit: visit, daysUntil: daysUntil),
                category: .report,
                severity: daysUntil <= 3 ? .caution : .information,
                source: .localSummary,
                action: .openDiabetesReport,
                relatedID: visit.id,
                generatedAt: now,
                updatedAt: now
            ))
        }
        return items
    }

    private static func reportDetail(visit: DoctorVisit, daysUntil: Int) -> String {
        if daysUntil < 0 {
            return String(format: NSLocalizedString("%@ is overdue. Review the report before updating the visit plan.", comment: "Follow-up agent item detail"), visit.displayTitle)
        }
        if daysUntil == 0 {
            return String(format: NSLocalizedString("%@ is today. Review patient questions and doctor-facing summary.", comment: "Follow-up agent item detail"), visit.displayTitle)
        }
        return String(format: NSLocalizedString("%@ is in %lld days. Review the report while there is still time to fill gaps.", comment: "Follow-up agent item detail"), visit.displayTitle, Int64(daysUntil))
    }

    private static func symptomNeedsClarification(_ symptom: SymptomEntry) -> Bool {
        if isBenignQuickFeeling(symptom) { return false }
        if symptom.severity == .severe { return true }

        let note = symptom.note?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return note.count < 12 || symptom.tags.count <= 1
    }

    private static func isBenignQuickFeeling(_ symptom: SymptomEntry) -> Bool {
        let note = symptom.note?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard note.isEmpty,
              symptom.severity == .mild,
              symptom.relatedMedicationIDs?.isEmpty != false,
              !symptom.tags.isEmpty else {
            return false
        }

        let benignTags: Set<String> = [
            "felt good",
            "felt okay",
            "今天感觉好",
            "今天感觉一般"
        ]
        return symptom.tags
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .allSatisfy { benignTags.contains($0) }
    }

    private static func deduplicated(_ items: [FollowUpAgentTask]) -> [FollowUpAgentTask] {
        var seen = Set<String>()
        return items.filter { item in
            if seen.contains(item.stableKey) { return false }
            seen.insert(item.stableKey)
            return true
        }
    }

    private static func sort(_ lhs: FollowUpAgentTask, _ rhs: FollowUpAgentTask) -> Bool {
        if severityRank(lhs.severity) != severityRank(rhs.severity) {
            return severityRank(lhs.severity) > severityRank(rhs.severity)
        }
        if categoryRank(lhs.category) != categoryRank(rhs.category) {
            return categoryRank(lhs.category) > categoryRank(rhs.category)
        }
        return lhs.updatedAt > rhs.updatedAt
    }

    private static func severityRank(_ severity: AgentInsightSeverity) -> Int {
        switch severity {
        case .urgent: return 3
        case .caution: return 2
        case .information: return 1
        }
    }

    private static func categoryRank(_ category: FollowUpAgentTaskCategory) -> Int {
        switch category {
        case .safety: return 6
        case .report: return 5
        case .caregiver: return 4
        case .adherence: return 3
        case .clarification: return 2
        case .missingData: return 1
        }
    }

    private static func dayKey(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
}
