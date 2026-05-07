import Foundation

enum FollowUpAgentStage: Equatable {
    case quietAccumulation
    case lightPrep(visitID: UUID, daysUntil: Int)
    case activePrep(visitID: UUID, daysUntil: Int)
    case visitDay(visitID: UUID)
    case postVisitCapture(visitID: UUID)

    var visitID: UUID? {
        switch self {
        case .quietAccumulation:
            return nil
        case .lightPrep(let visitID, _),
             .activePrep(let visitID, _),
             .visitDay(let visitID),
             .postVisitCapture(let visitID):
            return visitID
        }
    }
}

enum FollowUpAgentActionTarget: Equatable {
    case logMeasurement(MeasurementType)
    case clarifySymptom(UUID)
    case openHypertensionReport(UUID?)
    case openDiabetesReport(UUID?)
    case openVisitPrep(UUID?)
    case openDoctorSnapshot(UUID?)
    case recordPostVisit(UUID)
    case openMedications
    case openProfile
}

struct FollowUpAgentNextAction: Identifiable, Equatable {
    let stableKey: String
    let eyebrow: String
    let title: String
    let detail: String
    let buttonTitle: String
    let systemImage: String
    let severity: AgentInsightSeverity
    let target: FollowUpAgentActionTarget

    var id: String { stableKey }
}

enum FollowUpReportDomain: Equatable {
    case hypertension
    case diabetes

    var measurementType: MeasurementType {
        switch self {
        case .hypertension:
            return .bloodPressure
        case .diabetes:
            return .bloodGlucose
        }
    }

    var measurementGapTitle: String {
        switch self {
        case .hypertension:
            return NSLocalizedString("Add more blood pressure readings", comment: "Follow-up report readiness missing item")
        case .diabetes:
            return NSLocalizedString("Add more glucose readings", comment: "Follow-up report readiness missing item")
        }
    }
}

struct FollowUpReportReadiness: Equatable {
    struct MissingItem: Equatable {
        let title: String
        let target: FollowUpAgentActionTarget
    }

    let domain: FollowUpReportDomain
    let readyCount: Int
    let totalCount: Int
    let missingItems: [MissingItem]

    var isReady: Bool {
        readyCount >= totalCount && missingItems.isEmpty
    }

    var scoreText: String {
        String(format: NSLocalizedString("%lld / %lld doctor-ready", comment: "Follow-up report readiness score"), Int64(readyCount), Int64(totalCount))
    }

    var summaryText: String {
        if missingItems.isEmpty {
            return NSLocalizedString("Ready: medication list, measurement trend, and adherence context.", comment: "Follow-up report readiness summary")
        }

        let missing = missingItems.prefix(2).map(\.title).joined(separator: ", ")
        return String(format: NSLocalizedString("Missing: %@.", comment: "Follow-up report readiness summary"), missing)
    }
}

enum FollowUpAgentPlanner {
    private static var eyebrow: String {
        NSLocalizedString("AI Follow-up Agent", comment: "Follow-up agent card eyebrow")
    }

    @MainActor
    static func nextAction(
        store: DataStore,
        stage: FollowUpAgentStage,
        now: Date = Date()
    ) -> FollowUpAgentNextAction? {
        let generatedItems = FollowUpAgentTaskGenerator.generate(store: store, now: now)
        let openItems = FollowUpAgentTaskGenerator
            .merge(generated: generatedItems, existing: store.followUpAgentTasks, now: now)
            .filter(\.isOpen)
            .filter { $0.category != .safety }

        switch stage {
        case .postVisitCapture(let visitID):
            return postVisitAction(store: store, visitID: visitID)
        case .visitDay(let visitID):
            return visitDayAction(store: store, from: openItems, visitID: visitID, now: now)
                ?? doctorSnapshotAction(visitID: visitID)
        case .activePrep(let visitID, _):
            return firstAction(
                from: openItems,
                categories: [.clarification, .missingData, .adherence, .caregiver]
            ) ?? readinessGapAction(store: store, visitID: visitID, now: now)
                ?? reportAction(store: store, from: openItems, visitID: visitID, now: now)
        case .lightPrep(let visitID, _):
            return firstAction(
                from: openItems,
                categories: [.clarification, .missingData, .adherence, .caregiver]
            ) ?? readinessGapAction(store: store, visitID: visitID, now: now)
                ?? reportAction(store: store, from: openItems, visitID: visitID, now: now)
        case .quietAccumulation:
            return firstAction(
                from: openItems,
                categories: [.clarification, .missingData, .adherence, .caregiver]
            )
        }
    }

