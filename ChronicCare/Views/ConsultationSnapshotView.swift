import SwiftUI
import Charts

/// Consultation Snapshot — a doctor-first view of the patient-side data
/// that the hospital's information system doesn't have.
///
/// Design goal: a doctor should be able to scan this in ≤10 seconds and
/// form the same baseline understanding as from 5 minutes of questioning.
/// Priority: real medication list (all sources) → adherence gaps → home
/// measurements trend → symptom timeline between visits.
struct ConsultationSnapshotView: View {
    @EnvironmentObject var store: DataStore
    var visit: DoctorVisit? = nil

    @State private var showEmergencyEdit = false
    @State private var showSymptomEditor: SymptomEntry?
    @State private var showNewSymptom = false
    @State private var showMeasurementManager = false
    @State private var cachedSummary: DoctorReportSummary?
    @State private var pdfShareURL: URL?
    @State private var showPDFShare = false
    @State private var isGeneratingPDF = false
    @State private var pdfErrorMessage: String?
    @State private var showPDFError = false

    private let daysWindow: Int = 30

    private struct PatientBriefingItem: Identifiable {
        let id: String
        let title: String
        let detail: String
        let systemImage: String
        let tint: Color
    }

    private struct DoctorQuestion: Identifiable {
        let id: String
        let question: String
        let detail: String?
        let systemImage: String
        let tint: Color
    }

    private var snapshotVisit: DoctorVisit? {
        visit ?? store.nextDoctorVisit
    }

    private var doctorSummary: DoctorReportSummary {
        DoctorReportSummaryBuilder.build(store: store, days: daysWindow, visit: snapshotVisit)
    }

