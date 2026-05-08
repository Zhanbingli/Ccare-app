import SwiftUI
import UIKit

struct DiabetesFollowUpReportView: View {
    @EnvironmentObject var store: DataStore
    var visit: DoctorVisit? = nil
    var days: Int = 30
    @State private var showShareSheet = false
    @State private var shareText: String?
    @State private var showGlucoseSheet = false
    @State private var showSymptomSheet = false
    @State private var showCopyConfirmation = false

    private var report: DiabetesFollowUpReport {
        DiabetesFollowUpReportBuilder.build(store: store, visit: visit, days: days)
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
                    copyDoctorSummary(report)
                } label: {
                    Image(systemName: "doc.on.doc")
                }
                .accessibilityLabel(NSLocalizedString("Copy Doctor Summary", comment: "Diabetes report copy action"))

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
        .sheet(isPresented: $showGlucoseSheet) {
            AddMeasurementView(initialType: .bloodGlucose) { measurement in
                store.addMeasurement(measurement)
                Haptics.success()
            }
            .presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $showSymptomSheet) {
            SymptomQuickLogSheet()
                .environmentObject(store)
        }
        .alert(NSLocalizedString("Copied", comment: "Diabetes report copy confirmation"), isPresented: $showCopyConfirmation) {
            Button(NSLocalizedString("OK", comment: ""), role: .cancel) {}
        } message: {
            Text(NSLocalizedString("Doctor one-page summary copied.", comment: "Diabetes report copy confirmation detail"))
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

    @ViewBuilder
    private func visitDayChecklistSection(_ report: DiabetesFollowUpReport) -> some View {
        if let activeVisit = visit ?? store.nextDoctorVisit,
           Calendar.current.isDateInToday(activeVisit.scheduledDate),
           !activeVisit.isCompleted {
            reportSection(NSLocalizedString("Visit Day Checklist", comment: "Diabetes report visit day section")) {
                let medicationStatus = todayMedicationStatus()
                visitDayActionRow(
                    icon: medicationStatus.isReady ? "checkmark" : "pills",
                    title: NSLocalizedString("Today's diabetes medication record", comment: "Diabetes report visit day item"),
                    detail: medicationStatus.detail,
                    isReady: medicationStatus.isReady
                ) {
                    NavigationLink {
                        MedicationsView()
                    } label: {
                        Text(NSLocalizedString("Open", comment: "Diabetes report row action"))
                            .appFont(.caption)
                            .fontWeight(.semibold)
                    }
                }

                AppDivider()

                let glucoseStatus = todayGlucoseStatus()
                visitDayActionRow(
                    icon: glucoseStatus.isReady ? "checkmark" : "drop",
                    title: NSLocalizedString("Today's glucose", comment: "Diabetes report visit day item"),
                    detail: glucoseStatus.detail,
                    isReady: glucoseStatus.isReady
                ) {
                    Button {
                        showGlucoseSheet = true
                    } label: {
                        Text(NSLocalizedString("Log", comment: "Diabetes report row action"))
                            .appFont(.caption)
                            .fontWeight(.semibold)
                    }
                    .buttonStyle(.borderless)
                }

                AppDivider()

                let symptomStatus = todaySymptomStatus()
                visitDayActionRow(
                    icon: symptomStatus.isReady ? "checkmark" : "text.badge.plus",
                    title: NSLocalizedString("New symptoms today", comment: "Diabetes report visit day item"),
                    detail: symptomStatus.detail,
                    isReady: symptomStatus.isReady
                ) {
                    Button {
                        showSymptomSheet = true
                    } label: {
                        Text(NSLocalizedString("Add", comment: "Diabetes report row action"))
                            .appFont(.caption)
                            .fontWeight(.semibold)
                    }
                    .buttonStyle(.borderless)
                }

                AppDivider()

                EditorialButton(NSLocalizedString("Copy Doctor Summary", comment: "Diabetes report visit day action"), systemImage: "doc.on.doc", kind: .secondary) {
                    copyDoctorSummary(report)
                }
            }
        }
    }

    private func doctorOnePageSection(_ report: DiabetesFollowUpReport) -> some View {
        reportSection(NSLocalizedString("Doctor One-Page Summary", comment: "Diabetes report section")) {
            VStack(alignment: .leading, spacing: EditorialSpacing.sm) {
                ForEach(Array(doctorScanLines(report).enumerated()), id: \.offset) { index, line in
                    compactLine(line)
                    if index < doctorScanLines(report).count - 1 {
                        AppDivider()
                    }
                }
            }

            if !report.symptoms.summaries.isEmpty {
                AppDivider()
                VStack(alignment: .leading, spacing: EditorialSpacing.sm) {
                    Text(NSLocalizedString("Symptom Context", comment: "Diabetes report subsection"))
                        .appFont(.body)
                        .fontWeight(.semibold)
                        .foregroundStyle(AppColor.textPrimary)
                    ForEach(Array(report.symptoms.summaries.prefix(3).enumerated()), id: \.offset) { _, line in
                        compactLine(line, icon: "quote.bubble")
                    }
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
        DisclosureGroup {
            VStack(alignment: .leading, spacing: EditorialSpacing.md) {
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
            .padding(.top, EditorialSpacing.sm)
        } label: {
            HStack(alignment: .firstTextBaseline) {
                Text(NSLocalizedString("Glucose Appendix", comment: "Diabetes report section"))
                    .appFont(.body)
                    .fontWeight(.semibold)
                    .foregroundStyle(AppColor.textPrimary)
                Spacer(minLength: EditorialSpacing.md)
                Text(String(format: NSLocalizedString("%lld rows", comment: "Diabetes report appendix count"), Int64(report.rawGlucoseRows.count)))
                    .appFontNumeric(.caption)
                    .foregroundStyle(AppColor.textSecondary)
            }
        }
        .tint(AppColor.primary)
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

    private func compactLine(_ text: String, icon: String? = nil) -> some View {
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

    private func doctorScanLines(_ report: DiabetesFollowUpReport) -> [String] {
        var lines: [String] = [
            String(format: NSLocalizedString("Average home glucose %@ from %lld readings.", comment: "Diabetes report one-page line"), formattedGlucoseAverage(report.glucose.averageGlucose), Int64(report.glucose.totalReadings)),
            String(format: NSLocalizedString("Morning average %@; evening average %@.", comment: "Diabetes report one-page line"), formattedGlucoseAverage(report.glucose.morningAverageGlucose), formattedGlucoseAverage(report.glucose.eveningAverageGlucose)),
            String(format: NSLocalizedString("Low / high glucose readings: %lld below 70, %lld at or above 240.", comment: "Diabetes report one-page line"), Int64(report.glucose.lowReadingsCount), Int64(report.glucose.highReadingsCount)),
            String(format: NSLocalizedString("Antidiabetic adherence %@; %lld missed scheduled doses.", comment: "Diabetes report one-page line"), adherenceMetricValue(report), Int64(report.adherence.missedDoseCount))
        ]

        if let worstTime = report.adherence.worstMissedTimeLabel {
            lines.append(String(format: NSLocalizedString("Missed doses clustered around %@.", comment: "Diabetes report one-page line"), worstTime))
        }
        if let gap = report.glucose.measurementGapDays, gap >= 7 {
            lines.append(String(format: NSLocalizedString("Latest home glucose record is %lld days old.", comment: "Diabetes report one-page line"), Int64(gap)))
        }
        if !report.redFlags.isEmpty {
            lines.append(String(format: NSLocalizedString("%lld rule-based safety signals require review.", comment: "Diabetes report one-page line"), Int64(report.redFlags.count)))
        }

        return lines
    }

    private func formattedGlucoseAverage(_ value: Double?) -> String {
        value.map { DiabetesFollowUpReportBuilder.formattedGlucose($0) } ?? NSLocalizedString("not enough data", comment: "Diabetes report missing value")
    }

    private func adherenceMetricValue(_ report: DiabetesFollowUpReport) -> String {
        report.adherence.adherenceRate.map { "\(Int(($0 * 100).rounded()))%" } ?? NSLocalizedString("not enough data", comment: "Diabetes report missing value")
    }

    private func todayMedicationStatus() -> (detail: String, isReady: Bool) {
        let meds = store.medications.filter { $0.category == .antidiabetic && $0.isAsNeeded != true }
        guard !meds.isEmpty else {
            return (
                NSLocalizedString("No diabetes medication is listed yet.", comment: "Diabetes report visit day medication status"),
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
                NSLocalizedString("No diabetes medication dose is due yet today.", comment: "Diabetes report visit day medication status"),
                true
            )
        }
        return (
            String(format: NSLocalizedString("%lld of %lld due doses recorded as taken today.", comment: "Diabetes report visit day medication status"), Int64(counts.taken), Int64(counts.total)),
            counts.taken >= counts.total
        )
    }

    private func todayGlucoseStatus() -> (detail: String, isReady: Bool) {
        let readings = store.measurements
            .filter { $0.type == .bloodGlucose && Calendar.current.isDateInToday($0.date) }
            .sorted { $0.date > $1.date }

        guard let latest = readings.first else {
            return (
                NSLocalizedString("No glucose reading logged today.", comment: "Diabetes report visit day glucose status"),
                false
            )
        }

        return (
            String(format: NSLocalizedString("Latest today: %@ at %@", comment: "Diabetes report visit day glucose status"), DiabetesFollowUpReportBuilder.formattedGlucose(latest.value), latest.date.formatted(date: .omitted, time: .shortened)),
            true
        )
    }

    private func todaySymptomStatus() -> (detail: String, isReady: Bool) {
        let count = store.symptomEntries.filter { Calendar.current.isDateInToday($0.date) }.count
        guard count > 0 else {
            return (
                NSLocalizedString("No new symptom logged today.", comment: "Diabetes report visit day symptom status"),
                false
            )
        }
        return (
            String(format: NSLocalizedString("%lld symptom entries logged today.", comment: "Diabetes report visit day symptom status"), Int64(count)),
            true
        )
    }

    private func reportPeriod(_ report: DiabetesFollowUpReport) -> String {
        let start = report.periodStart.formatted(date: .abbreviated, time: .omitted)
        let end = report.periodEnd.formatted(date: .abbreviated, time: .omitted)
        return String(format: NSLocalizedString("%@ to %@", comment: "Diabetes report period"), start, end)
    }

    private func copyDoctorSummary(_ report: DiabetesFollowUpReport) {
        UIPasteboard.general.string = DiabetesFollowUpReportTextExporter.doctorOnePageText(report)
        showCopyConfirmation = true
        Haptics.success()
    }
}

#Preview {
    NavigationStack {
        DiabetesFollowUpReportView()
            .environmentObject(DataStore())
    }
}
