import SwiftUI

struct HypertensionFollowUpReportView: View {
    @EnvironmentObject var store: DataStore
    var visit: DoctorVisit? = nil
    var days: Int = 30

    private var report: HypertensionFollowUpReport {
        HypertensionFollowUpReportBuilder.build(store: store, visit: visit, days: days)
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
        .navigationTitle(NSLocalizedString("Hypertension Report", comment: "Hypertension report title"))
        .navigationBarTitleDisplayMode(.inline)
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
}

#Preview {
    NavigationStack {
        HypertensionFollowUpReportView()
            .environmentObject(DataStore())
    }
}