    var body: some View {
        let summary = cachedSummary ?? doctorSummary

        ScrollView {
            VStack(alignment: .leading, spacing: EditorialSpacing.xl) {
                header
                patientBriefingSection(summary: summary)
                doctorQuestionsSection(summary: summary)
                snapshotSummaryStrip(summary: summary)
                visitPrepSection(summary: summary)
                allergiesWarning(summary: summary)
                medicationsSection(summary: summary)
                adherenceSection(summary: summary)
                measurementsSection(summary: summary)
                symptomsSection
                emergencyFooter
                exportSection(summary: summary)
            }
            .padding(.horizontal, EditorialSpacing.lg)
            .padding(.vertical, EditorialSpacing.lg)
        }
        .background(AppColor.background)
        .navigationTitle(NSLocalizedString("Consultation Snapshot", comment: ""))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button {
                    exportPDFReport()
                } label: {
                    Image(systemName: isGeneratingPDF ? "hourglass" : "doc.richtext")
                }
                .disabled(isGeneratingPDF)
                .accessibilityLabel(NSLocalizedString("Export doctor PDF", comment: "Consultation snapshot PDF export action"))

                Menu {
                    Button {
                        showNewSymptom = true
                    } label: {
                        Label(NSLocalizedString("Log Symptom", comment: ""), systemImage: "heart.text.square")
                    }
                    Button {
                        showEmergencyEdit = true
                    } label: {
                        Label(NSLocalizedString("Edit Emergency Info", comment: ""), systemImage: "cross.case")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .sheet(isPresented: $showEmergencyEdit) {
            NavigationStack { EmergencyInfoEditView().environmentObject(store) }
        }
        .sheet(isPresented: $showNewSymptom) {
            SymptomQuickLogSheet().environmentObject(store)
        }
        .sheet(isPresented: $showMeasurementManager) {
            NavigationStack {
                MeasurementsManagementView()
                    .environmentObject(store)
            }
        }
        .sheet(item: $showSymptomEditor) { entry in
            SymptomQuickLogSheet(editing: entry).environmentObject(store)
        }
        .sheet(isPresented: $showPDFShare) {
            if let pdfShareURL {
                ShareSheet(activityItems: [pdfShareURL])
            }
        }
        .alert(NSLocalizedString("Could not create report", comment: ""), isPresented: $showPDFError) {
            Button(NSLocalizedString("OK", comment: ""), role: .cancel) {}
        } message: {
            if let pdfErrorMessage {
                Text(pdfErrorMessage)
            }
        }
        .onAppear {
            refreshSummary()
        }
        .onChange(of: store.reportDataRevision) { _ in
            refreshSummary()
        }
        .onChange(of: snapshotVisit?.id) { _ in
            refreshSummary()
        }
    }

    private func patientBriefingSection(summary: DoctorReportSummary) -> some View {
        let items = patientBriefingItems(summary: summary)

        return VStack(alignment: .leading, spacing: EditorialSpacing.md) {
            HStack(alignment: .firstTextBaseline) {
                sectionLabel(NSLocalizedString("What to Tell the Doctor", comment: "Patient briefing section title"))
                Spacer()
                Text(NSLocalizedString("talking card", comment: "Patient briefing label"))
                    .appFont(.caption)
                    .foregroundStyle(AppColor.textSecondary)
            }

            Text(NSLocalizedString("Use this to keep the appointment focused. The PDF below is supporting detail; this is what you should say first.", comment: "Patient briefing helper"))
                .appFont(.caption)
                .foregroundStyle(AppColor.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            AppDivider()

            ForEach(Array(items.prefix(3).enumerated()), id: \.element.id) { index, item in
                patientBriefingRow(item, number: index + 1)
                if index < min(items.count, 3) - 1 {
                    AppDivider()
                }
            }
        }
    }

    private func patientBriefingRow(_ item: PatientBriefingItem, number: Int) -> some View {
        HStack(alignment: .top, spacing: EditorialSpacing.sm) {
            ZStack {
                Circle()
                    .fill(item.tint.opacity(0.12))
                    .frame(width: 30, height: 30)
                Text("\(number)")
                    .appFontNumeric(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(item.tint)
            }

            VStack(alignment: .leading, spacing: EditorialSpacing.xs) {
                Label(item.title, systemImage: item.systemImage)
                    .appFont(.body)
                    .fontWeight(.semibold)
                    .foregroundStyle(AppColor.textPrimary)
                Text(item.detail)
                    .appFont(.caption)
                    .foregroundStyle(AppColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: EditorialSpacing.sm)
        }
        .padding(.vertical, EditorialSpacing.xs)
    }

    private func patientBriefingItems(summary: DoctorReportSummary) -> [PatientBriefingItem] {
        var items: [PatientBriefingItem] = []

        if let reason = summary.visit?.reason?.trimmingCharacters(in: .whitespacesAndNewlines), !reason.isEmpty {
            items.append(
                PatientBriefingItem(
                    id: "reason",
                    title: NSLocalizedString("Start with the reason for this visit", comment: "Patient briefing item"),
                    detail: reason,
                    systemImage: "quote.bubble",
                    tint: AppColor.primary
                )
            )
        }

        if let abnormal = summary.measurements
            .filter({ $0.outOfRangeCount > 0 })
            .sorted(by: { $0.outOfRangeCount > $1.outOfRangeCount })
            .first {
            items.append(
                PatientBriefingItem(
                    id: "measurement-\(abnormal.id.rawValue)",
                    title: NSLocalizedString("Mention the home readings", comment: "Patient briefing item"),
                    detail: String(format: NSLocalizedString("%@ has %lld out-of-range readings in the last %lld days; latest was %@.", comment: "Patient briefing measurement detail"), abnormal.type.displayName, abnormal.outOfRangeCount, summary.days, abnormal.latestValue),
                    systemImage: "waveform.path.ecg",
                    tint: AppColor.warning
                )
            )
        }

        if let worstGap = summary.adherenceGaps.first {
            items.append(
                PatientBriefingItem(
                    id: "missed-\(worstGap.id.uuidString)",
                    title: NSLocalizedString("Ask what to do after missed doses", comment: "Patient briefing item"),
                    detail: String(format: NSLocalizedString("%@ had %lld missed-dose days in the last %lld days.", comment: "Patient briefing missed dose detail"), worstGap.medicationName, worstGap.missedDays.count, summary.days),
                    systemImage: "pills",
                    tint: AppColor.warning
                )
            )
        }

        if let symptom = summary.symptoms.first {
            items.append(
                PatientBriefingItem(
                    id: "symptom-\(symptom.id.uuidString)",
                    title: NSLocalizedString("Bring up the main symptom", comment: "Patient briefing item"),
                    detail: symptom.note?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
                        ? "\(symptom.summary): \(symptom.note ?? "")"
                        : symptom.summary,
                    systemImage: "heart.text.square",
                    tint: symptom.severity == .severe ? AppColor.warning : AppColor.primary
                )
            )
        }

        if !summary.medications.isEmpty {
            items.append(
                PatientBriefingItem(
                    id: "medication-list",
                    title: NSLocalizedString("Confirm the medication list", comment: "Patient briefing item"),
                    detail: String(format: NSLocalizedString("Ask whether these %lld medications, doses, and times should continue until the next visit.", comment: "Patient briefing medication list detail"), summary.medications.count),
                    systemImage: "checklist",
                    tint: AppColor.primary
                )
            )
        }

        if items.isEmpty {
            items.append(
                PatientBriefingItem(
                    id: "routine",
                    title: NSLocalizedString("Confirm the plan until next time", comment: "Patient briefing fallback"),
                    detail: NSLocalizedString("No major issues were logged. Ask what to keep doing, what to watch, and when to come back.", comment: "Patient briefing fallback detail"),
                    systemImage: "calendar.badge.clock",
                    tint: AppColor.primary
                )
            )
        }

        return items
    }

    private func doctorQuestionsSection(summary: DoctorReportSummary) -> some View {
        let questions = doctorQuestions(summary: summary)

        return VStack(alignment: .leading, spacing: EditorialSpacing.md) {
            HStack(alignment: .firstTextBaseline) {
                sectionLabel(NSLocalizedString("Questions to Ask", comment: "Doctor questions section title"))
                Spacer()
                Text(String(format: NSLocalizedString("%lld prepared", comment: "Doctor questions prepared count"), questions.count))
                    .appFontNumeric(.caption)
                    .foregroundStyle(AppColor.textSecondary)
            }

            Text(NSLocalizedString("These are prompts to help you ask clearly. They are not medical advice.", comment: "Doctor questions disclaimer"))
                .appFont(.caption)
                .foregroundStyle(AppColor.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            AppDivider()

            ForEach(Array(questions.enumerated()), id: \.element.id) { index, item in
                doctorQuestionRow(item)
                if index < questions.count - 1 {
                    AppDivider()
                }
            }
        }
    }

    private func doctorQuestionRow(_ item: DoctorQuestion) -> some View {
        HStack(alignment: .top, spacing: EditorialSpacing.sm) {
            Image(systemName: item.systemImage)
                .font(.system(size: 15, weight: .regular))
                .foregroundStyle(item.tint)
                .frame(width: 24, alignment: .center)
                .padding(.top, 1)

            VStack(alignment: .leading, spacing: EditorialSpacing.xs) {
                Text(item.question)
                    .appFont(.body)
                    .fontWeight(.semibold)
                    .foregroundStyle(AppColor.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)

                if let detail = item.detail {
                    Text(detail)
                        .appFont(.caption)
                        .foregroundStyle(AppColor.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: EditorialSpacing.sm)
        }
        .padding(.vertical, EditorialSpacing.xs)
    }

    private func doctorQuestions(summary: DoctorReportSummary) -> [DoctorQuestion] {
        var questions: [DoctorQuestion] = []

        if !summary.medications.isEmpty {
            questions.append(
                DoctorQuestion(
                    id: "medication-plan",
                    question: NSLocalizedString("Should I keep taking each medication at the current dose and time?", comment: "Doctor question medication plan"),
                    detail: String(format: NSLocalizedString("%lld medications are listed in the snapshot.", comment: "Doctor question medication detail"), summary.medications.count),
                    systemImage: "pills",
                    tint: AppColor.primary
                )
            )
        }

        if let worstGap = summary.adherenceGaps.first {
            questions.append(
                DoctorQuestion(
                    id: "missed-dose-\(worstGap.id.uuidString)",
                    question: NSLocalizedString("What should I do when I miss a dose?", comment: "Doctor question missed dose"),
                    detail: String(format: NSLocalizedString("%@ has %lld missed-dose days in this report window.", comment: "Doctor question missed dose detail"), worstGap.medicationName, worstGap.missedDays.count),
                    systemImage: "clock.badge.exclamationmark",
                    tint: AppColor.warning
                )
            )
        }

        if let abnormal = summary.measurements
            .filter({ $0.outOfRangeCount > 0 })
            .sorted(by: { $0.outOfRangeCount > $1.outOfRangeCount })
            .first {
            questions.append(
                DoctorQuestion(
                    id: "target-\(abnormal.id.rawValue)",
                    question: String(format: NSLocalizedString("What target range should I use for %@ at home?", comment: "Doctor question measurement target"), abnormal.type.displayName),
                    detail: String(format: NSLocalizedString("%lld readings were out of range; latest was %@.", comment: "Doctor question measurement detail"), abnormal.outOfRangeCount, abnormal.latestValue),
                    systemImage: "target",
                    tint: AppColor.warning
                )
            )
        }

        if let symptom = summary.symptoms.first {
            questions.append(
                DoctorQuestion(
                    id: "symptom-\(symptom.id.uuidString)",
                    question: NSLocalizedString("Which symptoms should make me contact you sooner?", comment: "Doctor question symptoms"),
                    detail: symptom.summary,
                    systemImage: "heart.text.square",
                    tint: symptom.severity == .severe ? AppColor.warning : AppColor.primary
                )
            )
        }

        if let visit = summary.visit, visit.needsPostVisitCapture {
            questions.append(
                DoctorQuestion(
                    id: "post-visit-plan",
                    question: NSLocalizedString("Before I leave, can we confirm the plan until the next visit?", comment: "Doctor question confirm plan"),
                    detail: String(format: NSLocalizedString("Still needs: %@", comment: "Post visit missing detail"), visit.postVisitMissingItems.joined(separator: ", ")),
                    systemImage: "checklist",
                    tint: AppColor.warning
                )
            )
        } else {
            questions.append(
                DoctorQuestion(
                    id: "follow-up",
                    question: NSLocalizedString("When should I come back, and what should I track before then?", comment: "Doctor question follow up"),
                    detail: nil,
                    systemImage: "calendar.badge.clock",
                    tint: AppColor.primary
                )
            )
        }

        return Array(questions.prefix(4))
    }

    private func snapshotSummaryStrip(summary: DoctorReportSummary) -> some View {
        let totalMissed = summary.adherenceGaps.reduce(0) { $0 + $1.missedDays.count }
        let abnormalReadings = summary.measurements.reduce(0) { $0 + $1.outOfRangeCount }
        let symptomCount = recentSymptoms.count
        let concernCount = totalMissed + abnormalReadings + symptomCount

        return VStack(alignment: .leading, spacing: EditorialSpacing.md) {
            HStack(alignment: .firstTextBaseline) {
                sectionLabel(NSLocalizedString("At A Glance", comment: "Consultation snapshot quick summary section"))
                Spacer()
                Text(String(format: NSLocalizedString("Last %lld days", comment: "Consultation snapshot summary window"), daysWindow))
                    .appFontNumeric(.caption)
                    .foregroundStyle(AppColor.textSecondary)
            }

            VStack(spacing: EditorialSpacing.sm) {
                snapshotSummaryLine(
                    title: NSLocalizedString("Allergy", comment: "Consultation snapshot summary metric"),
                    value: summary.allergies ?? NSLocalizedString("None recorded", comment: "Consultation snapshot allergy metric detail"),
                    systemImage: summary.allergies == nil ? "checkmark.circle" : "exclamationmark.triangle",
                    tint: summary.allergies == nil ? AppColor.success : AppColor.warning
                )
                AppDivider()
                snapshotSummaryLine(
                    title: NSLocalizedString("Medications", comment: "Consultation snapshot summary metric"),
                    value: String(format: NSLocalizedString("%lld current medications", comment: "Consultation snapshot medication summary"), summary.medications.count),
                    systemImage: "pills",
                    tint: summary.medications.isEmpty ? AppColor.textSecondary : AppColor.primary
                )
                AppDivider()
                snapshotSummaryLine(
                    title: NSLocalizedString("Doctor should note", comment: "Consultation snapshot concern summary"),
                    value: concernCount == 0
                        ? NSLocalizedString("No major issues logged", comment: "Consultation snapshot no concerns")
                        : String(format: NSLocalizedString("%lld items need review", comment: "Consultation snapshot concern count"), concernCount),
                    systemImage: concernCount == 0 ? "checkmark.seal" : "exclamationmark.triangle",
                    tint: concernCount == 0 ? AppColor.success : AppColor.warning
                )
            }
        }
    }

    @ViewBuilder
    private func visitPrepSection(summary: DoctorReportSummary) -> some View {
        if let visit = summary.visit {
            VStack(alignment: .leading, spacing: EditorialSpacing.md) {
                HStack(alignment: .firstTextBaseline) {
                    sectionLabel(NSLocalizedString("Prepared For", comment: ""))
                    Spacer()
                    Text(visit.scheduledDate, format: .dateTime.year().month().day())
                        .appFontNumeric(.caption)
                        .foregroundStyle(AppColor.textSecondary)
                }

                AppDivider()

                VStack(alignment: .leading, spacing: EditorialSpacing.xs) {
                    Text(visit.displayTitle)
                        .appFont(.body)
                        .fontWeight(.semibold)
                        .foregroundStyle(AppColor.textPrimary)
                    if let reason = visit.reason, !reason.isEmpty {
                        Text(reason)
                            .appFont(.caption)
                            .foregroundStyle(AppColor.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Text(preVisitReadinessText(for: visit))
                        .appFont(.caption)
                        .foregroundStyle(AppColor.textSecondary)
                }

                VStack(alignment: .leading, spacing: EditorialSpacing.sm) {
                    ForEach(summary.talkingPoints, id: \.self) { point in
                        HStack(alignment: .top, spacing: EditorialSpacing.sm) {
                            Image(systemName: "checkmark")
                                .font(.system(size: 12, weight: .regular))
                                .foregroundStyle(AppColor.primary)
                                .padding(.top, 2)
                            Text(point)
                                .appFont(.caption)
                                .foregroundStyle(AppColor.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: EditorialSpacing.sm) {
            HStack(alignment: .firstTextBaseline) {
                Text(NSLocalizedString("Visit summary", comment: "Consultation snapshot editorial title"))
                    .appFont(.displayTitle)
                    .foregroundStyle(AppColor.textPrimary)
                Spacer()
                Text(Date(), format: .dateTime.year().month().day())
                    .appFontNumeric(.caption)
                    .foregroundStyle(AppColor.textSecondary)
            }

            Text(NSLocalizedString("Patient-reported · not a medical record", comment: ""))
                    .appFont(.caption)
                    .foregroundStyle(AppColor.textSecondary)

            AppDivider()
        }
    }

    @ViewBuilder
    private func allergiesWarning(summary: DoctorReportSummary) -> some View {
        if let allergies = summary.allergies {
            VStack(alignment: .leading, spacing: EditorialSpacing.md) {
                HStack(alignment: .firstTextBaseline, spacing: EditorialSpacing.sm) {
                    Image(systemName: "exclamationmark.triangle")
                        .foregroundStyle(AppColor.warning)
                        .font(.system(size: 14, weight: .regular))
                    Text(String(format: NSLocalizedString("Allergy · %@", comment: "Visit summary allergy line"), allergies))
                        .appFont(.body)
                        .fontWeight(.semibold)
                        .foregroundStyle(AppColor.warning)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer()
                }
                AppDivider()
            }
        }
    }

    // MARK: - Medications

    private func groupedSummaryMedications(summary: DoctorReportSummary) -> [(MedicationSource, [DoctorReportSummary.MedicationLine])] {
        let order: [MedicationSource] = [.prescribed, .external, .otc, .supplement, .unknown]
        let groups = Dictionary(grouping: summary.medications) { $0.source }
        return order.compactMap { src in
            guard let meds = groups[src], !meds.isEmpty else { return nil }
            return (src, meds)
        }
    }

    private func medicationsSection(summary: DoctorReportSummary) -> some View {
        VStack(alignment: .leading, spacing: EditorialSpacing.md) {
            HStack(alignment: .firstTextBaseline) {
                Text(NSLocalizedString("Current medications", comment: "Visit summary medications header"))
                    .appFont(.headline)
                    .foregroundStyle(AppColor.textPrimary)
                Spacer()
                Text(String(format: NSLocalizedString("%lld items", comment: "Visit summary medication count"), summary.medications.count))
                    .appFontNumeric(.caption)
                    .foregroundStyle(AppColor.textSecondary)
            }

            AppDivider()

            if summary.medications.isEmpty {
                Text(NSLocalizedString("No medications recorded.", comment: ""))
                    .appFont(.caption)
                    .foregroundStyle(AppColor.textSecondary)
            } else {
                ForEach(groupedSummaryMedications(summary: summary), id: \.0) { (source, meds) in
                    VStack(alignment: .leading, spacing: EditorialSpacing.sm) {
                        Text(editorialSourceTitle(source))
                            .appFont(.micro)
                            .textCase(.uppercase)
                            .tracking(0.7)
                            .foregroundStyle(AppColor.textSecondary)
                        ForEach(Array(meds.enumerated()), id: \.element.id) { index, med in
                            medicationRow(med)
                            if index < meds.count - 1 {
                                AppDivider()
                            }
                        }
                    }
                    .padding(.top, EditorialSpacing.xs)
                }
            }
        }
    }

    @ViewBuilder
    private func medicationRow(_ med: DoctorReportSummary.MedicationLine) -> some View {
        VStack(alignment: .leading, spacing: EditorialSpacing.xs) {
            Text("\(med.name) \(med.dose)")
                .appFont(.body)
                .fontWeight(.semibold)
                .foregroundStyle(AppColor.textPrimary)
                .fixedSize(horizontal: false, vertical: true)

            Label(med.schedule, systemImage: med.schedule == NSLocalizedString("PRN", comment: "As needed") ? "hand.raised" : "clock")
                .appFont(.caption)
                .foregroundStyle(AppColor.textSecondary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)

            if let caption = med.caption {
                Text(caption)
                    .appFont(.caption)
                    .foregroundStyle(AppColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, EditorialSpacing.xs)
    }

    // MARK: - Adherence

    private func adherenceSection(summary: DoctorReportSummary) -> some View {
        let gaps = summary.adherenceGaps
        let totalMissed = gaps.reduce(0) { $0 + $1.missedDays.count }
        let scheduledMeds = store.medications.filter { $0.isAsNeeded != true && !$0.timesOfDay.isEmpty }
        return VStack(alignment: .leading, spacing: EditorialSpacing.md) {
            HStack {
                Text(String(format: NSLocalizedString("Adherence · last %lld days", comment: ""), daysWindow))
                    .appFont(.headline)
                    .foregroundStyle(AppColor.textPrimary)
                Spacer()
                if !scheduledMeds.isEmpty {
                    Text(String(format: "%.0f%%", store.adherencePercent(days: daysWindow) * 100))
                        .appFontNumeric(.headline)
                        .fontWeight(.bold)
                        .foregroundStyle(totalMissed == 0 ? AppColor.success : AppColor.textPrimary)
                }
            }

            AppDivider()

            if scheduledMeds.isEmpty {
                Text(NSLocalizedString("No scheduled medications.", comment: ""))
                    .appFont(.caption)
                    .foregroundStyle(AppColor.textSecondary)
            } else if totalMissed == 0 {
                Text(NSLocalizedString("No missed doses.", comment: ""))
                    .appFont(.caption)
                    .foregroundStyle(AppColor.textSecondary)
            } else {
                ForEach(gaps) { gap in
                    VStack(alignment: .leading, spacing: EditorialSpacing.xs) {
                        HStack(alignment: .firstTextBaseline) {
                            Text(gap.medicationName)
                                .appFont(.caption)
                                .fontWeight(.semibold)
                                .foregroundStyle(AppColor.textPrimary)
                            Spacer()
                            Text(String(format: NSLocalizedString("%lld missed", comment: ""), gap.missedDays.count))
                                .appFontNumeric(.caption)
                                .foregroundStyle(AppColor.warning)
                        }
                        Text(gap.missedDays.prefix(8).map { dateShort($0) }.joined(separator: ", "))
                            .appFontNumeric(.footnote)
                            .foregroundStyle(AppColor.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.vertical, EditorialSpacing.xs)
                }
            }
        }
    }

    // MARK: - Home Measurements

    private func measurementsSection(summary: DoctorReportSummary) -> some View {
        VStack(alignment: .leading, spacing: EditorialSpacing.md) {
            HStack(alignment: .firstTextBaseline) {
                Text(String(format: NSLocalizedString("Home measurements · last %lld days", comment: ""), daysWindow))
                    .appFont(.headline)
                    .foregroundStyle(AppColor.textPrimary)
                Spacer()
                if !store.measurements.isEmpty {
                    Button {
                        Haptics.impact(.light)
                        showMeasurementManager = true
                    } label: {
                        Text(NSLocalizedString("Manage", comment: ""))
                            .appFont(.caption)
                            .foregroundStyle(AppColor.primary)
                    }
                    .buttonStyle(.plain)
                }
            }

            AppDivider()

            let highlights = summary.measurements
            if highlights.isEmpty {
                Text(NSLocalizedString("No measurements recorded in the window.", comment: ""))
                    .appFont(.caption)
                    .foregroundStyle(AppColor.textSecondary)
            } else {
                ForEach(Array(highlights.enumerated()), id: \.element.id) { index, highlight in
                    measurementRow(highlight)
                    if index < highlights.count - 1 {
                        AppDivider()
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func measurementRow(_ highlight: DoctorReportSummary.MeasurementHighlight) -> some View {
        let latestIsOutOfRange = latestMeasurementIsOutOfRange(highlight)
        let valueColor = latestIsOutOfRange ? AppColor.warning : AppColor.textPrimary
        let rangeText = measurementRangeText(for: highlight.type)

        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(highlight.type.displayName)
                    .appFont(.body)
                    .fontWeight(.semibold)
                    .foregroundStyle(AppColor.textPrimary)

                Text(highlight.latestValue)
                    .appFontNumeric(.subheadline)
                    .fontWeight(.bold)
                    .foregroundStyle(valueColor)

                if let rangeText {
                    Text(rangeText)
                        .appFontNumeric(.footnote)
                        .foregroundStyle(AppColor.textSecondary)
                }

                if highlight.outOfRangeCount > 0 {
                    Text(String(format: NSLocalizedString("Latest %@ · %lld entries · %lld out-of-range", comment: "Visit summary measurement warning caption"), dateShort(highlight.latestDate), highlight.entryCount, highlight.outOfRangeCount))
                        .appFontNumeric(.caption)
                        .foregroundStyle(AppColor.warning)
                } else {
                    Text(String(format: NSLocalizedString("Latest %@ · %lld entries · within range", comment: "Visit summary measurement normal caption"), dateShort(highlight.latestDate), highlight.entryCount))
                        .appFontNumeric(.caption)
                        .foregroundStyle(AppColor.textSecondary)
                }
            }
            Spacer()
            if !highlight.series.isEmpty {
                sparkline(series: highlight.series, type: highlight.type)
                    .frame(width: 100, height: 34)
            }
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private func sparkline(series: [Measurement], type: MeasurementType) -> some View {
        Chart(series) { m in
            LineMark(
                x: .value("d", m.date),
                y: .value("v", primaryValue(m))
            )
            .foregroundStyle(AppColor.primary.opacity(0.72))
            .interpolationMethod(.monotone)

            if m.id == series.last?.id {
                PointMark(
                    x: .value("d", m.date),
                    y: .value("v", primaryValue(m))
                )
                .foregroundStyle(m.isAbnormal ? AppColor.warning : AppColor.primary)
            }
        }
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartPlotStyle { plot in
            plot.background(Color.clear)
        }
    }

    private func primaryValue(_ m: Measurement) -> Double {
        m.value
    }

    private func latestMeasurementIsOutOfRange(_ highlight: DoctorReportSummary.MeasurementHighlight) -> Bool {
        guard let latest = highlight.series.last else { return false }
        return latest.isAbnormal
    }

    private func measurementRangeText(for type: MeasurementType) -> String? {
        switch type {
        case .bloodPressure:
            let thresholds = store.bpThresholds()
            let target = "\(Int(thresholds.systolicHigh))/\(Int(thresholds.diastolicHigh)) \(type.unit)"
            return String(format: NSLocalizedString("Target <= %@", comment: "Consultation snapshot blood pressure target"), target)
        case .bloodGlucose:
            guard let range = store.customGoalRange(for: type) else { return nil }
            let low = UnitPreferences.mgdlToPreferred(range.lowerBound)
            let high = UnitPreferences.mgdlToPreferred(range.upperBound)
            let formatter = UnitPreferences.glucoseUnit == .mgdL ? "%.0f" : "%.1f"
            let target = "\(String(format: formatter, low))-\(String(format: formatter, high)) \(UnitPreferences.glucoseUnit.rawValue)"
            return String(format: NSLocalizedString("Target %@", comment: "Consultation snapshot measurement target"), target)
        case .heartRate:
            guard let range = store.customGoalRange(for: type) else { return nil }
            let target = "\(Int(range.lowerBound))-\(Int(range.upperBound)) \(type.unit)"
            return String(format: NSLocalizedString("Target %@", comment: "Consultation snapshot measurement target"), target)
        case .weight:
            return nil
        }
    }

    // MARK: - Symptoms

    private var recentSymptoms: [SymptomEntry] {
        let cal = Calendar.current
        guard let cutoff = cal.date(byAdding: .day, value: -daysWindow, to: Date()) else { return [] }
        return store.symptomEntries
            .filter { $0.date >= cutoff }
            .sorted(by: { $0.date > $1.date })
    }

    private var symptomsSection: some View {
        VStack(alignment: .leading, spacing: EditorialSpacing.md) {
            HStack {
                Text(String(format: NSLocalizedString("Symptoms · last %lld days", comment: ""), daysWindow))
                    .appFont(.headline)
                    .foregroundStyle(AppColor.textPrimary)
                Spacer()
                Button {
                    showNewSymptom = true
                } label: {
                    Label(NSLocalizedString("Add", comment: ""), systemImage: "plus")
                        .appFont(.caption)
                        .foregroundStyle(AppColor.primary)
                }
            }

            AppDivider()

            if recentSymptoms.isEmpty {
                Text(NSLocalizedString("No symptoms logged. Tap Add when you feel unwell.", comment: ""))
                    .appFont(.caption)
                    .foregroundStyle(AppColor.textSecondary)
            } else {
                ForEach(Array(recentSymptoms.enumerated()), id: \.element.id) { index, entry in
                    Button {
                        showSymptomEditor = entry
                    } label: {
                        symptomRow(entry)
                    }
                    .buttonStyle(.plain)
                    if index < recentSymptoms.count - 1 {
                        AppDivider()
                    }
                }
            }
        }
    }

    private func symptomRow(_ entry: SymptomEntry) -> some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(dateShort(entry.date))
                    .appFontNumeric(.footnote)
                    .foregroundStyle(AppColor.textSecondary)
                Text(entry.severity.displayName)
                    .appFont(.footnote)
                    .foregroundStyle(severityColor(entry.severity))
            }
            .frame(width: 54, alignment: .leading)

            VStack(alignment: .leading, spacing: 3) {
                Text(entry.tags.joined(separator: "、"))
                    .appFont(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(AppColor.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                if let note = entry.note, !note.isEmpty {
                    Text(note)
                        .appFont(.footnote)
                        .foregroundStyle(AppColor.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let ids = entry.relatedMedicationIDs, !ids.isEmpty {
                    let names = store.medications.filter { ids.contains($0.id) }.map(\.name)
                    if !names.isEmpty {
                        Text(String(format: NSLocalizedString("suspected: %@", comment: ""),
                                    names.joined(separator: ", ")))
                            .appFont(.footnote)
                            .foregroundStyle(AppColor.textSecondary)
                            .italic()
                    }
                }
            }
            Spacer()
        }
        .padding(.vertical, 3)
    }

    private func severityColor(_ s: SymptomSeverity) -> Color {
        switch s {
        case .mild: return AppColor.textSecondary
        case .moderate: return AppColor.textPrimary
        case .severe: return AppColor.warning
        }
    }

    // MARK: - Emergency footer

    @ViewBuilder
    private var emergencyFooter: some View {
        let info = store.emergencyInfo
        let contact = info?.emergencyContacts.first
        VStack(alignment: .leading, spacing: EditorialSpacing.md) {
            Text(NSLocalizedString("Emergency Info", comment: ""))
                .appFont(.headline)
                .foregroundStyle(AppColor.textPrimary)

            AppDivider()

            Group {
                if let bt = info?.bloodType, !bt.isEmpty {
                    emergencyLine(NSLocalizedString("Blood type", comment: ""), bt)
                }
                if let cond = info?.medicalConditions, !cond.isEmpty {
                    emergencyLine(NSLocalizedString("Conditions", comment: ""), cond)
                }
                if let contact {
                    emergencyLine(NSLocalizedString("Contact", comment: ""),
                                  "\(contact.name) · \(contact.phone)")
                }
                if info == nil || ((info?.bloodType?.isEmpty ?? true)
                                    && (info?.medicalConditions?.isEmpty ?? true)
                                    && (info?.emergencyContacts.isEmpty ?? true)) {
                    Text(NSLocalizedString("Not set. Use the menu to edit.", comment: ""))
                        .appFont(.caption)
                        .foregroundStyle(AppColor.textSecondary)
                }
            }
        }
    }

    private func emergencyLine(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(label)
                .appFont(.footnote)
                .foregroundStyle(AppColor.textSecondary)
                .frame(width: 72, alignment: .leading)
            Text(value)
                .appFont(.caption)
                .fontWeight(.medium)
                .foregroundStyle(AppColor.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
        }
    }

    // MARK: - Export

    private func exportSection(summary: DoctorReportSummary) -> some View {
        VStack(alignment: .leading, spacing: EditorialSpacing.md) {
            AppDivider()

            Text(NSLocalizedString("Give this to your doctor", comment: "Consultation snapshot export section"))
                .appFont(.headline)
                .foregroundStyle(AppColor.textPrimary)

            Text(NSLocalizedString("Export a clean PDF when the doctor needs a focused summary with supporting details.", comment: "Consultation snapshot export helper"))
                .appFont(.caption)
                .foregroundStyle(AppColor.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            EditorialButton(
                isGeneratingPDF
                ? NSLocalizedString("Generating PDF…", comment: "Health report preview loading action")
                : NSLocalizedString("Export doctor PDF", comment: "Consultation snapshot PDF export action"),
                systemImage: isGeneratingPDF ? "hourglass" : "doc.richtext",
                kind: .primary
            ) {
                exportPDFReport()
            }
            .disabled(isGeneratingPDF)
        }
        .padding(.top, EditorialSpacing.sm)
    }

    // MARK: - Helpers

    private func sectionLabel(_ text: String, count: Int? = nil) -> some View {
        HStack(spacing: 6) {
            Text(text.uppercased())
                .appFont(.micro)
                .foregroundStyle(AppColor.textPrimary)
                .tracking(0.7)
            if let count, count > 0 {
                Text("\(count)")
                    .appFontNumeric(.caption)
                    .foregroundStyle(AppColor.textSecondary)
            }
        }
    }

    private func snapshotSummaryLine(title: String, value: String, systemImage: String, tint: Color) -> some View {
        HStack(alignment: .top, spacing: EditorialSpacing.sm) {
            Image(systemName: systemImage)
                .font(.system(size: 18, weight: .regular))
                .foregroundStyle(tint)
                .frame(width: 24, alignment: .center)

            VStack(alignment: .leading, spacing: EditorialSpacing.xs) {
                Text(title)
                    .appFont(.body)
                    .foregroundStyle(AppColor.textSecondary)
                Text(value)
                    .appFont(.headline)
                    .foregroundStyle(AppColor.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: EditorialSpacing.sm)
        }
        .padding(.vertical, EditorialSpacing.xs)
    }

    private func editorialSourceTitle(_ source: MedicationSource) -> String {
        switch source {
        case .prescribed:
            return NSLocalizedString("Hospital prescription", comment: "Visit summary medication source")
        case .external:
            return NSLocalizedString("External prescription", comment: "Visit summary medication source")
        case .otc:
            return NSLocalizedString("OTC", comment: "Visit summary medication source")
        case .supplement:
            return NSLocalizedString("Supplement", comment: "Visit summary medication source")
        case .unknown:
            return NSLocalizedString("Unspecified", comment: "Visit summary medication source")
        }
    }

    private static let shortDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("Md")
        return formatter
    }()

    private func dateShort(_ date: Date) -> String {
        Self.shortDateFormatter.string(from: date)
    }

    private func preVisitReadinessText(for visit: DoctorVisit) -> String {
        guard let days = visit.daysUntil() else {
            return NSLocalizedString("Completed visit. Keep notes here for the next follow-up.", comment: "")
        }
        if days == 0 {
            return NSLocalizedString("Use this during the appointment to answer common doctor questions quickly.", comment: "")
        }
        if days > 0 {
            return String(format: NSLocalizedString("Your appointment is in %lld days. Keep logging anything the doctor should know.", comment: ""), days)
        }
        return NSLocalizedString("This appointment is overdue. Update it after the visit or schedule the next one.", comment: "")
    }

    private func refreshSummary() {
        cachedSummary = DoctorReportSummaryBuilder.build(store: store, days: daysWindow, visit: snapshotVisit)
    }

    @MainActor
    private func exportPDFReport() {
        guard !isGeneratingPDF else { return }
        isGeneratingPDF = true
        Task {
            do {
                pdfShareURL = try await PDFGenerator.generateReportOffMain(store: store, days: daysWindow)
                showPDFShare = true
                Haptics.success()
            } catch {
                pdfErrorMessage = error.localizedDescription
                showPDFError = true
            }
            isGeneratingPDF = false
        }
    }
}

private struct MeasurementsManagementView: View {
    @EnvironmentObject var store: DataStore
    @Environment(\.dismiss) private var dismiss
    @State private var editingMeasurement: Measurement?

    private var sortedMeasurements: [Measurement] {
        store.measurements.sorted { $0.date > $1.date }
    }

    var body: some View {
        Group {
            if sortedMeasurements.isEmpty {
                VStack(spacing: EditorialSpacing.md) {
                    Image(systemName: "waveform.path.ecg")
                        .font(.system(size: 28, weight: .regular))
                        .foregroundStyle(AppColor.textTertiary)
                    Text(NSLocalizedString("No measurements recorded.", comment: ""))
                        .appFont(.body)
                        .foregroundStyle(AppColor.textPrimary)
                    Text(NSLocalizedString("New blood pressure and glucose readings will appear here.", comment: ""))
                        .appFont(.caption)
                        .foregroundStyle(AppColor.textSecondary)
                        .multilineTextAlignment(.center)
                }
                .padding(EditorialSpacing.xl)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(AppColor.background)
            } else {
                List {
                    ForEach(sortedMeasurements) { measurement in
                        Button {
                            Haptics.impact(.light)
                            editingMeasurement = measurement
                        } label: {
                            measurementRow(measurement)
                        }
                        .buttonStyle(EditorialRowButtonStyle())
                    }
                    .onDelete(perform: deleteMeasurements)
                }
                .listStyle(.insetGrouped)
                .scrollContentBackground(.hidden)
                .background(AppColor.background)
            }
        }
        .sheet(item: $editingMeasurement) { measurement in
            AddMeasurementView(editing: measurement) { updated in
                store.updateMeasurement(updated)
            }
            .environmentObject(store)
        }
        .navigationTitle(NSLocalizedString("Manage Measurements", comment: ""))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if !sortedMeasurements.isEmpty {
                ToolbarItem(placement: .topBarLeading) {
                    EditButton()
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button(NSLocalizedString("Done", comment: "")) { dismiss() }
            }
        }
    }

    private func measurementRow(_ measurement: Measurement) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: EditorialSpacing.md) {
            VStack(alignment: .leading, spacing: EditorialSpacing.xs) {
                Text(measurement.type.displayName)
                    .appFont(.body)
                    .foregroundStyle(AppColor.textPrimary)
                Text(Self.dateFormatter.string(from: measurement.date))
                    .appFont(.caption)
                    .foregroundStyle(AppColor.textSecondary)
            }

            Spacer()

            Text(formattedValue(measurement))
                .appFontNumeric(.body)
                .fontWeight(.semibold)
                .foregroundStyle(AppColor.textPrimary)
                .multilineTextAlignment(.trailing)
        }
        .padding(.vertical, EditorialSpacing.xs)
    }

    private func deleteMeasurements(at offsets: IndexSet) {
        let items = offsets.map { sortedMeasurements[$0] }
        items.forEach(store.removeMeasurement)
        Haptics.success()
    }

    private func formattedValue(_ measurement: Measurement) -> String {
        if measurement.type == .bloodPressure, let diastolic = measurement.diastolic {
            return "\(Int(measurement.value))/\(Int(diastolic)) \(measurement.type.unit)"
        }
        if measurement.type == .bloodGlucose {
            let value = UnitPreferences.mgdlToPreferred(measurement.value)
            let formatted = UnitPreferences.glucoseUnit == .mgdL
                ? String(format: "%.0f", value)
                : String(format: "%.1f", value)
            return "\(formatted) \(UnitPreferences.glucoseUnit.rawValue)"
        }
        if measurement.type == .heartRate {
            return "\(Int(measurement.value)) \(measurement.type.unit)"
        }
        return "\(String(format: "%.1f", measurement.value)) \(measurement.type.unit)"
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()
}