    @MainActor
    static func reportReadiness(
        store: DataStore,
        domain: FollowUpReportDomain,
        visitID: UUID?,
        now: Date = Date()
    ) -> FollowUpReportReadiness {
        let visit = visitID.flatMap { id in
            store.doctorVisits.first { $0.id == id }
        } ?? store.nextDoctorVisit

        switch domain {
        case .hypertension:
            let medications = store.medications.filter { $0.category == .antihypertensive }
            let report = HypertensionFollowUpReportBuilder.build(store: store, visit: visit, days: 30, now: now)
            return readiness(
                domain: domain,
                medicationCount: report.adherence.medicationCount,
                hasMedicationSchedule: hasMedicationSchedule(medications),
                measurementCount: report.bloodPressure.totalReadings
            )
        case .diabetes:
            let medications = store.medications.filter { $0.category == .antidiabetic }
            let report = DiabetesFollowUpReportBuilder.build(store: store, visit: visit, days: 30, now: now)
            return readiness(
                domain: domain,
                medicationCount: report.adherence.medicationCount,
                hasMedicationSchedule: hasMedicationSchedule(medications),
                measurementCount: report.glucose.totalReadings
            )
        }
    }

    @MainActor
    private static func postVisitAction(store: DataStore, visitID: UUID) -> FollowUpAgentNextAction? {
        guard let visit = store.doctorVisits.first(where: { $0.id == visitID }),
              visit.needsPostVisitCapture else {
            return nil
        }

        let missing = visit.postVisitMissingItems.prefix(3).joined(separator: ", ")
        let detail = missing.isEmpty
            ? NSLocalizedString("Save what changed today so the next follow-up report starts from the doctor’s plan.", comment: "Follow-up agent post visit action detail")
            : String(format: NSLocalizedString("Still missing: %@. Save the doctor’s plan before daily tracking continues.", comment: "Follow-up agent post visit action detail"), missing)

        return FollowUpAgentNextAction(
            stableKey: "agent.next.postVisit.\(visitID.uuidString)",
            eyebrow: eyebrow,
            title: NSLocalizedString("Capture today’s visit plan", comment: "Follow-up agent post visit action title"),
            detail: detail,
            buttonTitle: NSLocalizedString("Record Visit Notes", comment: "Follow-up agent post visit action button"),
            systemImage: "square.and.pencil",
            severity: .caution,
            target: .recordPostVisit(visitID)
        )
    }

    @MainActor
    private static func visitDayAction(store: DataStore, from items: [FollowUpAgentTask], visitID: UUID, now: Date) -> FollowUpAgentNextAction? {
        if let report = reportItem(from: items, visitID: visitID),
           let target = target(for: report),
           let domain = domain(for: report) {
            let readiness = reportReadiness(store: store, domain: domain, visitID: visitID, now: now)
            return FollowUpAgentNextAction(
                stableKey: "agent.next.visitDay.\(report.stableKey)",
                eyebrow: eyebrow,
                title: NSLocalizedString("Use the doctor summary today", comment: "Follow-up agent visit day action title"),
                detail: reportReviewDetail(readiness),
                buttonTitle: NSLocalizedString("Open Report", comment: "Follow-up agent report action button"),
                systemImage: "doc.text.magnifyingglass",
                severity: .caution,
                target: target
            )
        }
        return nil
    }

    private static func doctorSnapshotAction(visitID: UUID) -> FollowUpAgentNextAction {
        FollowUpAgentNextAction(
            stableKey: "agent.next.snapshot.\(visitID.uuidString)",
            eyebrow: eyebrow,
            title: NSLocalizedString("Keep the visit snapshot ready", comment: "Follow-up agent visit day snapshot title"),
            detail: NSLocalizedString("Use the appointment summary to keep medication lists, questions, and recent records in one place.", comment: "Follow-up agent visit day snapshot detail"),
            buttonTitle: NSLocalizedString("Open Visit Snapshot", comment: "Follow-up agent snapshot action button"),
            systemImage: "calendar.badge.clock",
            severity: .information,
            target: .openDoctorSnapshot(visitID)
        )
    }

    @MainActor
    private static func readinessGapAction(store: DataStore, visitID: UUID, now: Date) -> FollowUpAgentNextAction? {
        guard let domain = primaryDomain(store: store) else { return nil }
        let readiness = reportReadiness(store: store, domain: domain, visitID: visitID, now: now)
        guard let gap = readiness.missingItems.first else { return nil }

        return FollowUpAgentNextAction(
            stableKey: "agent.next.readiness.\(domain).\(visitID)",
            eyebrow: eyebrow,
            title: NSLocalizedString("Strengthen the follow-up report", comment: "Follow-up agent readiness action title"),
            detail: reportGapDetail(readiness),
            buttonTitle: buttonTitle(for: gap.target),
            systemImage: systemImage(for: gap.target),
            severity: .information,
            target: gap.target
        )
    }

