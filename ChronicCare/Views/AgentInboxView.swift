import SwiftUI

struct AgentInboxView: View {
    @EnvironmentObject var store: DataStore
    @State private var showMeasurementSheet = false
    @State private var pendingMeasurementType: MeasurementType = .bloodPressure
    @State private var route: AgentWorkspaceRoute?

    private var openItems: [AgentInboxItem] {
        store.agentInboxItems.filter(\.isOpen)
    }

    private var safetyItems: [AgentInboxItem] {
        openItems.filter { $0.category == .safety }
    }

    private var action: FollowUpAgentNextAction? {
        FollowUpAgentPlanner.nextAction(store: store, stage: currentStage)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: EditorialSpacing.xl) {
                header

                if let urgent = safetyItems.first {
                    safetyCard(urgent)
                }

                decisionCard
                signalPanel
                safetyFooter
            }
            .padding(.horizontal, EditorialSpacing.lg)
            .padding(.vertical, EditorialSpacing.lg)
        }
        .background(AppColor.background)
        .navigationTitle(NSLocalizedString("AI Follow-up Agent", comment: "Follow-up agent title"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    store.refreshAgentInbox()
                    Haptics.impact(.light)
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .accessibilityLabel(NSLocalizedString("Refresh Follow-up Agent", comment: "Follow-up agent refresh action"))
            }
        }
        .sheet(isPresented: $showMeasurementSheet) {
            AddMeasurementView(initialType: pendingMeasurementType) { measurement in
                store.addMeasurement(measurement)
                store.refreshAgentInbox()
                Haptics.success()
            }
            .presentationDetents([.medium, .large])
        }
        .navigationDestination(
            isPresented: Binding(
                get: { route != nil },
                set: { isActive in
                    if !isActive { route = nil }
                }
            )
        ) {
            if let route {
                destination(for: route)
            } else {
                EmptyView()
            }
        }
        .onAppear {
            store.refreshAgentInbox()
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: EditorialSpacing.sm) {
            Text(NSLocalizedString("AI Follow-up Agent", comment: "Follow-up agent heading"))
                .appFont(.displayTitle)
                .fontWeight(.bold)
                .foregroundStyle(AppColor.textPrimary)
            Text(NSLocalizedString("One clinical next step, based on daily records.", comment: "Follow-up agent subtitle"))
                .appFont(.body)
                .foregroundStyle(AppColor.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private var decisionCard: some View {
        if let action {
            Card {
                VStack(alignment: .leading, spacing: EditorialSpacing.md) {
                    HStack(alignment: .top, spacing: EditorialSpacing.md) {
                        Image(systemName: action.systemImage)
                            .font(.system(size: 18, weight: .regular))
                            .foregroundStyle(tint(for: action))
                            .frame(width: 28, height: 28)

                        VStack(alignment: .leading, spacing: EditorialSpacing.xs) {
                            Text(NSLocalizedString("Current focus", comment: "Follow-up agent current focus label"))
                                .appFont(.micro)
                                .textCase(.uppercase)
                                .tracking(0.7)
                                .foregroundStyle(AppColor.textTertiary)

                            Text(action.title)
                                .appFont(.headline)
                                .foregroundStyle(AppColor.textPrimary)
                                .fixedSize(horizontal: false, vertical: true)

                            Text(action.detail)
                                .appFont(.body)
                                .foregroundStyle(AppColor.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        Spacer(minLength: 0)
                    }

                    AppDivider()

                    Text(reason(for: action))
                        .appFont(.caption)
                        .foregroundStyle(AppColor.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)

                    Button {
                        Haptics.impact(.light)
                        handle(action.target)
                    } label: {
                        HStack {
                            Text(action.buttonTitle)
                                .fontWeight(.semibold)
                            Spacer()
                            Image(systemName: "arrow.right")
                                .font(.system(size: 13, weight: .semibold))
                        }
                        .frame(maxWidth: .infinity, minHeight: 42)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(tint(for: action))
                }
            }
        } else {
            Card {
                VStack(alignment: .leading, spacing: EditorialSpacing.sm) {
                    Label(NSLocalizedString("No action needed", comment: "Follow-up agent empty title"), systemImage: "checkmark.circle")
                        .appFont(.headline)
                        .foregroundStyle(AppColor.textPrimary)
                    Text(NSLocalizedString("Keep recording blood pressure, medication intake, symptoms, and visit dates.", comment: "Follow-up agent empty detail"))
                        .appFont(.body)
                        .foregroundStyle(AppColor.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var signalPanel: some View {
        EditorialSection(NSLocalizedString("Watching", comment: "Follow-up agent signal section")) {
            VStack(spacing: EditorialSpacing.md) {
                signalRow(
                    icon: "waveform.path.ecg",
                    title: NSLocalizedString("Blood pressure", comment: "Follow-up agent signal"),
                    detail: bloodPressureSignal,
                    tint: AppColor.primary
                )
                AppDivider()
                signalRow(
                    icon: "pills",
                    title: NSLocalizedString("Medication", comment: "Follow-up agent signal"),
                    detail: medicationSignal,
                    tint: AppColor.primary
                )
                AppDivider()
                signalRow(
                    icon: "heart.text.square",
                    title: NSLocalizedString("Symptoms", comment: "Follow-up agent signal"),
                    detail: symptomSignal,
                    tint: AppColor.primary
                )
            }
        }
    }

    private func safetyCard(_ item: AgentInboxItem) -> some View {
        TintedCard(tint: AppColor.warning) {
            VStack(alignment: .leading, spacing: EditorialSpacing.sm) {
                Label(item.title, systemImage: "exclamationmark.triangle")
                    .appFont(.headline)
                    .foregroundStyle(AppColor.textPrimary)
                Text(item.detail)
                    .appFont(.body)
                    .foregroundStyle(AppColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button {
                    Haptics.impact(.light)
                    let target: FollowUpAgentActionTarget = item.action == .openDiabetesReport
                        ? .openDiabetesReport(item.relatedID)
                        : .openHypertensionReport(item.relatedID)
                    handle(target)
                } label: {
                    Label(NSLocalizedString("Open Report", comment: "Follow-up agent safety action"), systemImage: "doc.text.magnifyingglass")
                }
                .buttonStyle(.borderless)
                .foregroundStyle(AppColor.warning)
            }
        }
    }

    private var safetyFooter: some View {
        Text(NSLocalizedString("Safety warnings are rule-based. AI drafts summaries, not diagnoses or medication changes.", comment: "Follow-up agent safety footer"))
            .appFont(.caption)
            .foregroundStyle(AppColor.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func signalRow(icon: String, title: String, detail: String, tint: Color) -> some View {
        HStack(alignment: .top, spacing: EditorialSpacing.md) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .regular))
                .foregroundStyle(tint)
                .frame(width: 26, height: 26)
            VStack(alignment: .leading, spacing: EditorialSpacing.xxs) {
                Text(title)
                    .appFont(.body)
                    .foregroundStyle(AppColor.textPrimary)
                Text(detail)
                    .appFont(.caption)
                    .foregroundStyle(AppColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
    }

    private var bloodPressureSignal: String {
        let count = recentMeasurements(type: .bloodPressure, days: 30).count
        if count == 0 {
            return NSLocalizedString("No recent BP readings", comment: "Follow-up agent BP signal")
        }
        return String(format: NSLocalizedString("%lld readings in 30 days", comment: "Follow-up agent BP signal"), Int64(count))
    }

    private var medicationSignal: String {
        let scheduled = store.medications.filter { $0.isAsNeeded != true && !$0.timesOfDay.isEmpty }
        guard !scheduled.isEmpty else {
            return NSLocalizedString("No scheduled medication routine", comment: "Follow-up agent medication signal")
        }
        let percent = Int(store.adherencePercent(days: 14).rounded())
        return String(format: NSLocalizedString("%lld%% adherence in 14 days", comment: "Follow-up agent medication signal"), Int64(percent))
    }

    private var symptomSignal: String {
        let count = recentSymptoms(days: 14).filter { !isBenignFeeling($0) }.count
        if count == 0 {
            return NSLocalizedString("No recent discomfort logs", comment: "Follow-up agent symptom signal")
        }
        return String(format: NSLocalizedString("%lld recent symptom logs", comment: "Follow-up agent symptom signal"), Int64(count))
    }

    private var currentStage: FollowUpAgentStage {
        if let visit = recentCompletedVisitForCapture {
            return .postVisitCapture(visitID: visit.id)
        }

        guard let visit = store.nextDoctorVisit,
              let days = visit.daysUntil() else {
            return .quietAccumulation
        }

        if days == 0 { return .visitDay(visitID: visit.id) }
        if days <= 3 { return .activePrep(visitID: visit.id, daysUntil: days) }
        if days <= 7 { return .lightPrep(visitID: visit.id, daysUntil: days) }
        return .quietAccumulation
    }

    private var recentCompletedVisitForCapture: DoctorVisit? {
        let now = Date()
        return store.completedDoctorVisits.first { visit in
            guard let completedDate = visit.completedDate else { return false }
            return now.timeIntervalSince(completedDate) <= 48 * 60 * 60 && visit.needsPostVisitCapture
        }
    }

    private func recentMeasurements(type: MeasurementType, days: Int) -> [Measurement] {
        let cutoff = Calendar.current.date(byAdding: .day, value: -days + 1, to: Calendar.current.startOfDay(for: Date())) ?? Date()
        return store.measurements.filter { $0.type == type && $0.date >= cutoff }
    }

    private func recentSymptoms(days: Int) -> [SymptomEntry] {
        let cutoff = Calendar.current.date(byAdding: .day, value: -days + 1, to: Calendar.current.startOfDay(for: Date())) ?? Date()
        return store.symptomEntries.filter { $0.date >= cutoff }
    }

    private func isBenignFeeling(_ symptom: SymptomEntry) -> Bool {
        let note = symptom.note?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard note.isEmpty, symptom.severity == .mild else { return false }
        let benignTags: Set<String> = ["felt good", "felt okay", "今天感觉好", "今天感觉一般"]
        return symptom.tags
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .allSatisfy { benignTags.contains($0) }
    }

    private func reason(for action: FollowUpAgentNextAction) -> String {
        switch action.target {
        case .logMeasurement(.bloodPressure):
            return NSLocalizedString("The report needs current home BP context before it can be useful to a doctor.", comment: "Follow-up agent reason")
        case .logMeasurement(.bloodGlucose):
            return NSLocalizedString("The report needs current home glucose context before it can be useful to a doctor.", comment: "Follow-up agent reason")
        case .clarifySymptom:
            return NSLocalizedString("A symptom was recorded without enough timing or medication context.", comment: "Follow-up agent reason")
        case .openHypertensionReport, .openDiabetesReport:
            return NSLocalizedString("The agent has enough structured data to prepare a doctor-facing summary.", comment: "Follow-up agent reason")
        case .openVisitPrep, .openDoctorSnapshot:
            return NSLocalizedString("The visit is close enough that questions and records should be reviewed together.", comment: "Follow-up agent reason")
        case .recordPostVisit:
            return NSLocalizedString("The next cycle should start from what the doctor changed at this visit.", comment: "Follow-up agent reason")
        case .openMedications:
            return NSLocalizedString("Medication list and schedule are core evidence for a follow-up report.", comment: "Follow-up agent reason")
        case .openProfile:
            return NSLocalizedString("Caregiver support matters when missed doses need follow-up.", comment: "Follow-up agent reason")
        case .logMeasurement:
            return NSLocalizedString("The report needs current measurement context before it can be useful to a doctor.", comment: "Follow-up agent reason")
        }
    }

    private func tint(for action: FollowUpAgentNextAction) -> Color {
        switch action.severity {
        case .urgent, .caution:
            return AppColor.warning
        case .information:
            return AppColor.primary
        }
    }

    private func handle(_ target: FollowUpAgentActionTarget) {
        switch target {
        case .logMeasurement(let type):
            pendingMeasurementType = type
            showMeasurementSheet = true
        case .clarifySymptom(let symptomID):
            route = AgentWorkspaceRoute(kind: .symptomClarification, relatedID: symptomID)
        case .openHypertensionReport(let visitID):
            route = AgentWorkspaceRoute(kind: .hypertensionReport, relatedID: visitID)
        case .openDiabetesReport(let visitID):
            route = AgentWorkspaceRoute(kind: .diabetesReport, relatedID: visitID)
        case .openVisitPrep(let visitID), .openDoctorSnapshot(let visitID):
            route = AgentWorkspaceRoute(kind: .visitPrep, relatedID: visitID)
        case .recordPostVisit(let visitID):
            route = AgentWorkspaceRoute(kind: .visitPrep, relatedID: visitID)
        case .openMedications:
            route = AgentWorkspaceRoute(kind: .medications, relatedID: nil)
        case .openProfile:
            route = AgentWorkspaceRoute(kind: .caregivers, relatedID: nil)
        }
    }

    @ViewBuilder
    private func destination(for route: AgentWorkspaceRoute) -> some View {
        switch route.kind {
        case .hypertensionReport:
            HypertensionFollowUpReportView(visit: visit(for: route.relatedID))
        case .diabetesReport:
            DiabetesFollowUpReportView(visit: visit(for: route.relatedID))
        case .visitPrep:
            DoctorVisitsView()
        case .caregivers:
            CaregiversView()
        case .medications:
            MedicationsView()
        case .symptomClarification:
            if let symptom = route.relatedID.flatMap(symptom(for:)) {
                SymptomClarificationView(symptom: symptom)
            } else {
                DoctorVisitsView()
            }
        }
    }

    private func visit(for id: UUID?) -> DoctorVisit? {
        guard let id else { return store.nextDoctorVisit }
        return store.doctorVisits.first { $0.id == id } ?? store.nextDoctorVisit
    }

    private func symptom(for id: UUID) -> SymptomEntry? {
        store.symptomEntries.first { $0.id == id }
    }
}

private struct AgentWorkspaceRoute: Identifiable, Hashable {
    enum Kind: Hashable {
        case hypertensionReport
        case diabetesReport
        case visitPrep
        case caregivers
        case medications
        case symptomClarification
    }

    let kind: Kind
    let relatedID: UUID?

    var id: String {
        "\(kind)-\(relatedID?.uuidString ?? "none")"
    }
}

#Preview {
    NavigationStack {
        AgentInboxView()
            .environmentObject(DataStore())
    }
}
