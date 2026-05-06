import SwiftUI

struct AgentInboxView: View {
    @EnvironmentObject var store: DataStore
    @State private var showMeasurementSheet = false
    @State private var pendingMeasurementType: MeasurementType = .bloodPressure

    private var openItems: [AgentInboxItem] {
        store.agentInboxItems.filter(\.isOpen)
    }

    private var dismissedItems: [AgentInboxItem] {
        store.agentInboxItems.filter { !$0.isOpen }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: EditorialSpacing.xl) {
                header
                openSection
                if !dismissedItems.isEmpty {
                    dismissedSection
                }
                safetyNote
            }
            .padding(.horizontal, EditorialSpacing.lg)
            .padding(.vertical, EditorialSpacing.lg)
        }
        .background(AppColor.background)
        .navigationTitle(NSLocalizedString("Agent Inbox", comment: "Agent inbox title"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    store.refreshAgentInbox()
                    Haptics.impact(.light)
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .accessibilityLabel(NSLocalizedString("Refresh Agent Inbox", comment: "Agent inbox refresh action"))
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
        .onAppear {
            store.refreshAgentInbox()
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: EditorialSpacing.sm) {
            Text(NSLocalizedString("Agent Inbox", comment: "Agent inbox heading"))
                .appFont(.displayTitle)
                .fontWeight(.bold)
                .foregroundStyle(AppColor.textPrimary)
            Text(NSLocalizedString("A local follow-up agent turns daily records into the next useful action.", comment: "Agent inbox subtitle"))
                .appFont(.body)
                .foregroundStyle(AppColor.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: EditorialSpacing.md) {
                metric(value: "\(openItems.count)", label: NSLocalizedString("Open", comment: "Agent inbox metric"))
                metricDivider
                metric(value: "\(urgentCount)", label: NSLocalizedString("Urgent", comment: "Agent inbox metric"))
                metricDivider
                metric(value: "\(reportCount)", label: NSLocalizedString("Reports", comment: "Agent inbox metric"))
            }
            .padding(.top, EditorialSpacing.xs)
        }
    }

    private var openSection: some View {
        EditorialSection(
            NSLocalizedString("Open Items", comment: "Agent inbox section"),
            trailing: String(format: NSLocalizedString("%lld open", comment: "Agent inbox open count"), Int64(openItems.count))
        ) {
            if openItems.isEmpty {
                VStack(alignment: .leading, spacing: EditorialSpacing.xs) {
                    Text(NSLocalizedString("Nothing needs attention right now.", comment: "Agent inbox empty title"))
                        .appFont(.headline)
                        .foregroundStyle(AppColor.textPrimary)
                    Text(NSLocalizedString("Keep recording medication intake, measurements, symptoms, and visit dates.", comment: "Agent inbox empty detail"))
                        .appFont(.body)
                        .foregroundStyle(AppColor.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.vertical, EditorialSpacing.xs)
            } else {
                VStack(spacing: EditorialSpacing.md) {
                    ForEach(Array(openItems.enumerated()), id: \.element.id) { index, item in
                        inboxRow(item, isDismissed: false)
                        if index < openItems.count - 1 {
                            AppDivider()
                        }
                    }
                }
            }
        }
    }

    private var dismissedSection: some View {
        EditorialSection(
            NSLocalizedString("Dismissed", comment: "Agent inbox section"),
            trailing: String(format: NSLocalizedString("%lld dismissed", comment: "Agent inbox dismissed count"), Int64(dismissedItems.count))
        ) {
            VStack(spacing: EditorialSpacing.md) {
                ForEach(Array(dismissedItems.prefix(5).enumerated()), id: \.element.id) { index, item in
                    inboxRow(item, isDismissed: true)
                    if index < min(dismissedItems.count, 5) - 1 {
                        AppDivider()
                    }
                }
            }
        }
    }

    private var safetyNote: some View {
        Text(NSLocalizedString("Safety signals are rule-based. AI may draft summaries elsewhere, but it does not decide medical risk or medication changes.", comment: "Agent inbox safety note"))
            .appFont(.caption)
            .foregroundStyle(AppColor.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func inboxRow(_ item: AgentInboxItem, isDismissed: Bool) -> some View {
        VStack(alignment: .leading, spacing: EditorialSpacing.md) {
            HStack(alignment: .top, spacing: EditorialSpacing.md) {
                Image(systemName: item.category.iconName)
                    .font(.system(size: 15, weight: .regular))
                    .foregroundStyle(item.tint)
                    .frame(width: 28, height: 28)

                VStack(alignment: .leading, spacing: EditorialSpacing.xs) {
                    HStack(spacing: EditorialSpacing.sm) {
                        Text(item.category.displayName)
                            .appFont(.micro)
                            .foregroundStyle(AppColor.textTertiary)
                            .textCase(.uppercase)
                        if item.source == .rule {
                            Text(NSLocalizedString("Rule", comment: "Agent inbox source badge"))
                                .appFont(.micro)
                                .foregroundStyle(AppColor.warning)
                                .textCase(.uppercase)
                        }
                    }
                    Text(item.title)
                        .appFont(.headline)
                        .foregroundStyle(AppColor.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(item.detail)
                        .appFont(.body)
                        .foregroundStyle(AppColor.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: EditorialSpacing.sm)

                if !isDismissed {
                    Button {
                        store.dismissAgentInboxItem(item)
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 13, weight: .regular))
                            .foregroundStyle(AppColor.textTertiary)
                            .frame(width: 30, height: 30)
                    }
                    .accessibilityLabel(NSLocalizedString("Dismiss", comment: "Agent inbox dismiss action"))
                }
            }

            if isDismissed {
                Button {
                    store.reopenAgentInboxItem(item)
                } label: {
                    Label(NSLocalizedString("Reopen", comment: "Agent inbox reopen action"), systemImage: "arrow.uturn.backward")
                }
                .buttonStyle(.borderless)
                .foregroundStyle(AppColor.primary)
            } else {
                actionControl(for: item)
            }
        }
        .padding(.vertical, EditorialSpacing.xs)
        .opacity(isDismissed ? 0.72 : 1)
    }

    @ViewBuilder
    private func actionControl(for item: AgentInboxItem) -> some View {
        switch item.action {
        case .logBloodPressure:
            Button {
                pendingMeasurementType = .bloodPressure
                showMeasurementSheet = true
            } label: {
                Label(NSLocalizedString("Log BP", comment: "Agent inbox action"), systemImage: "plus")
            }
            .buttonStyle(.borderless)
            .foregroundStyle(AppColor.primary)
        case .logBloodGlucose:
            Button {
                pendingMeasurementType = .bloodGlucose
                showMeasurementSheet = true
            } label: {
                Label(NSLocalizedString("Log Glucose", comment: "Agent inbox action"), systemImage: "plus")
            }
            .buttonStyle(.borderless)
            .foregroundStyle(AppColor.primary)
        case .openHypertensionReport:
            NavigationLink {
                HypertensionFollowUpReportView(visit: visit(for: item))
            } label: {
                Label(NSLocalizedString("Open Report", comment: "Agent inbox action"), systemImage: "doc.text.magnifyingglass")
            }
            .foregroundStyle(AppColor.primary)
        case .openDiabetesReport:
            NavigationLink {
                DiabetesFollowUpReportView(visit: visit(for: item))
            } label: {
                Label(NSLocalizedString("Open Report", comment: "Agent inbox action"), systemImage: "doc.text.magnifyingglass")
            }
            .foregroundStyle(AppColor.primary)
        case .openVisitPrep:
            NavigationLink {
                DoctorVisitsView()
            } label: {
                Label(NSLocalizedString("Open Visit Prep", comment: "Agent inbox action"), systemImage: "calendar.badge.clock")
            }
            .foregroundStyle(AppColor.primary)
        case .openCaregivers:
            NavigationLink {
                CaregiversView()
            } label: {
                Label(NSLocalizedString("Open Caregivers", comment: "Agent inbox action"), systemImage: "person.2")
            }
            .foregroundStyle(AppColor.primary)
        case .openMedications:
            NavigationLink {
                MedicationsView()
            } label: {
                Label(NSLocalizedString("Open Medications", comment: "Agent inbox action"), systemImage: "pills")
            }
            .foregroundStyle(AppColor.primary)
        case .clarifySymptom:
            if let symptom = symptom(for: item) {
                NavigationLink {
                    SymptomClarificationView(symptom: symptom)
                } label: {
                    Label(NSLocalizedString("Clarify Symptom", comment: "Agent inbox action"), systemImage: "questionmark.bubble")
                }
                .foregroundStyle(AppColor.primary)
            } else {
                Button {
                    store.dismissAgentInboxItem(item)
                } label: {
                    Label(NSLocalizedString("Mark Done", comment: "Agent inbox action"), systemImage: "checkmark")
                }
                .buttonStyle(.borderless)
                .foregroundStyle(AppColor.primary)
            }
        case .none:
            Button {
                store.dismissAgentInboxItem(item)
            } label: {
                Label(NSLocalizedString("Mark Done", comment: "Agent inbox action"), systemImage: "checkmark")
            }
            .buttonStyle(.borderless)
            .foregroundStyle(AppColor.primary)
        }
    }

    private var urgentCount: Int {
        openItems.filter { $0.severity == .urgent }.count
    }

    private var reportCount: Int {
        openItems.filter { $0.category == .report }.count
    }

    private var metricDivider: some View {
        Rectangle()
            .fill(AppColor.divider)
            .frame(width: 1, height: 34)
    }

    private func metric(value: String, label: String) -> some View {
        VStack(alignment: .leading, spacing: EditorialSpacing.xxs) {
            Text(value)
                .appFontNumeric(.headline)
                .foregroundStyle(AppColor.textPrimary)
            Text(label)
                .appFont(.caption)
                .foregroundStyle(AppColor.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func visit(for item: AgentInboxItem) -> DoctorVisit? {
        if let id = item.relatedID {
            return store.doctorVisits.first { $0.id == id } ?? store.nextDoctorVisit
        }
        return store.nextDoctorVisit
    }

    private func symptom(for item: AgentInboxItem) -> SymptomEntry? {
        guard let id = item.relatedID else { return nil }
        return store.symptomEntries.first { $0.id == id }
    }
}

private extension AgentInboxItem {
    var tint: Color {
        switch severity {
        case .urgent, .caution:
            return AppColor.warning
        case .information:
            return category == .report ? AppColor.primary : AppColor.textSecondary
        }
    }
}

private extension AgentInboxCategory {
    var displayName: String {
        switch self {
        case .safety: return NSLocalizedString("Safety", comment: "Agent inbox category")
        case .missingData: return NSLocalizedString("Missing Data", comment: "Agent inbox category")
        case .adherence: return NSLocalizedString("Adherence", comment: "Agent inbox category")
        case .clarification: return NSLocalizedString("Clarify", comment: "Agent inbox category")
        case .report: return NSLocalizedString("Report", comment: "Agent inbox category")
        case .caregiver: return NSLocalizedString("Caregiver", comment: "Agent inbox category")
        }
    }

    var iconName: String {
        switch self {
        case .safety: return "exclamationmark.triangle"
        case .missingData: return "waveform.path.ecg"
        case .adherence: return "pills"
        case .clarification: return "questionmark.circle"
        case .report: return "doc.text.magnifyingglass"
        case .caregiver: return "person.2"
        }
    }
}

#Preview {
    NavigationStack {
        AgentInboxView()
            .environmentObject(DataStore())
    }
}
