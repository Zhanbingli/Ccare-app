import SwiftUI

struct DiabetesFollowUpReportView: View {
    @EnvironmentObject var store: DataStore
    var visit: DoctorVisit? = nil
    var days: Int = 30
    @State private var showShareSheet = false
    @State private var shareText: String?

    private var report: DiabetesFollowUpReport {
        DiabetesFollowUpReportBuilder.build(store: store, visit: visit, days: days)
    }

    var body: some View {
        let report = report

        ScrollView {
            VStack(alignment: .leading, spacing: EditorialSpacing.xl) {
                header(report)
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
        .navigationTitle(NSLocalizedString("Diabetes Report", comment: "Diabetes report title"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    shareText = DiabetesFollowUpReportTextExporter.plainText(report)
                    showShareSheet = true
                } label: {
                    Image(systemName: "square.and.arrow.up")
                }
                .accessibilityLabel(NSLocalizedString("Share Report", comment: "Diabetes report share action"))
            }
        }
        .sheet(isPresented: $showShareSheet) {
            if let shareText {
                ShareSheet(activityItems: [shareText])
            }
        }
    }

    private func header(_ report: DiabetesFollowUpReport) -> some View {
        VStack(alignment: .leading, spacing: EditorialSpacing.sm) {
            Text(NSLocalizedString("AI follow-up preparation", comment: "Diabetes report eyebrow"))
                .appFont(.micro)
                .foregroundStyle(AppColor.textTertiary)
                .textCase(.uppercase)
            Text(NSLocalizedString("Diabetes follow-up report", comment: "Diabetes report heading"))
                .appFont(.displayTitle)
                .fontWeight(.bold)
                .foregroundStyle(AppColor.textPrimary)
            Text(reportPeriod(report))
                .appFont(.caption)
                .foregroundStyle(AppColor.textSecondary)
        }
    }

    @ViewBuilder
    private func safetySection(_ report: DiabetesFollowUpReport) -> some View {
        if !report.redFlags.isEmpty {
            reportSection(NSLocalizedString("Rule-Based Safety Signals", comment: "Diabetes report section")) {
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

    private func patientPrepSection(_ report: DiabetesFollowUpReport) -> some View {
        reportSection(NSLocalizedString("Patient Prep", comment: "Diabetes report section")) {
            if report.patientInsights.isEmpty {
                Text(NSLocalizedString("No strong pattern detected yet. Keep recording glucose, diabetes medication intake, and symptoms before the visit.", comment: "Diabetes report empty insights"))
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

    private func doctorSummarySection(_ report: DiabetesFollowUpReport) -> some View {
        reportSection(NSLocalizedString("Doctor-Facing Summary", comment: "Diabetes report section")) {
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

    private func questionsSection(_ report: DiabetesFollowUpReport) -> some View {
        reportSection(NSLocalizedString("Questions for Doctor", comment: "Diabetes report section")) {
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

    private func rawDataSection(_ report: DiabetesFollowUpReport) -> some View {
        reportSection(NSLocalizedString("Glucose Appendix", comment: "Diabetes report section")) {
            if report.rawGlucoseRows.isEmpty {
                Text(NSLocalizedString("No glucose readings in this report period.", comment: "Diabetes report empty raw data"))
                    .appFont(.caption)
                    .foregroundStyle(AppColor.textSecondary)
            } else {
                ForEach(Array(report.rawGlucoseRows.enumerated()), id: \.element.id) { index, row in
                    HStack(alignment: .firstTextBaseline) {
                        Text(row.date, format: .dateTime.month().day().hour().minute())
                            .appFontNumeric(.caption)
                            .foregroundStyle(AppColor.textSecondary)
                        Spacer(minLength: EditorialSpacing.md)
                        Text(DiabetesFollowUpReportBuilder.formattedGlucose(row.glucose))
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
                    if index < report.rawGlucoseRows.count - 1 {
                        AppDivider()
                    }
                }
            }
        }
    }

    private func disclaimer(_ report: DiabetesFollowUpReport) -> some View {
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

    private func reportPeriod(_ report: DiabetesFollowUpReport) -> String {
        let start = report.periodStart.formatted(date: .abbreviated, time: .omitted)
        let end = report.periodEnd.formatted(date: .abbreviated, time: .omitted)
        return String(format: NSLocalizedString("%@ to %@", comment: "Diabetes report period"), start, end)
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
}

#Preview {
    NavigationStack {
        DiabetesFollowUpReportView()
            .environmentObject(DataStore())
    }
}
