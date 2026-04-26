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
    @State private var shareText: String = ""
    @State private var showShare = false

    private let daysWindow: Int = 30

    private var snapshotVisit: DoctorVisit? {
        visit ?? store.nextDoctorVisit
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: EditorialSpacing.xl) {
                header
                visitPrepSection
                allergiesWarning
                medicationsSection
                adherenceSection
                measurementsSection
                symptomsSection
                emergencyFooter
                shareButton
            }
            .padding(.horizontal, EditorialSpacing.lg)
            .padding(.vertical, EditorialSpacing.lg)
        }
        .background(AppColor.background)
        .navigationTitle(NSLocalizedString("Consultation Snapshot", comment: ""))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
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
        .sheet(item: $showSymptomEditor) { entry in
            SymptomQuickLogSheet(editing: entry).environmentObject(store)
        }
        .sheet(isPresented: $showShare) {
            ShareSheet(activityItems: [shareText])
        }
    }

    @ViewBuilder
    private var visitPrepSection: some View {
        if let visit = snapshotVisit {
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
                    ForEach(preVisitTalkingPoints(), id: \.self) { point in
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
    private var allergiesWarning: some View {
        if let allergies = store.emergencyInfo?.allergies,
           !allergies.trimmingCharacters(in: .whitespaces).isEmpty {
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

    private var groupedMedications: [(MedicationSource, [Medication])] {
        let order: [MedicationSource] = [.prescribed, .external, .otc, .supplement, .unknown]
        let groups = Dictionary(grouping: store.medications) { $0.source ?? .unknown }
        return order.compactMap { src in
            guard let meds = groups[src], !meds.isEmpty else { return nil }
            return (src, meds)
        }
    }

    private var medicationsSection: some View {
        VStack(alignment: .leading, spacing: EditorialSpacing.md) {
            HStack(alignment: .firstTextBaseline) {
                Text(NSLocalizedString("Current medications", comment: "Visit summary medications header"))
                    .appFont(.headline)
                    .foregroundStyle(AppColor.textPrimary)
                Spacer()
                Text(String(format: NSLocalizedString("%lld items", comment: "Visit summary medication count"), store.medications.count))
                    .appFontNumeric(.caption)
                    .foregroundStyle(AppColor.textSecondary)
            }

            AppDivider()

            if store.medications.isEmpty {
                Text(NSLocalizedString("No medications recorded.", comment: ""))
                    .appFont(.caption)
                    .foregroundStyle(AppColor.textSecondary)
            } else {
                ForEach(groupedMedications, id: \.0) { (source, meds) in
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
    private func medicationRow(_ med: Medication) -> some View {
        let daysOnTherapy = Calendar.current.dateComponents([.day], from: med.startDate, to: Date()).day ?? 0
        let caption = medicationCaption(med: med, daysOnTherapy: daysOnTherapy)
        VStack(alignment: .leading, spacing: EditorialSpacing.xs) {
            HStack(alignment: .firstTextBaseline) {
                Text("\(med.name) \(med.dose)")
                    .appFont(.body)
                    .fontWeight(.semibold)
                    .foregroundStyle(AppColor.textPrimary)
                Spacer()
                Text(medScheduleSummary(med))
                    .appFont(.caption)
                    .foregroundStyle(AppColor.textSecondary)
            }

            if !caption.isEmpty {
                Text(caption)
                    .appFont(.caption)
                    .foregroundStyle(AppColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, EditorialSpacing.xs)
    }

    // MARK: - Adherence

    private var adherenceSection: some View {
        let missedByMed = computeMissedDates()
        let totalMissed = missedByMed.reduce(0) { $0 + $1.1.count }
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
                ForEach(missedByMed, id: \.0) { (medName, dates) in
                    if !dates.isEmpty {
                        VStack(alignment: .leading, spacing: EditorialSpacing.xs) {
                            HStack(alignment: .firstTextBaseline) {
                                Text(medName)
                                    .appFont(.caption)
                                    .fontWeight(.semibold)
                                    .foregroundStyle(AppColor.textPrimary)
                                Spacer()
                                Text(String(format: NSLocalizedString("%lld missed", comment: ""), dates.count))
                                    .appFontNumeric(.caption)
                                    .foregroundStyle(AppColor.warning)
                            }
                            Text(dates.prefix(8).map { dateShort($0) }.joined(separator: ", "))
                                .appFontNumeric(.footnote)
                                .foregroundStyle(AppColor.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(.vertical, EditorialSpacing.xs)
                    }
                }
            }
        }
    }

    /// Per-medication list of missed dates within the window. A "missed day"
    /// means the day had scheduled doses and zero were taken.
    private func computeMissedDates() -> [(String, [Date])] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        var results: [(String, [Date])] = []
        for med in store.medications where med.isAsNeeded != true && !med.timesOfDay.isEmpty {
            var missedDays: [Date] = []
            for offset in 1...daysWindow {
                guard let day = cal.date(byAdding: .day, value: -offset, to: today) else { continue }
                // Skip if the medication hadn't started yet.
                guard med.startDate <= cal.date(byAdding: .day, value: 1, to: day) ?? day else { continue }
                if let courseEnd = med.courseEndDate, day > cal.startOfDay(for: courseEnd) { continue }
                let counts = AdherenceCalculator.dayCounts(dayKey: day, medications: [med], logs: store.intakeLogs)
                if counts.total > 0 && counts.taken == 0 {
                    missedDays.append(day)
                }
            }
            if !missedDays.isEmpty {
                results.append((med.name, missedDays))
            }
        }
        return results.sorted { $0.1.count > $1.1.count }
    }

    // MARK: - Home Measurements

    private var measurementsSection: some View {
        VStack(alignment: .leading, spacing: EditorialSpacing.md) {
            Text(String(format: NSLocalizedString("Home measurements · last %lld days", comment: ""), daysWindow))
                .appFont(.headline)
                .foregroundStyle(AppColor.textPrimary)

            AppDivider()

            let types = MeasurementType.allCases.filter { type in
                !recentMeasurements(type: type).isEmpty
            }
            if types.isEmpty {
                Text(NSLocalizedString("No measurements recorded in the window.", comment: ""))
                    .appFont(.caption)
                    .foregroundStyle(AppColor.textSecondary)
            } else {
                ForEach(Array(types.enumerated()), id: \.element) { index, type in
                    measurementRow(type: type)
                    if index < types.count - 1 {
                        AppDivider()
                    }
                }
            }
        }
    }

    private func recentMeasurements(type: MeasurementType) -> [Measurement] {
        let cal = Calendar.current
        guard let cutoff = cal.date(byAdding: .day, value: -daysWindow, to: Date()) else { return [] }
        return store.measurements
            .filter { $0.type == type && $0.date >= cutoff }
            .sorted(by: { $0.date < $1.date })
    }

    @ViewBuilder
    private func measurementRow(type: MeasurementType) -> some View {
        let series = recentMeasurements(type: type)
        if let latest = series.last {
            let anomalies = countAnomalies(type: type, series: series)
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(type.displayName)
                        .appFont(.body)
                        .fontWeight(.semibold)
                        .foregroundStyle(AppColor.textPrimary)

                    Text(formattedValue(latest))
                        .appFontNumeric(.subheadline)
                        .fontWeight(.bold)
                        .foregroundStyle(AppColor.textPrimary)

                    if anomalies > 0 {
                        Text(String(format: NSLocalizedString("Latest %@ · %lld entries · %lld out-of-range", comment: "Visit summary measurement warning caption"), dateShort(latest.date), series.count, anomalies))
                            .appFontNumeric(.caption)
                            .foregroundStyle(AppColor.warning)
                    } else {
                        Text(String(format: NSLocalizedString("Latest %@ · %lld entries · within range", comment: "Visit summary measurement normal caption"), dateShort(latest.date), series.count))
                            .appFontNumeric(.caption)
                            .foregroundStyle(AppColor.textSecondary)
                    }
                }
                Spacer()
                sparkline(series: series, type: type)
                    .frame(width: 100, height: 34)
            }
            .padding(.vertical, 2)
        }
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

    private func countAnomalies(type: MeasurementType, series: [Measurement]) -> Int {
        switch type {
        case .bloodGlucose, .heartRate:
            guard let range = store.customGoalRange(for: type) else { return 0 }
            return series.filter { $0.value < range.lowerBound || $0.value > range.upperBound }.count
        case .bloodPressure:
            let t = store.bpThresholds()
            return series.filter { m in
                m.value > t.systolicHigh || (m.diastolic ?? 0) > t.diastolicHigh
            }.count
        case .weight:
            return 0
        }
    }

    private func formattedValue(_ m: Measurement) -> String {
        if m.type == .bloodPressure, let diastolic = m.diastolic {
            return "\(Int(m.value))/\(Int(diastolic)) \(m.type.unit)"
        }
        if m.type == .bloodGlucose {
            let value = UnitPreferences.mgdlToPreferred(m.value)
            let formatted = UnitPreferences.glucoseUnit == .mgdL
                ? String(format: "%.0f", value)
                : String(format: "%.1f", value)
            return "\(formatted) \(UnitPreferences.glucoseUnit.rawValue)"
        }
        return "\(String(format: "%.1f", m.value)) \(m.type.unit)"
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

    // MARK: - Share

    private var shareButton: some View {
        EditorialButton(NSLocalizedString("Share Snapshot", comment: ""), systemImage: "square.and.arrow.up", kind: .primary) {
            shareText = buildShareText()
            showShare = true
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

    private func medScheduleSummary(_ med: Medication) -> String {
        if med.isAsNeeded == true {
            return NSLocalizedString("PRN", comment: "As needed")
        }
        guard !med.timesOfDay.isEmpty else {
            return NSLocalizedString("No time set", comment: "Medication schedule missing")
        }
        return med.timesOfDay.map(timeText).joined(separator: " / ")
    }

    private func medicationCaption(med: Medication, daysOnTherapy: Int) -> String {
        var parts: [String] = []
        if daysOnTherapy >= 0 && med.startDate > .distantPast {
            parts.append(String(format: NSLocalizedString("Since %@", comment: "Visit summary medication start date"), dateShort(med.startDate)))
        }
        if let hospital = med.hospital?.trimmingCharacters(in: .whitespacesAndNewlines), !hospital.isEmpty {
            parts.append(hospital)
        }
        return parts.joined(separator: " · ")
    }

    private func timeText(_ c: DateComponents) -> String {
        let h = c.hour ?? 0
        let m = c.minute ?? 0
        return String(format: "%02d:%02d", h, m)
    }

    private func dateShort(_ date: Date) -> String {
        let f = DateFormatter()
        f.setLocalizedDateFormatFromTemplate("Md")
        return f.string(from: date)
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

    private func preVisitTalkingPoints() -> [String] {
        var points: [String] = []
        let missedCount = computeMissedDates().reduce(0) { $0 + $1.1.count }
        let anomalyCount = MeasurementType.allCases.reduce(0) { total, type in
            total + countAnomalies(type: type, series: recentMeasurements(type: type))
        }

        if !store.medications.isEmpty {
            points.append(String(format: NSLocalizedString("%lld current medications, grouped by source.", comment: ""), store.medications.count))
        }
        if missedCount > 0 {
            points.append(String(format: NSLocalizedString("%lld missed-dose days to discuss.", comment: ""), missedCount))
        }
        if anomalyCount > 0 {
            points.append(String(format: NSLocalizedString("%lld out-of-range home readings in the last 30 days.", comment: ""), anomalyCount))
        }
        if !recentSymptoms.isEmpty {
            points.append(String(format: NSLocalizedString("%lld symptom notes since the last review window.", comment: ""), recentSymptoms.count))
        }
        if points.isEmpty {
            points.append(NSLocalizedString("No major issues logged yet; keep recording doses, symptoms, and measurements before the visit.", comment: ""))
        }
        return points
    }

    private func buildShareText() -> String {
        var lines: [String] = []
        lines.append(NSLocalizedString("Consultation Snapshot", comment: ""))
        let df = DateFormatter()
        df.dateStyle = .medium
        lines.append(df.string(from: Date()))
        if let visit = snapshotVisit {
            lines.append(String(format: NSLocalizedString("Prepared for: %@ (%@)", comment: ""), visit.displayTitle, df.string(from: visit.scheduledDate)))
            if let reason = visit.reason, !reason.isEmpty {
                lines.append(String(format: NSLocalizedString("Reason: %@", comment: ""), reason))
            }
        }
        lines.append("")
        if let allergies = store.emergencyInfo?.allergies, !allergies.isEmpty {
            lines.append("[\(NSLocalizedString("Warning", comment: ""))] \(NSLocalizedString("Allergies", comment: "")): \(allergies)")
            lines.append("")
        }
        lines.append("── \(NSLocalizedString("Current Medications", comment: "")) ──")
        for (src, meds) in groupedMedications {
            lines.append("[\(src.displayName)]")
            for med in meds {
                var row = "• \(med.name) \(med.dose)"
                if !med.timesOfDay.isEmpty {
                    row += "  \(med.timesOfDay.map(timeText).joined(separator: ", "))"
                }
                if med.startDate > .distantPast {
                    row += "  \(NSLocalizedString("since", comment: "")) \(dateShort(med.startDate))"
                }
                if let h = med.hospital, !h.isEmpty {
                    row += "  (\(h))"
                }
                lines.append(row)
            }
        }
        lines.append("")
        let missed = computeMissedDates()
        let totalMissed = missed.reduce(0) { $0 + $1.1.count }
        lines.append("── \(NSLocalizedString("Adherence", comment: "")) · \(daysWindow)d ──")
        if totalMissed == 0 {
            lines.append(NSLocalizedString("No missed doses.", comment: ""))
        } else {
            for (name, dates) in missed where !dates.isEmpty {
                lines.append("• \(name): \(dates.count) missed - \(dates.prefix(10).map(dateShort).joined(separator: ", "))")
            }
        }
        lines.append("")
        lines.append("── \(NSLocalizedString("Home Measurements", comment: "")) ──")
        for type in MeasurementType.allCases {
            let s = recentMeasurements(type: type)
            guard let latest = s.last else { continue }
            let anom = countAnomalies(type: type, series: s)
            lines.append("• \(type.displayName): \(formattedValue(latest)) (\(dateShort(latest.date)))  " +
                         (anom > 0 ? "\(anom) out-of-range" : "\(s.count) readings"))
        }
        lines.append("")
        lines.append("── \(NSLocalizedString("Symptoms", comment: "")) · \(daysWindow)d ──")
        if recentSymptoms.isEmpty {
            lines.append(NSLocalizedString("None.", comment: ""))
        } else {
            for e in recentSymptoms {
                var row = "• \(dateShort(e.date)) [\(e.severity.displayName)] \(e.tags.joined(separator: "、"))"
                if let n = e.note, !n.isEmpty { row += " - \(n)" }
                lines.append(row)
            }
        }
        return lines.joined(separator: "\n")
    }
}
