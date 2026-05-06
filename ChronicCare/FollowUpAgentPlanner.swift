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

enum FollowUpAgentPlanner {
    @MainActor
    static func nextAction(
        store: DataStore,
        stage: FollowUpAgentStage,
        now: Date = Date()
    ) -> FollowUpAgentNextAction? {
        let generatedItems = AgentInboxGenerator.generate(store: store, now: now)
        let openItems = AgentInboxGenerator
            .merge(generated: generatedItems, existing: store.agentInboxItems, now: now)
            .filter(\.isOpen)
            .filter { $0.category != .safety }

        switch stage {
        case .postVisitCapture(let visitID):
            return postVisitAction(store: store, visitID: visitID)
        case .visitDay(let visitID):
            return visitDayAction(from: openItems, visitID: visitID)
                ?? doctorSnapshotAction(visitID: visitID)
        case .activePrep(let visitID, _):
            return firstAction(
                from: openItems,
                categories: [.clarification, .missingData, .adherence, .caregiver]
            ) ?? reportAction(from: openItems, visitID: visitID)
        case .lightPrep(let visitID, _):
            return firstAction(
                from: openItems,
                categories: [.clarification, .missingData, .adherence, .caregiver]
            ) ?? reportAction(from: openItems, visitID: visitID)
        case .quietAccumulation:
            return firstAction(
                from: openItems,
                categories: [.clarification, .missingData, .adherence, .caregiver]
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
            eyebrow: NSLocalizedString("Agent next step", comment: "Follow-up agent card eyebrow"),
            title: NSLocalizedString("Capture today’s visit plan", comment: "Follow-up agent post visit action title"),
            detail: detail,
            buttonTitle: NSLocalizedString("Record Visit Notes", comment: "Follow-up agent post visit action button"),
            systemImage: "square.and.pencil",
            severity: .caution,
            target: .recordPostVisit(visitID)
        )
    }

    private static func visitDayAction(from items: [AgentInboxItem], visitID: UUID) -> FollowUpAgentNextAction? {
        if let report = reportItem(from: items, visitID: visitID),
           let target = target(for: report) {
            return FollowUpAgentNextAction(
                stableKey: "agent.next.visitDay.\(report.stableKey)",
                eyebrow: NSLocalizedString("Agent next step", comment: "Follow-up agent card eyebrow"),
                title: NSLocalizedString("Use the doctor summary today", comment: "Follow-up agent visit day action title"),
                detail: NSLocalizedString("Open the one-page follow-up report and questions before the appointment.", comment: "Follow-up agent visit day action detail"),
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
            eyebrow: NSLocalizedString("Agent next step", comment: "Follow-up agent card eyebrow"),
            title: NSLocalizedString("Keep the visit snapshot ready", comment: "Follow-up agent visit day snapshot title"),
            detail: NSLocalizedString("Use the appointment summary to keep medication lists, questions, and recent records in one place.", comment: "Follow-up agent visit day snapshot detail"),
            buttonTitle: NSLocalizedString("Open Visit Snapshot", comment: "Follow-up agent snapshot action button"),
            systemImage: "calendar.badge.clock",
            severity: .information,
            target: .openDoctorSnapshot(visitID)
        )
    }

    private static func firstAction(
        from items: [AgentInboxItem],
        categories: [AgentInboxCategory]
    ) -> FollowUpAgentNextAction? {
        for category in categories {
            if let item = items.first(where: { $0.category == category }),
               let action = action(from: item) {
                return action
            }
        }
        return nil
    }

    private static func reportAction(from items: [AgentInboxItem], visitID: UUID) -> FollowUpAgentNextAction? {
        guard let item = reportItem(from: items, visitID: visitID) else { return nil }
        return action(from: item)
    }

    private static func reportItem(from items: [AgentInboxItem], visitID: UUID) -> AgentInboxItem? {
        items.first {
            $0.relatedID == visitID &&
                ($0.action == .openHypertensionReport || $0.action == .openDiabetesReport)
        }
    }

    private static func action(from item: AgentInboxItem) -> FollowUpAgentNextAction? {
        let target = target(for: item)
        let buttonTitle = buttonTitle(for: item.action)
        guard let target, let buttonTitle else { return nil }

        return FollowUpAgentNextAction(
            stableKey: "agent.next.\(item.stableKey)",
            eyebrow: NSLocalizedString("Agent next step", comment: "Follow-up agent card eyebrow"),
            title: item.title,
            detail: item.detail,
            buttonTitle: buttonTitle,
            systemImage: systemImage(for: item.action),
            severity: item.severity,
            target: target
        )
    }

    private static func target(for item: AgentInboxItem) -> FollowUpAgentActionTarget? {
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

    private static func buttonTitle(for action: AgentInboxAction) -> String? {
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

    private static func systemImage(for action: AgentInboxAction) -> String {
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
}