    private static func firstAction(
        from items: [FollowUpAgentTask],
        categories: [FollowUpAgentTaskCategory]
    ) -> FollowUpAgentNextAction? {
        for category in categories {
            if let item = items.first(where: { $0.category == category }),
               let action = action(from: item) {
                return action
            }
        }
        return nil
    }

    @MainActor
    private static func reportAction(store: DataStore, from items: [FollowUpAgentTask], visitID: UUID, now: Date) -> FollowUpAgentNextAction? {
        guard let item = reportItem(from: items, visitID: visitID),
              let target = target(for: item),
              let domain = domain(for: item) else {
            return nil
        }

        let readiness = reportReadiness(store: store, domain: domain, visitID: visitID, now: now)
        return FollowUpAgentNextAction(
            stableKey: "agent.next.\(item.stableKey)",
            eyebrow: eyebrow,
            title: item.title,
            detail: reportReviewDetail(readiness),
            buttonTitle: NSLocalizedString("Open Report", comment: "Follow-up agent action button"),
            systemImage: "doc.text.magnifyingglass",
            severity: item.severity,
            target: target
        )
    }

    private static func reportItem(from items: [FollowUpAgentTask], visitID: UUID) -> FollowUpAgentTask? {
        items.first {
            $0.relatedID == visitID &&
                ($0.action == .openHypertensionReport || $0.action == .openDiabetesReport)
        }
    }

    private static func action(from item: FollowUpAgentTask) -> FollowUpAgentNextAction? {
        let target = target(for: item)
        let buttonTitle = buttonTitle(for: item.action)
        guard let target, let buttonTitle else { return nil }

        return FollowUpAgentNextAction(
            stableKey: "agent.next.\(item.stableKey)",
            eyebrow: eyebrow,
            title: item.title,
            detail: item.detail,
            buttonTitle: buttonTitle,
            systemImage: systemImage(for: item.action),
            severity: item.severity,
            target: target
        )
    }

    private static func target(for item: FollowUpAgentTask) -> FollowUpAgentActionTarget? {
        switch item.action {
        case .none:
            return nil
        case .logBloodPressure:
            return .logMeasurement(.bloodPressure)
        case .logBloodGlucose:
            return .logMeasurement(.bloodGlucose)
        case .openHypertensionReport:
            return .openHypertensionReport(item.relatedID)
        case .openDiabetesReport:
            return .openDiabetesReport(item.relatedID)
        case .openVisitPrep:
            return .openVisitPrep(item.relatedID)
        case .openCaregivers:
            return .openProfile
        case .openMedications:
            return .openMedications
        case .clarifySymptom:
            guard let id = item.relatedID else { return nil }
            return .clarifySymptom(id)
        }
    }

    private static func domain(for item: FollowUpAgentTask) -> FollowUpReportDomain? {
        switch item.action {
        case .openHypertensionReport:
            return .hypertension
        case .openDiabetesReport:
            return .diabetes
        default:
            return nil
        }
    }

    @MainActor
    private static func primaryDomain(store: DataStore) -> FollowUpReportDomain? {
        let hasHypertensionContext = store.medications.contains { $0.category == .antihypertensive } ||
            store.measurements.contains { $0.type == .bloodPressure }
        if hasHypertensionContext { return .hypertension }

        let hasDiabetesContext = store.medications.contains { $0.category == .antidiabetic } ||
            store.measurements.contains { $0.type == .bloodGlucose }
        if hasDiabetesContext { return .diabetes }

        return nil
    }

    private static func buttonTitle(for action: FollowUpAgentTaskAction) -> String? {
        switch action {
        case .none:
            return nil
        case .logBloodPressure:
            return NSLocalizedString("Log BP", comment: "Follow-up agent action button")
        case .logBloodGlucose:
            return NSLocalizedString("Log Glucose", comment: "Follow-up agent action button")
        case .openHypertensionReport, .openDiabetesReport:
            return NSLocalizedString("Open Report", comment: "Follow-up agent action button")
        case .openVisitPrep:
            return NSLocalizedString("Open Visit Prep", comment: "Follow-up agent action button")
        case .openCaregivers:
            return NSLocalizedString("Open Support", comment: "Follow-up agent action button")
        case .openMedications:
            return NSLocalizedString("Open Medications", comment: "Follow-up agent action button")
        case .clarifySymptom:
            return NSLocalizedString("Clarify Symptom", comment: "Follow-up agent action button")
        }
    }

