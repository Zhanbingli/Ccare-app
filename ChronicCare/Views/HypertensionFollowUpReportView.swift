import SwiftUI

struct HypertensionFollowUpReportView: View {
    @EnvironmentObject var store: DataStore
    var visit: DoctorVisit? = nil
    var days: Int = 30
    @State private var showShareSheet = false
    @State private var shareText: String?
    @State private var showPDFShareSheet = false
    @State private var pdfShareURL: URL?
    @State private var isGeneratingPDF = false
    @State private var showPDFError = false
    @State private var pdfErrorMessage = ""
    @State private var aiDraft: HypertensionFollowUpLLMDraft?
    @State private var aiDraftGeneratedAt: Date?
    @State private var isDraftingAI = false
    @State private var showAIDataDisclosure = false
    @State private var showAIError = false
    @State private var aiErrorMessage = ""

    private var report: HypertensionFollowUpReport {
        HypertensionFollowUpReportBuilder.build(store: store, visit: visit, days: days)
    }

    private var aiDraftContextKey: String {
        "hypertension.\(aiDraftVisitKey)"
    }

    private var aiDraftVisitKey: String {
        let visitID = visit?.id.uuidString ?? store.nextDoctorVisit?.id.uuidString ?? "current"
        return visitID
    }

    private var legacyAIDraftCacheKey: String {
        "ai.hypertensionFollowUpDraft.\(aiDraftVisitKey).\(days).\(store.reportDataRevision)"
    }

    private struct CachedAIDraft: Codable {
        let draft: HypertensionFollowUpLLMDraft
        let generatedAt: Date
    }

    var body: some View {
        let report = report

        ScrollView {
            VStack(alignment: .leading, spacing: EditorialSpacing.xl) {
                header(report)
                aiDraftSection
                safetySection(report)
                patientPrepSection(report)
                doctorSummarySection(report)
                questionsSection(report)
                rawDataSection(report)
                disclaimer(report)
            }
            .padding(.horizontal, EditorialSpacing.lg)
            .padding(.vertical, EditorialSpacing.lg)
        }
        .background(AppColor.background)
        .navigationTitle(NSLocalizedString("Hypertension Report", comment: "Hypertension report title"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if AIService.shared.isConfigured {
                    Button {
                        beginAIDraftFlow(report)
                    } label: {
                        Image(systemName: isDraftingAI ? "hourglass" : "sparkles")
                    }
                    .disabled(isDraftingAI)
                    .accessibilityLabel(NSLocalizedString("Refine with AI", comment: "Hypertension report AI action"))
                }

                Button {
                    exportPDF(report)
                } label: {
                    Image(systemName: isGeneratingPDF ? "hourglass" : "doc.richtext")
                }
                .disabled(isGeneratingPDF)
                .accessibilityLabel(NSLocalizedString("Export PDF", comment: "Hypertension report PDF action"))

                Button {
                    shareText = HypertensionFollowUpReportTextExporter.plainText(report, aiDraft: aiDraft)
                    showShareSheet = true
                } label: {
                    Image(systemName: "square.and.arrow.up")
                }
                .accessibilityLabel(NSLocalizedString("Share Report", comment: "Hypertension report share action"))
            }
        }
        .sheet(isPresented: $showShareSheet) {
            if let shareText {
                ShareSheet(activityItems: [shareText])
            }
        }
        .sheet(isPresented: $showPDFShareSheet) {
            if let pdfShareURL {
                ShareSheet(activityItems: [pdfShareURL])
            }
        }
        .alert(NSLocalizedString("Send Structured Report to AI?", comment: "Hypertension report AI disclosure title"), isPresented: $showAIDataDisclosure) {
            Button(NSLocalizedString("Draft with AI", comment: "Hypertension report AI disclosure action")) {
                AIService.shared.hasUserConsent = true
                draftWithAI(report)
            }
            Button(NSLocalizedString("Cancel", comment: ""), role: .cancel) {}
        } message: {
            Text(NSLocalizedString("This sends only the structured hypertension report: BP summaries, adherence counts, symptom summaries, rule-based safety signals, doctor questions, and recent BP rows. It does not send contacts, emergency contact details, raw backups, or unrelated app data.", comment: "Hypertension report AI disclosure detail"))
        }
        .alert(NSLocalizedString("Could not draft AI summary", comment: "Hypertension report AI error title"), isPresented: $showAIError) {
            Button(NSLocalizedString("OK", comment: ""), role: .cancel) {}
        } message: {
            Text(aiErrorMessage)
        }
        .alert(NSLocalizedString("Could not create report", comment: "Hypertension report PDF error title"), isPresented: $showPDFError) {
            Button(NSLocalizedString("OK", comment: ""), role: .cancel) {}
        } message: {
            Text(pdfErrorMessage)
        }
        .onAppear {
            loadCachedAIDraft()
        }
        .onChange(of: store.reportDataRevision) { _ in
            loadCachedAIDraft()
        }
    }

