import SwiftUI

struct FollowUpAgentWorkspaceView: View {
    @EnvironmentObject var store: DataStore
    @State private var showMeasurementSheet = false
    @State private var pendingMeasurementType: MeasurementType = .bloodPressure

    private var openItems: [FollowUpAgentTask] {
        store.followUpAgentTasks.filter(\.isOpen)
    }

    private var safetyItems: [FollowUpAgentTask] {
        openItems.filter { $0.category == .safety }
    }

    private var action: FollowUpAgentNextAction? {
        FollowUpAgentPlanner.nextAction(store: store, stage: currentStage)
    }

    private var suggestedAction: FollowUpAgentNextAction? {
        guard let action, !isReportOpeningTarget(action.target) else { return nil }
        return action
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: EditorialSpacing.xl) {
                header

                if let urgent = safetyItems.first {
                    safetyCard(urgent)
                }

                findingsCard
                if let suggestedAction {
                    suggestedActionCard(suggestedAction)
                }
                preparedCard
                safetyFooter
            }
            .padding(.horizontal, EditorialSpacing.lg)
            .padding(.vertical, EditorialSpacing.lg)
        }
        .background(AppColor.background)
        .navigationTitle(NSLocalizedString("Follow-up organizer", comment: "Follow-up agent title"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    store.refreshFollowUpAgentTasks()
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
                store.refreshFollowUpAgentTasks()
                Haptics.success()
            }
            .presentationDetents([.medium, .large])
        }
        .onAppear {
            store.refreshFollowUpAgentTasks()
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: EditorialSpacing.sm) {
            Text(NSLocalizedString("Follow-up organizer", comment: "Follow-up agent heading"))
                .appFont(.displayTitle)
                .fontWeight(.bold)
                .foregroundStyle(AppColor.textPrimary)
            Text(NSLocalizedString("I organize daily records into a visit-ready report.", comment: "Follow-up agent subtitle"))
                .appFont(.body)
                .foregroundStyle(AppColor.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func safetyCard(_ item: FollowUpAgentTask) -> some View {
        TintedCard(tint: AppColor.warning) {
            VStack(alignment: .leading, spacing: EditorialSpacing.sm) {
                Label(item.title, systemImage: "exclamationmark.triangle")
                    .appFont(.headline)
                    .foregroundStyle(AppColor.textPrimary)
                Text(item.detail)
                    .appFont(.body)
                    .foregroundStyle(AppColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                let target: FollowUpAgentActionTarget = item.action == .openDiabetesReport
                    ? .openDiabetesReport(item.relatedID)
                    : .openHypertensionReport(item.relatedID)
                if let route = navigationRoute(for: target) {
                    NavigationLink {
                        destination(for: route)
                    } label: {
                        Label(NSLocalizedString("Open Report", comment: "Follow-up agent safety action"), systemImage: "doc.text.magnifyingglass")
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(AppColor.warning)
                }
            }
        }
    }

    private var safetyFooter: some View {
        Text(NSLocalizedString("Safety warnings are rule-based. AI drafts summaries, not diagnoses or medication changes.", comment: "Follow-up agent safety footer"))
            .appFont(.caption)
            .foregroundStyle(AppColor.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var findingsCard: some View {
        Card {
            VStack(alignment: .leading, spacing: EditorialSpacing.md) {
                sectionTitle(NSLocalizedString("I found", comment: "Follow-up agent findings section"))
                ForEach(Array(findings.enumerated()), id: \.element.id) { index, finding in
                    organizerRow(
                        icon: finding.systemImage,
                        title: finding.title,
                        detail: finding.detail,
                        tint: finding.tint
                    )
                    if index < findings.count - 1 {
                        AppDivider()
                    }
                }
            }
        }
    }

    private func suggestedActionCard(_ action: FollowUpAgentNextAction) -> some View {
        Card {
            VStack(alignment: .leading, spacing: EditorialSpacing.md) {
                sectionTitle(NSLocalizedString("Suggested next step", comment: "Follow-up agent suggested action section"))
                organizerRow(
                    icon: action.systemImage,
                    title: action.title,
                    detail: action.detail,
                    tint: tint(for: action)
                )
                actionControl(action)
            }
        }
    }

    private var preparedCard: some View {
        Card {
            VStack(alignment: .leading, spacing: EditorialSpacing.md) {
                sectionTitle(NSLocalizedString("Already prepared", comment: "Follow-up agent prepared section"))
                organizerRow(
                    icon: "doc.text.magnifyingglass",
                    title: NSLocalizedString("Visit report", comment: "Follow-up agent prepared report title"),
                    detail: preparedReportDetail,
                    tint: AppColor.primary
                )
                NavigationLink {
                    destination(for: primaryReportRoute(visitID: currentStage.visitID))
                } label: {
                    actionButtonLabel(NSLocalizedString("Open Visit Report", comment: "Follow-up agent prepared report action"))
                }
                .buttonStyle(.borderedProminent)
                .tint(AppColor.primary)
            }
        }
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title)
            .appFont(.micro)
            .textCase(.uppercase)
            .tracking(0.7)
            .foregroundStyle(AppColor.textTertiary)
    }

    private func organizerRow(icon: String, title: String, detail: String, tint: Color) -> some View {
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

    private var findings: [OrganizerFinding] {
        [
            OrganizerFinding(
                id: "bloodPressure",
                title: NSLocalizedString("Blood pressure", comment: "Follow-up agent signal"),
                detail: bloodPressureSignal,
                systemImage: "waveform.path.ecg",
                tint: AppColor.primary
            ),
            OrganizerFinding(
                id: "medication",
                title: NSLocalizedString("Medication", comment: "Follow-up agent signal"),
                detail: medicationSignal,
                systemImage: "pills",
                tint: AppColor.primary
            ),
            OrganizerFinding(
                id: "symptoms",
                title: NSLocalizedString("Symptoms", comment: "Follow-up agent signal"),
                detail: symptomSignal,
                systemImage: "heart.text.square",
                tint: AppColor.primary
            )
        ]
    }

    private var preparedReportDetail: String {
        if suggestedAction == nil {
            return NSLocalizedString("The current report is ready from the records available now.", comment: "Follow-up agent prepared report detail")
        }
        return NSLocalizedString("The report is available now and will improve after the suggested update.", comment: "Follow-up agent prepared report detail")
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

    private func tint(for action: FollowUpAgentNextAction) -> Color {
        switch action.severity {
        case .urgent, .caution:
            return AppColor.warning
        case .information:
            return AppColor.primary
        }
    }

    private func isReportOpeningTarget(_ target: FollowUpAgentActionTarget) -> Bool {
        switch target {
        case .openHypertensionReport, .openDiabetesReport, .openVisitPrep, .openDoctorSnapshot:
            return true
        case .logMeasurement, .clarifySymptom, .recordPostVisit, .openMedications, .openProfile:
            return false
        }
    }

    @ViewBuilder
    private func actionControl(_ action: FollowUpAgentNextAction) -> some View {
        if let route = navigationRoute(for: action.target) {
            NavigationLink {
                destination(for: route)
            } label: {
                actionButtonLabel(action.buttonTitle)
            }
            .buttonStyle(.borderedProminent)
            .tint(tint(for: action))
        } else {
            Button {
                Haptics.impact(.light)
                handle(action.target)
            } label: {
                actionButtonLabel(action.buttonTitle)
            }
            .buttonStyle(.borderedProminent)
            .tint(tint(for: action))
        }
    }

    private func actionButtonLabel(_ title: String) -> some View {
        HStack {
            Text(title)
                .fontWeight(.semibold)
            Spacer()
            Image(systemName: "arrow.right")
                .font(.system(size: 13, weight: .semibold))
        }
        .frame(maxWidth: .infinity, minHeight: 42)
    }

    private func navigationRoute(for target: FollowUpAgentActionTarget) -> FollowUpAgentWorkspaceRoute? {
        switch target {
        case .logMeasurement:
            return nil
        case .clarifySymptom(let symptomID):
            return FollowUpAgentWorkspaceRoute(kind: .symptomClarification, relatedID: symptomID)
        case .openHypertensionReport(let visitID):
            return FollowUpAgentWorkspaceRoute(kind: .hypertensionReport, relatedID: visitID)
        case .openDiabetesReport(let visitID):
            return FollowUpAgentWorkspaceRoute(kind: .diabetesReport, relatedID: visitID)
        case .openVisitPrep(let visitID), .openDoctorSnapshot(let visitID):
            return primaryReportRoute(visitID: visitID)
        case .recordPostVisit(let visitID):
            return FollowUpAgentWorkspaceRoute(kind: .visitPrep, relatedID: visitID)
        case .openMedications:
            return FollowUpAgentWorkspaceRoute(kind: .medications, relatedID: nil)
        case .openProfile:
            return FollowUpAgentWorkspaceRoute(kind: .caregivers, relatedID: nil)
        }
    }

    private func primaryReportRoute(visitID: UUID?) -> FollowUpAgentWorkspaceRoute {
        let hasHypertensionContext = store.medications.contains { $0.category == .antihypertensive }
            || store.measurements.contains { $0.type == .bloodPressure }
        if hasHypertensionContext {
            return FollowUpAgentWorkspaceRoute(kind: .hypertensionReport, relatedID: visitID)
        }

        let hasDiabetesContext = store.medications.contains { $0.category == .antidiabetic }
            || store.measurements.contains { $0.type == .bloodGlucose }
        if hasDiabetesContext {
            return FollowUpAgentWorkspaceRoute(kind: .diabetesReport, relatedID: visitID)
        }

        return FollowUpAgentWorkspaceRoute(kind: .hypertensionReport, relatedID: visitID)
    }

    private func handle(_ target: FollowUpAgentActionTarget) {
        switch target {
        case .logMeasurement(let type):
            pendingMeasurementType = type
            showMeasurementSheet = true
        case .clarifySymptom,
             .openHypertensionReport,
             .openDiabetesReport,
             .openVisitPrep,
             .openDoctorSnapshot,
             .recordPostVisit,
             .openMedications,
             .openProfile:
            break
        }
    }

    @ViewBuilder
    private func destination(for route: FollowUpAgentWorkspaceRoute) -> some View {
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

private struct OrganizerFinding: Identifiable {
    let id: String
    let title: String
    let detail: String
    let systemImage: String
    let tint: Color
}

private struct FollowUpAgentWorkspaceRoute: Identifiable, Hashable {
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
        FollowUpAgentWorkspaceView()
            .environmentObject(DataStore())
    }
}