    private static func buttonTitle(for target: FollowUpAgentActionTarget) -> String {
        switch target {
        case .logMeasurement(.bloodPressure):
            return NSLocalizedString("Log BP", comment: "Follow-up agent action button")
        case .logMeasurement(.bloodGlucose):
            return NSLocalizedString("Log Glucose", comment: "Follow-up agent action button")
        case .logMeasurement:
            return NSLocalizedString("Log Measurement", comment: "Follow-up agent action button")
        case .clarifySymptom:
            return NSLocalizedString("Clarify Symptom", comment: "Follow-up agent action button")
        case .openHypertensionReport, .openDiabetesReport:
            return NSLocalizedString("Open Report", comment: "Follow-up agent action button")
        case .openVisitPrep:
            return NSLocalizedString("Open Visit Prep", comment: "Follow-up agent action button")
        case .openDoctorSnapshot:
            return NSLocalizedString("Open Visit Snapshot", comment: "Follow-up agent snapshot action button")
        case .recordPostVisit:
            return NSLocalizedString("Record Visit Notes", comment: "Follow-up agent post visit action button")
        case .openMedications:
            return NSLocalizedString("Open Medications", comment: "Follow-up agent action button")
        case .openProfile:
            return NSLocalizedString("Open Support", comment: "Follow-up agent action button")
        }
    }

    private static func systemImage(for action: FollowUpAgentTaskAction) -> String {
        switch action {
        case .none:
            return "sparkles"
        case .logBloodPressure, .logBloodGlucose:
            return "plus"
        case .openHypertensionReport, .openDiabetesReport:
            return "doc.text.magnifyingglass"
        case .openVisitPrep:
            return "calendar.badge.clock"
        case .openCaregivers:
            return "person.2"
        case .openMedications:
            return "pills"
        case .clarifySymptom:
            return "questionmark.bubble"
        }
    }

    private static func systemImage(for target: FollowUpAgentActionTarget) -> String {
        switch target {
        case .logMeasurement:
            return "plus"
        case .clarifySymptom:
            return "questionmark.bubble"
        case .openHypertensionReport, .openDiabetesReport:
            return "doc.text.magnifyingglass"
        case .openVisitPrep, .openDoctorSnapshot:
            return "calendar.badge.clock"
        case .recordPostVisit:
            return "square.and.pencil"
        case .openMedications:
            return "pills"
        case .openProfile:
            return "person.2"
        }
    }

    private static func readiness(
        domain: FollowUpReportDomain,
        medicationCount: Int,
        hasMedicationSchedule: Bool,
        measurementCount: Int
    ) -> FollowUpReportReadiness {
        let medicationReady = medicationCount > 0
        let measurementReady = measurementCount >= 7
        let adherenceReady = hasMedicationSchedule
        var missing: [FollowUpReportReadiness.MissingItem] = []

        if !medicationReady {
            missing.append(FollowUpReportReadiness.MissingItem(
                title: NSLocalizedString("Confirm medication list", comment: "Follow-up report readiness missing item"),
                target: .openMedications
            ))
        }

        if !measurementReady {
            missing.append(FollowUpReportReadiness.MissingItem(
                title: domain.measurementGapTitle,
                target: .logMeasurement(domain.measurementType)
            ))
        }

        if medicationReady && !adherenceReady {
            missing.append(FollowUpReportReadiness.MissingItem(
                title: NSLocalizedString("Set medication schedule", comment: "Follow-up report readiness missing item"),
                target: .openMedications
            ))
        }

        let readyCount = [medicationReady, measurementReady, adherenceReady].filter { $0 }.count
        return FollowUpReportReadiness(
            domain: domain,
            readyCount: readyCount,
            totalCount: 3,
            missingItems: missing
        )
    }

    private static func hasMedicationSchedule(_ medications: [Medication]) -> Bool {
        medications.contains { medication in
            medication.isAsNeeded != true && !medication.timesOfDay.isEmpty
        }
    }

    private static func reportGapDetail(_ readiness: FollowUpReportReadiness) -> String {
        String(
            format: NSLocalizedString("Report is %@. %@", comment: "Follow-up agent readiness gap detail"),
            readiness.scoreText,
            readiness.summaryText
        )
    }

    private static func reportReviewDetail(_ readiness: FollowUpReportReadiness) -> String {
        String(
            format: NSLocalizedString("Report is %@. Review the one-page summary and questions before the visit.", comment: "Follow-up agent report review detail"),
            readiness.scoreText
        )
    }
}