    private func header(_ report: HypertensionFollowUpReport) -> some View {
        VStack(alignment: .leading, spacing: EditorialSpacing.sm) {
            Text(NSLocalizedString("AI follow-up preparation", comment: "Hypertension report eyebrow"))
                .appFont(.micro)
                .foregroundStyle(AppColor.textTertiary)
                .textCase(.uppercase)
            Text(NSLocalizedString("Hypertension follow-up report", comment: "Hypertension report heading"))
                .appFont(.displayTitle)
                .fontWeight(.bold)
                .foregroundStyle(AppColor.textPrimary)
            Text(reportPeriod(report))
                .appFont(.caption)
                .foregroundStyle(AppColor.textSecondary)
        }
    }

    @ViewBuilder
    private var aiDraftSection: some View {
        if isDraftingAI || aiDraft != nil {
            reportSection(NSLocalizedString("AI Draft", comment: "Hypertension report AI section")) {
                if isDraftingAI {
                    HStack(spacing: 10) {
                        ProgressView()
                            .controlSize(.small)
                        Text(NSLocalizedString("Drafting...", comment: "Hypertension report AI loading"))
                            .appFont(.caption)
                            .foregroundStyle(AppColor.textSecondary)
                    }
                    .padding(.vertical, 6)
                } else if let aiDraft {
                    if let generatedAt = aiDraftGeneratedAt {
                        Text(String(format: NSLocalizedString("AI drafted %@", comment: "Hypertension report AI generated metadata"), generatedAt.formatted(date: .omitted, time: .shortened)))
                            .appFont(.caption)
                            .foregroundStyle(AppColor.textSecondary)
                    }
                    if let patientSummary = aiDraft.patientSummary {
                        reportLine(
                            icon: "person.text.rectangle",
                            title: NSLocalizedString("Patient summary", comment: "Hypertension report AI draft label"),
                            detail: patientSummary,
                            tint: AppColor.primary
                        )
                    }
                    if let doctorSummary = aiDraft.doctorSummary {
                        AppDivider()
                        reportLine(
                            icon: "stethoscope",
                            title: NSLocalizedString("Doctor summary", comment: "Hypertension report AI draft label"),
                            detail: doctorSummary,
                            tint: AppColor.primary
                        )
                    }
                    if !aiDraft.questions.isEmpty {
                        AppDivider()
                        VStack(alignment: .leading, spacing: EditorialSpacing.sm) {
                            Text(NSLocalizedString("Questions", comment: "Hypertension report AI draft label"))
                                .appFont(.body)
                                .fontWeight(.semibold)
                                .foregroundStyle(AppColor.textPrimary)
                            ForEach(Array(aiDraft.questions.enumerated()), id: \.offset) { _, question in
                                HStack(alignment: .top, spacing: 8) {
                                    Image(systemName: "questionmark.circle")
                                        .font(.system(size: 14, weight: .regular))
                                        .foregroundStyle(AppColor.primary)
                                        .frame(width: 18)
                                    Text(question)
                                        .appFont(.caption)
                                        .foregroundStyle(AppColor.textPrimary)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func safetySection(_ report: HypertensionFollowUpReport) -> some View {
        if !report.redFlags.isEmpty {
            reportSection(NSLocalizedString("Rule-Based Safety Signals", comment: "Hypertension report section")) {
                ForEach(Array(report.redFlags.enumerated()), id: \.element.id) { index, flag in
                    reportLine(
                        icon: flag.severity == .urgent ? "exclamationmark.triangle.fill" : "exclamationmark.triangle",
                        title: flag.title,
                        detail: flag.detail,
                        tint: flag.severity == .urgent ? AppColor.warning : AppColor.primary
                    )
                    if index < report.redFlags.count - 1 {
                        AppDivider()
                    }
                }
            }
        }
    }

    private func patientPrepSection(_ report: HypertensionFollowUpReport) -> some View {
        reportSection(NSLocalizedString("Patient Prep", comment: "Hypertension report section")) {
            if report.patientInsights.isEmpty {
                Text(NSLocalizedString("No strong pattern detected yet. Keep recording blood pressure, medication intake, and symptoms before the visit.", comment: "Hypertension report empty insights"))
                    .appFont(.caption)
                    .foregroundStyle(AppColor.textSecondary)
            } else {
                ForEach(Array(report.patientInsights.enumerated()), id: \.element.id) { index, insight in
                    reportLine(
                        icon: iconName(for: insight.severity),
                        title: insight.title,
                        detail: insight.detail,
                        tint: tint(for: insight.severity)
                    )
                    if index < report.patientInsights.count - 1 {
                        AppDivider()
                    }
                }
            }
        }
    }

    private func doctorSummarySection(_ report: HypertensionFollowUpReport) -> some View {
        reportSection(NSLocalizedString("Doctor-Facing Summary", comment: "Hypertension report section")) {
            ForEach(Array(report.doctorSummaryLines.enumerated()), id: \.offset) { index, line in
                Text(line)
                    .appFont(.caption)
                    .foregroundStyle(AppColor.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                if index < report.doctorSummaryLines.count - 1 {
                    AppDivider()
                }
            }
        }
    }

    private func questionsSection(_ report: HypertensionFollowUpReport) -> some View {
        reportSection(NSLocalizedString("Questions for Doctor", comment: "Hypertension report section")) {
            ForEach(Array(report.doctorQuestions.enumerated()), id: \.element.id) { index, question in
                reportLine(
                    icon: "questionmark.circle",
                    title: question.prompt,
                    detail: question.reason,
                    tint: AppColor.primary
                )
                if index < report.doctorQuestions.count - 1 {
                    AppDivider()
                }
            }
        }
    }

    private func rawDataSection(_ report: HypertensionFollowUpReport) -> some View {
        reportSection(NSLocalizedString("Blood Pressure Appendix", comment: "Hypertension report section")) {
            if report.rawBloodPressureRows.isEmpty {
                Text(NSLocalizedString("No blood pressure readings in this report period.", comment: "Hypertension report empty raw data"))
                    .appFont(.caption)
                    .foregroundStyle(AppColor.textSecondary)
            } else {
                ForEach(Array(report.rawBloodPressureRows.enumerated()), id: \.element.id) { index, row in
                    HStack(alignment: .firstTextBaseline) {
                        Text(row.date, format: .dateTime.month().day().hour().minute())
                            .appFontNumeric(.caption)
                            .foregroundStyle(AppColor.textSecondary)
                        Spacer(minLength: EditorialSpacing.md)
                        Text(rawBPText(row))
                            .appFontNumeric(.body)
                            .fontWeight(.semibold)
                            .foregroundStyle(AppColor.textPrimary)
                    }
                    if let note = row.note, !note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text(note)
                            .appFont(.caption)
                            .foregroundStyle(AppColor.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if index < report.rawBloodPressureRows.count - 1 {
                        AppDivider()
                    }
                }
            }
        }
    }

    private func disclaimer(_ report: HypertensionFollowUpReport) -> some View {
        Text(report.disclaimer)
            .appFont(.caption)
            .foregroundStyle(AppColor.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func reportSection<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: EditorialSpacing.md) {
            Text(title.uppercased())
                .appFont(.micro)
                .foregroundStyle(AppColor.textPrimary)
                .tracking(0.7)
            AppDivider()
            content()
        }
    }

    private func reportLine(icon: String, title: String, detail: String?, tint: Color) -> some View {
        HStack(alignment: .top, spacing: EditorialSpacing.sm) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .regular))
                .foregroundStyle(tint)
                .frame(width: 24, alignment: .center)
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: EditorialSpacing.xs) {
                Text(title)
                    .appFont(.body)
                    .fontWeight(.semibold)
                    .foregroundStyle(AppColor.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                if let detail, !detail.isEmpty {
                    Text(detail)
                        .appFont(.caption)
                        .foregroundStyle(AppColor.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private func reportPeriod(_ report: HypertensionFollowUpReport) -> String {
        let start = report.periodStart.formatted(date: .abbreviated, time: .omitted)
        let end = report.periodEnd.formatted(date: .abbreviated, time: .omitted)
        return String(format: NSLocalizedString("%@ to %@", comment: "Hypertension report period"), start, end)
    }

    private func rawBPText(_ row: HypertensionFollowUpReport.RawBloodPressureRow) -> String {
        if let diastolic = row.diastolic {
            return "\(row.systolic)/\(diastolic) mmHg"
        }
        return "\(row.systolic) mmHg"
    }

    private func iconName(for severity: AgentInsightSeverity) -> String {
        switch severity {
        case .information: return "info.circle"
        case .caution: return "exclamationmark.circle"
        case .urgent: return "exclamationmark.triangle.fill"
        }
    }

    private func tint(for severity: AgentInsightSeverity) -> Color {
        switch severity {
        case .information: return AppColor.primary
        case .caution, .urgent: return AppColor.warning
        }
    }

    private func exportPDF(_ report: HypertensionFollowUpReport) {
        guard !isGeneratingPDF else { return }
        isGeneratingPDF = true
        defer { isGeneratingPDF = false }

        do {
            pdfShareURL = try HypertensionFollowUpReportPDFExporter.generate(report: report, aiDraft: aiDraft)
            showPDFShareSheet = true
            Haptics.success()
        } catch {
            pdfErrorMessage = error.localizedDescription
            showPDFError = true
            Haptics.notification(.warning)
        }
    }

    private func beginAIDraftFlow(_ report: HypertensionFollowUpReport) {
        guard AIService.shared.isConfigured else { return }
        if !AIService.shared.hasUserConsent {
            showAIDataDisclosure = true
            return
        }
        draftWithAI(report)
    }

    private func draftWithAI(_ report: HypertensionFollowUpReport) {
        guard !isDraftingAI else { return }
        isDraftingAI = true
        let context = HypertensionFollowUpLLMContext(report: report)

        Task {
            do {
                let draft = try await AIService.shared.draftHypertensionFollowUpReport(context)
                await MainActor.run {
                    cacheAIDraft(draft)
                    isDraftingAI = false
                    Haptics.success()
                }
            } catch {
                await MainActor.run {
                    isDraftingAI = false
                    aiErrorMessage = error.localizedDescription
                    showAIError = true
                    Haptics.notification(.warning)
                }
            }
        }
    }

    private func loadCachedAIDraft() {
        if let record = store.hypertensionAIDraft(
            contextKey: aiDraftContextKey,
            days: days,
            dataRevision: store.reportDataRevision
        ) {
            aiDraft = record.draft
            aiDraftGeneratedAt = record.generatedAt
            return
        }

        if let data = UserDefaults.standard.data(forKey: legacyAIDraftCacheKey),
           let cached = try? JSONDecoder().decode(CachedAIDraft.self, from: data) {
            store.saveHypertensionAIDraft(
                cached.draft,
                contextKey: aiDraftContextKey,
                days: days,
                dataRevision: store.reportDataRevision,
                generatedAt: cached.generatedAt
            )
            aiDraft = cached.draft
            aiDraftGeneratedAt = cached.generatedAt
            return
        }

        aiDraft = nil
        aiDraftGeneratedAt = nil
    }

    private func cacheAIDraft(_ draft: HypertensionFollowUpLLMDraft) {
        let generatedAt = Date()
        store.saveHypertensionAIDraft(
            draft,
            contextKey: aiDraftContextKey,
            days: days,
            dataRevision: store.reportDataRevision,
            generatedAt: generatedAt
        )
        aiDraft = draft
        aiDraftGeneratedAt = generatedAt
    }
}

#Preview {
    NavigationStack {
        HypertensionFollowUpReportView()
            .environmentObject(DataStore())
    }
}
