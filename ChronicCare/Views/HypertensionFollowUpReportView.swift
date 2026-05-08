import SwiftUI
import UIKit

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
    @State private var showBloodPressureSheet = false
    @State private var showSymptomSheet = false
    @State private var showCopyConfirmation = false

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
                visitDayChecklistSection(report)
                safetySection(report)
                doctorOnePageSection(report)
                questionsSection(report)
                patientPrepNotesSection
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
                    copyDoctorSummary(report)
                } label: {
                    Image(systemName: "doc.on.doc")
                }
                .accessibilityLabel(NSLocalizedString("Copy Doctor Summary", comment: "Hypertension report copy action"))

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
        .sheet(isPresented: $showBloodPressureSheet) {
            AddMeasurementView(initialType: .bloodPressure) { measurement in
                store.addMeasurement(measurement)
                Haptics.success()
            }
            .presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $showSymptomSheet) {
            SymptomQuickLogSheet()
                .environmentObject(store)
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
        .alert(NSLocalizedString("Copied", comment: "Hypertension report copy confirmation"), isPresented: $showCopyConfirmation) {
            Button(NSLocalizedString("OK", comment: ""), role: .cancel) {}
        } message: {
            Text(NSLocalizedString("Doctor one-page summary copied.", comment: "Hypertension report copy confirmation detail"))
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
    private var patientPrepNotesSection: some View {
        if isDraftingAI || aiDraft?.patientSummary != nil {
            reportSection(NSLocalizedString("Patient Prep Notes", comment: "Hypertension report AI patient section")) {
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
                }
            }
        }
    }

    @ViewBuilder
    private func visitDayChecklistSection(_ report: HypertensionFollowUpReport) -> some View {
        if let activeVisit = visit ?? store.nextDoctorVisit,
           Calendar.current.isDateInToday(activeVisit.scheduledDate),
           !activeVisit.isCompleted {
            reportSection(NSLocalizedString("Visit Day Checklist", comment: "Hypertension report visit day section")) {
                let medicationStatus = todayMedicationStatus()
                visitDayActionRow(
                    icon: medicationStatus.isReady ? "checkmark" : "pills",
                    title: NSLocalizedString("Today's medication record", comment: "Hypertension report visit day item"),
                    detail: medicationStatus.detail,
                    isReady: medicationStatus.isReady
                ) {
                    NavigationLink {
                        MedicationsView()
                    } label: {
                        Text(NSLocalizedString("Open", comment: "Hypertension report row action"))
                            .appFont(.caption)
                            .fontWeight(.semibold)
                    }
                }

                AppDivider()

                let bpStatus = todayBloodPressureStatus()
                visitDayActionRow(
                    icon: bpStatus.isReady ? "checkmark" : "waveform.path.ecg",
                    title: NSLocalizedString("Today's blood pressure", comment: "Hypertension report visit day item"),
                    detail: bpStatus.detail,
                    isReady: bpStatus.isReady
                ) {
                    Button {
                        showBloodPressureSheet = true
                    } label: {
                        Text(NSLocalizedString("Log", comment: "Hypertension report row action"))
                            .appFont(.caption)
                            .fontWeight(.semibold)
                    }
                    .buttonStyle(.borderless)
                }

                AppDivider()

                let symptomStatus = todaySymptomStatus()
                visitDayActionRow(
                    icon: symptomStatus.isReady ? "checkmark" : "text.badge.plus",
                    title: NSLocalizedString("New symptoms today", comment: "Hypertension report visit day item"),
                    detail: symptomStatus.detail,
                    isReady: symptomStatus.isReady
                ) {
                    Button {
                        showSymptomSheet = true
                    } label: {
                        Text(NSLocalizedString("Add", comment: "Hypertension report row action"))
                            .appFont(.caption)
                            .fontWeight(.semibold)
                    }
                    .buttonStyle(.borderless)
                }

                AppDivider()

                HStack(spacing: EditorialSpacing.sm) {
                    EditorialButton(NSLocalizedString("Copy Doctor Summary", comment: "Hypertension report visit day action"), systemImage: "doc.on.doc", kind: .secondary) {
                        copyDoctorSummary(report)
                    }
                    EditorialButton(NSLocalizedString("Export PDF", comment: "Hypertension report PDF action"), systemImage: "doc.richtext", kind: .secondary) {
                        exportPDF(report)
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

    private func doctorOnePageSection(_ report: HypertensionFollowUpReport) -> some View {
        reportSection(NSLocalizedString("Doctor One-Page Summary", comment: "Hypertension report section")) {
            VStack(alignment: .leading, spacing: EditorialSpacing.sm) {
                ForEach(Array(doctorScanLines(report).enumerated()), id: \.offset) { index, line in
                    compactBullet(line)
                    if index < doctorScanLines(report).count - 1 {
                        AppDivider()
                    }
                }
            }

            if !report.symptoms.summaries.isEmpty {
                AppDivider()
                VStack(alignment: .leading, spacing: EditorialSpacing.sm) {
                    Text(NSLocalizedString("Symptom Context", comment: "Hypertension report subsection"))
                        .appFont(.body)
                        .fontWeight(.semibold)
                        .foregroundStyle(AppColor.textPrimary)
                    ForEach(Array(report.symptoms.summaries.prefix(3).enumerated()), id: \.offset) { _, line in
                        compactBullet(line, icon: "quote.bubble")
                    }
                }
            }
        }
    }

    private func questionsSection(_ report: HypertensionFollowUpReport) -> some View {
        reportSection(NSLocalizedString("Questions for Doctor", comment: "Hypertension report section")) {
            if let aiDraft, !aiDraft.questions.isEmpty {
                if let generatedAt = aiDraftGeneratedAt {
                    Text(String(format: NSLocalizedString("AI drafted %@", comment: "Hypertension report AI generated metadata"), generatedAt.formatted(date: .omitted, time: .shortened)))
                        .appFont(.caption)
                        .foregroundStyle(AppColor.textSecondary)
                }
                ForEach(Array(aiDraft.questions.enumerated()), id: \.offset) { index, question in
                    reportLine(
                        icon: "questionmark.circle",
                        title: question,
                        detail: nil,
                        tint: AppColor.primary
                    )
                    if index < aiDraft.questions.count - 1 {
                        AppDivider()
                    }
                }
            } else {
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
    }

    private func rawDataSection(_ report: HypertensionFollowUpReport) -> some View {
        DisclosureGroup {
            VStack(alignment: .leading, spacing: EditorialSpacing.md) {
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
            .padding(.top, EditorialSpacing.sm)
        } label: {
            HStack(alignment: .firstTextBaseline) {
                Text(NSLocalizedString("Blood Pressure Appendix", comment: "Hypertension report section"))
                    .appFont(.body)
                    .fontWeight(.semibold)
                    .foregroundStyle(AppColor.textPrimary)
                Spacer(minLength: EditorialSpacing.md)
                Text(String(format: NSLocalizedString("%lld rows", comment: "Hypertension report appendix count"), Int64(report.rawBloodPressureRows.count)))
                    .appFontNumeric(.caption)
                    .foregroundStyle(AppColor.textSecondary)
            }
        }
        .tint(AppColor.primary)
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

    private func compactBullet(_ text: String, icon: String? = nil) -> some View {
        HStack(alignment: .top, spacing: EditorialSpacing.sm) {
            if let icon {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(AppColor.primary)
                    .frame(width: 18, height: 20)
            }
            Text(text)
                .appFont(.body)
                .foregroundStyle(AppColor.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func visitDayActionRow<Trailing: View>(
        icon: String,
        title: String,
        detail: String,
        isReady: Bool,
        @ViewBuilder trailing: () -> Trailing
    ) -> some View {
        HStack(alignment: .top, spacing: EditorialSpacing.sm) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .regular))
                .foregroundStyle(isReady ? AppColor.success : AppColor.primary)
                .frame(width: 24, alignment: .center)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: EditorialSpacing.xs) {
                Text(title)
                    .appFont(.body)
                    .fontWeight(.semibold)
                    .foregroundStyle(AppColor.textPrimary)
                Text(detail)
                    .appFont(.caption)
                    .foregroundStyle(AppColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: EditorialSpacing.sm)

            trailing()
                .foregroundStyle(AppColor.primary)
        }
        .padding(.vertical, EditorialSpacing.xs)
    }

    private func doctorScanLines(_ report: HypertensionFollowUpReport) -> [String] {
        var lines: [String] = [
            String(format: NSLocalizedString("Average home BP %@ from %lld readings; %lld above target.", comment: "Hypertension report one-page line"), HypertensionFollowUpReportBuilder.formatAverageBP(report.bloodPressure.averageSystolic, report.bloodPressure.averageDiastolic), Int64(report.bloodPressure.totalReadings), Int64(report.bloodPressure.aboveTargetCount)),
            String(format: NSLocalizedString("Morning average %@; evening average %@.", comment: "Hypertension report one-page line"), HypertensionFollowUpReportBuilder.formatAverageBP(report.bloodPressure.morningAverageSystolic, report.bloodPressure.morningAverageDiastolic), HypertensionFollowUpReportBuilder.formatAverageBP(report.bloodPressure.eveningAverageSystolic, report.bloodPressure.eveningAverageDiastolic)),
            String(format: NSLocalizedString("Antihypertensive adherence %@; %lld missed scheduled doses.", comment: "Hypertension report one-page line"), adherenceMetricValue(report), Int64(report.adherence.missedDoseCount))
        ]

        if let worstTime = report.adherence.worstMissedTimeLabel {
            lines.append(String(format: NSLocalizedString("Missed doses clustered around %@.", comment: "Hypertension report one-page line"), worstTime))
        }
        if let gap = report.bloodPressure.measurementGapDays, gap >= 7 {
            lines.append(String(format: NSLocalizedString("Latest home BP record is %lld days old.", comment: "Hypertension report one-page line"), Int64(gap)))
        }
        if !report.redFlags.isEmpty {
            lines.append(String(format: NSLocalizedString("%lld rule-based safety signals require review.", comment: "Hypertension report one-page line"), Int64(report.redFlags.count)))
        }

        return lines
    }

    private func adherenceMetricValue(_ report: HypertensionFollowUpReport) -> String {
        report.adherence.adherenceRate.map { "\(Int(($0 * 100).rounded()))%" } ?? NSLocalizedString("not enough data", comment: "Hypertension report missing value")
    }

    private func todayMedicationStatus() -> (detail: String, isReady: Bool) {
        let meds = store.medications.filter { $0.category == .antihypertensive && $0.isAsNeeded != true }
        guard !meds.isEmpty else {
            return (
                NSLocalizedString("No antihypertensive medication is listed yet.", comment: "Hypertension report visit day medication status"),
                false
            )
        }

        let counts = AdherenceCalculator.dayCounts(
            dayKey: Calendar.current.startOfDay(for: Date()),
            medications: meds,
            logs: store.intakeLogs
        )
        if counts.total == 0 {
            return (
                NSLocalizedString("No antihypertensive dose is due yet today.", comment: "Hypertension report visit day medication status"),
                true
            )
        }
        return (
            String(format: NSLocalizedString("%lld of %lld due doses recorded as taken today.", comment: "Hypertension report visit day medication status"), Int64(counts.taken), Int64(counts.total)),
            counts.taken >= counts.total
        )
    }

    private func todayBloodPressureStatus() -> (detail: String, isReady: Bool) {
        let readings = store.measurements
            .filter { $0.type == .bloodPressure && Calendar.current.isDateInToday($0.date) }
            .sorted { $0.date > $1.date }

        guard let latest = readings.first else {
            return (
                NSLocalizedString("No blood pressure reading logged today.", comment: "Hypertension report visit day BP status"),
                false
            )
        }

        return (
            String(format: NSLocalizedString("Latest today: %@ at %@", comment: "Hypertension report visit day BP status"), HypertensionFollowUpReportBuilder.formatBP(latest), latest.date.formatted(date: .omitted, time: .shortened)),
            true
        )
    }

    private func todaySymptomStatus() -> (detail: String, isReady: Bool) {
        let count = store.symptomEntries.filter { Calendar.current.isDateInToday($0.date) }.count
        guard count > 0 else {
            return (
                NSLocalizedString("No new symptom logged today.", comment: "Hypertension report visit day symptom status"),
                false
            )
        }
        return (
            String(format: NSLocalizedString("%lld symptom entries logged today.", comment: "Hypertension report visit day symptom status"), Int64(count)),
            true
        )
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

    private func copyDoctorSummary(_ report: HypertensionFollowUpReport) {
        UIPasteboard.general.string = HypertensionFollowUpReportTextExporter.doctorOnePageText(report, aiDraft: aiDraft)
        showCopyConfirmation = true
        Haptics.success()
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
