import SwiftUI
import Charts

// MARK: - MedicationDetailView

struct MedicationDetailView: View {
    @EnvironmentObject var store: DataStore
    let medication: Medication
    let onEdit: (Medication) -> Void
    private let snapshotColumns = [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)]

    private var reminderStrategy: AdaptiveReminderStrategy {
        AdaptiveReminderEngine.strategy(for: medication, intakeLogs: store.intakeLogs)
    }

    private var reminderProfile: AdherenceProfile {
        AdaptiveReminderEngine.profile(for: medication, intakeLogs: store.intakeLogs)
    }

    private var lastTakenLog: IntakeLog? {
        store.intakeLogs
            .filter { $0.medicationID == medication.id && $0.status == .taken }
            .max(by: { $0.effectiveRecordedAt < $1.effectiveRecordedAt })
    }

    private var adherence7: Double {
        store.adherencePercent(for: medication.id, days: 7)
    }

    private var adherence30: Double {
        store.adherencePercent(for: medication.id, days: 30)
    }

    private var streakCount: Int {
        store.currentStreak(for: medication.id)
    }

    private var monthlyTakenCount: Int {
        let cal = Calendar.current
        let now = Date()
        let start = cal.date(from: cal.dateComponents([.year, .month], from: now))!
        return store.intakeLogs.filter {
            $0.medicationID == medication.id && $0.status == .taken && $0.date >= start
        }.count
    }

    private var scheduleText: String {
        guard medication.isAsNeeded != true else {
            return NSLocalizedString("Log doses when needed from Today.", comment: "")
        }
        guard !medication.timesOfDay.isEmpty else {
            return NSLocalizedString("No fixed times are configured yet.", comment: "")
        }
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        let values = medication.timesOfDay.compactMap { comps -> String? in
            guard let hour = comps.hour,
                  let minute = comps.minute,
                  let date = Calendar.current.date(bySettingHour: hour, minute: minute, second: 0, of: Date()) else { return nil }
            return formatter.string(from: date)
        }
        return values.joined(separator: ", ")
    }

    private var modeLabel: String {
        medication.isAsNeeded == true ? NSLocalizedString("As Needed", comment: "") : NSLocalizedString("Scheduled", comment: "")
    }

    private var modeTint: Color {
        medication.isAsNeeded == true ? .blue : .green
    }

    private var reminderStateLabel: String {
        if medication.isAsNeeded == true {
            return NSLocalizedString("Manual Logging", comment: "")
        }
        if !medication.remindersEnabled {
            return NSLocalizedString("Reminders Off", comment: "")
        }
        if medication.timesOfDay.isEmpty {
            return NSLocalizedString("Times Missing", comment: "")
        }
        return NSLocalizedString("Reminders On", comment: "")
    }

    private var reminderStateTint: Color {
        if medication.isAsNeeded == true { return .blue }
        if !medication.remindersEnabled || medication.timesOfDay.isEmpty { return .orange }
        return .green
    }

    private var detailAccentTint: Color {
        if medication.isLowSupply || !maintenanceSummary.isEmpty {
            return .orange
        }
        return reminderStateTint
    }

    private var nextDoseText: String {
        guard medication.isAsNeeded != true else { return NSLocalizedString("PRN", comment: "") }
        guard medication.remindersEnabled else { return NSLocalizedString("Off", comment: "") }

        let calendar = Calendar.current
        let now = Date()
        let sorted = medication.timesOfDay.sorted { ($0.hour ?? 0, $0.minute ?? 0) < ($1.hour ?? 0, $1.minute ?? 0) }
        for offset in 0..<2 {
            guard let day = calendar.date(byAdding: .day, value: offset, to: calendar.startOfDay(for: now)) else { continue }
            for comps in sorted {
                guard let hour = comps.hour,
                      let minute = comps.minute,
                      let scheduled = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day),
                      scheduled >= now else { continue }
                return scheduled.formatted(offset == 0 ? .dateTime.hour().minute() : .dateTime.weekday(.abbreviated).hour().minute())
            }
        }
        return NSLocalizedString("Not scheduled", comment: "")
    }

    private var lastTakenText: String {
        guard let lastTakenLog else { return NSLocalizedString("None", comment: "") }
        let date = lastTakenLog.effectiveRecordedAt
        let cal = Calendar.current
        if cal.isDateInToday(date) {
            return date.formatted(date: .omitted, time: .shortened)
        }
        if cal.isDateInYesterday(date) {
            let time = date.formatted(date: .omitted, time: .shortened)
            return String(format: NSLocalizedString("Yesterday %@", comment: "Yesterday + time"), time)
        }
        // Same year: omit year to save space (e.g. "Apr 15, 8:30 AM" → "4/15 8:30")
        let fmt = DateFormatter()
        if cal.isDate(date, equalTo: Date(), toGranularity: .year) {
            fmt.dateFormat = DateFormatter.dateFormat(fromTemplate: "MdHm", options: 0, locale: Locale.current)
        } else {
            fmt.dateStyle = .short
            fmt.timeStyle = .short
        }
        return fmt.string(from: date)
    }

    private var detailStatusLine: String {
        if medication.isAsNeeded == true {
            return NSLocalizedString("Manual logging only.", comment: "")
        }
        if !medication.remindersEnabled {
            return NSLocalizedString("Fixed reminders are off.", comment: "")
        }
        if medication.timesOfDay.isEmpty {
            return NSLocalizedString("Reminder times need setup.", comment: "")
        }
        return String(format: NSLocalizedString("Next: %@", comment: ""), nextDoseText)
    }

    private var detailHeadline: String {
        if medication.isAsNeeded == true {
            return NSLocalizedString("Take only when needed", comment: "")
        }
        if !medication.remindersEnabled {
            return NSLocalizedString("Reminders are currently off", comment: "")
        }
        if medication.timesOfDay.isEmpty {
            return NSLocalizedString("Schedule needs setup", comment: "")
        }
        return String(format: NSLocalizedString("Next dose at %@", comment: ""), nextDoseText)
    }

    private var detailSupportingLine: String {
        if medication.isAsNeeded == true {
            return NSLocalizedString("Log each dose from Today whenever you take it.", comment: "")
        }
        return scheduleText
    }

    private var reminderSummary: String {
        if medication.isAsNeeded == true {
            return NSLocalizedString("This medication is set to as-needed, so fixed reminders are off.", comment: "")
        }
        if !medication.remindersEnabled {
            return NSLocalizedString("Fixed reminders are turned off for this medication.", comment: "")
        }
        if medication.timesOfDay.isEmpty {
            return NSLocalizedString("No reminder times are set yet.", comment: "")
        }

        let startText = reminderStrategy.leadMinutes > 0
            ? String(format: NSLocalizedString("Starts %lld minutes early", comment: ""), reminderStrategy.leadMinutes)
            : NSLocalizedString("Starts at the scheduled time", comment: "")
        let followUpText = reminderStrategy.followUpIntervals.isEmpty
            ? NSLocalizedString("No follow-up reminders", comment: "")
            : String(format: NSLocalizedString("%lld follow-up reminders", comment: ""), reminderStrategy.followUpIntervals.count)
        return "\(startText) · \(followUpText)"
    }

    private var reminderExplanation: String {
        if medication.isAsNeeded == true {
            return NSLocalizedString("No fixed notifications for PRN medications.", comment: "")
        }
        if !medication.remindersEnabled {
            return NSLocalizedString("Turn reminders on to include this medication in scheduling.", comment: "")
        }
        if reminderProfile.sampleCount == 0 {
            return NSLocalizedString("The reminder pattern will adapt after more scheduled logs.", comment: "")
        }

        switch reminderStrategy.riskLevel {
        case .high:
            return String(format: NSLocalizedString("Higher recent miss risk. Using %lld follow-ups.", comment: ""), reminderStrategy.followUpIntervals.count)
        case .medium:
            return String(format: NSLocalizedString("Some recent delays or snoozes. Using %lld follow-ups.", comment: ""), reminderStrategy.followUpIntervals.count)
        case .low:
            return NSLocalizedString("Recent history looks consistent. Keeping reminders lighter.", comment: "")
        }
    }

    private var reminderRiskLabel: String {
        switch reminderStrategy.riskLevel {
        case .high:
            return NSLocalizedString("High Attention", comment: "")
        case .medium:
            return NSLocalizedString("Balanced", comment: "")
        case .low:
            return NSLocalizedString("Light Touch", comment: "")
        }
    }

    private var reminderRiskTint: Color {
        switch reminderStrategy.riskLevel {
        case .high: return .orange
        case .medium: return .blue
        case .low: return .green
        }
    }

    private var maintenanceSummary: [String] {
        var items: [String] = []
        if let remaining = medication.pillsRemaining {
            if let days = medication.daysOfSupplyRemaining {
                items.append(String(format: NSLocalizedString("%lld pills left, about %lld days remaining.", comment: ""), remaining, days))
            } else {
                items.append(String(format: NSLocalizedString("%lld pills left.", comment: ""), remaining))
            }
        }
        if let courseState = medication.courseState() {
            switch courseState {
            case .ended(let daysPast):
                items.append(String(format: NSLocalizedString("Course ended %lld days ago.", comment: ""), daysPast))
            case .endsToday:
                items.append(NSLocalizedString("Course ends today.", comment: ""))
            case .endingSoon(let daysRemaining):
                items.append(String(format: NSLocalizedString("Course ends in %lld days.", comment: ""), daysRemaining))
            case .scheduled(let daysRemaining):
                items.append(String(format: NSLocalizedString("Course ends in %lld days.", comment: ""), daysRemaining))
            }
        }
        return items
    }

    private var maintenanceTint: Color {
        if medication.isLowSupply { return .orange }
        if let state = medication.courseState() {
            switch state {
            case .ended, .endsToday: return .red
            case .endingSoon: return .orange
            case .scheduled: return .green
            }
        }
        return .green
    }

    private var correlatedTypes: [MeasurementType] {
        (medication.category == .unspecified ? nil : medication.category)?.correlatedMeasurementTypes ?? []
    }

    private func relatedMeasurements(for type: MeasurementType) -> [Measurement]? {
        let data = store.measurements
            .filter { $0.type == type }
            .sorted { $0.date < $1.date }
            .suffix(30)
        return data.count >= 2 ? Array(data) : nil
    }

    private func relatedMeasurementSummary(for type: MeasurementType, data: [Measurement]) -> String {
        guard let latest = data.last else { return NSLocalizedString("No recent readings.", comment: "") }
        if type == .bloodPressure, let dia = latest.diastolic {
            return String(format: NSLocalizedString("Latest: %d/%d mmHg", comment: ""), Int(latest.value), Int(dia))
        }
        if type == .bloodGlucose {
            let preferred = UnitPreferences.mgdlToPreferred(latest.value)
            let formatted = UnitPreferences.glucoseUnit == .mgdL ? String(format: "%.0f", preferred) : String(format: "%.1f", preferred)
            return String(format: NSLocalizedString("Latest: %@ %@", comment: ""), formatted, UnitPreferences.glucoseUnit.rawValue)
        }
        return String(format: NSLocalizedString("Latest: %.1f %@", comment: ""), latest.value, type.unit)
    }

    private func relatedMeasurementTrendText(for type: MeasurementType, data: [Measurement]) -> String {
        guard let first = data.first, let last = data.last else {
            return NSLocalizedString("No recent trend available.", comment: "")
        }
        let delta = last.value - first.value
        let threshold: Double = type == .bloodPressure ? 4 : type == .bloodGlucose ? 8 : 1
        if abs(delta) < threshold {
            return NSLocalizedString("Recent readings look fairly stable.", comment: "")
        }
        return delta < 0
            ? NSLocalizedString("Recent readings are trending lower.", comment: "")
            : NSLocalizedString("Recent readings are trending higher.", comment: "")
    }

    private var hasRelatedMeasurementData: Bool {
        correlatedTypes.contains { relatedMeasurements(for: $0) != nil }
    }

    // MARK: - Hero Card Data

    private struct HeroSnippet {
        let value: String
        let label: String
        let tint: Color
    }

    /// The supply or course countdown shown top-right in the hero card.
    private var heroSupplySnippet: HeroSnippet? {
        // Prioritize supply days if available
        if let days = medication.daysOfSupplyRemaining {
            let tint: Color = days <= 3 ? .red : days <= 7 ? .orange : .green
            return HeroSnippet(
                value: "\(days)",
                label: days == 1
                    ? NSLocalizedString("day left", comment: "supply singular")
                    : NSLocalizedString("days left", comment: "supply plural"),
                tint: tint
            )
        }
        // Fall back to pills count
        if let pills = medication.pillsRemaining {
            let tint: Color = pills <= 10 ? .orange : .green
            return HeroSnippet(
                value: "\(pills)",
                label: NSLocalizedString("pills", comment: "pill count label"),
                tint: tint
            )
        }
        // Fall back to course countdown
        if let state = medication.courseState() {
            switch state {
            case .ended(let d):
                return HeroSnippet(
                    value: "+\(d)",
                    label: NSLocalizedString("days past", comment: "course ended"),
                    tint: .red
                )
            case .endsToday:
                return HeroSnippet(
                    value: NSLocalizedString("Today", comment: ""),
                    label: NSLocalizedString("ends", comment: "course ends today"),
                    tint: .orange
                )
            case .endingSoon(let d), .scheduled(let d):
                let tint: Color = d <= 3 ? .orange : .blue
                return HeroSnippet(
                    value: "\(d)",
                    label: d == 1
                        ? NSLocalizedString("day left", comment: "course singular")
                        : NSLocalizedString("days left", comment: "course plural"),
                    tint: tint
                )
            }
        }
        return nil
    }

    private struct HeroAttribute: Hashable {
        let icon: String
        let label: String
        let tint: Color
        func hash(into hasher: inout Hasher) { hasher.combine(label) }
        static func == (lhs: HeroAttribute, rhs: HeroAttribute) -> Bool { lhs.label == rhs.label }
    }

    /// Compact attribute rows shown in the hero card body.
    private var heroAttributes: [HeroAttribute] {
        var attrs: [HeroAttribute] = []

        // Schedule
        if medication.isAsNeeded == true {
            attrs.append(HeroAttribute(
                icon: "hand.tap",
                label: NSLocalizedString("As needed — log when taken", comment: ""),
                tint: .blue
            ))
        } else if !medication.timesOfDay.isEmpty {
            attrs.append(HeroAttribute(
                icon: "clock",
                label: scheduleText,
                tint: .blue
            ))
        }

        // Special instructions
        if let si = medication.specialInstructions, !si.trimmingCharacters(in: .whitespaces).isEmpty {
            attrs.append(HeroAttribute(
                icon: "exclamationmark.triangle",
                label: si,
                tint: .yellow
            ))
        }

        // Course date range
        if let endDate = medication.courseEndDate {
            let fmt = DateFormatter()
            fmt.dateStyle = .medium
            fmt.timeStyle = .none
            let startStr = fmt.string(from: medication.startDate)
            let endStr = fmt.string(from: endDate)
            attrs.append(HeroAttribute(
                icon: "calendar",
                label: "\(startStr) → \(endStr)",
                tint: .purple
            ))
        }

        return attrs
    }

    @ViewBuilder
    private var heroMedicationThumbnail: some View {
        if let path = medication.imagePath, let ui = loadMedicationImage(path: path) {
            Image(uiImage: ui)
                .resizable()
                .scaledToFill()
                .frame(width: 52, height: 52)
                .clipShape(RoundedRectangle(cornerRadius: AppRadius.panel, style: .continuous))
        } else {
            RoundedRectangle(cornerRadius: AppRadius.panel, style: .continuous)
                .fill(detailAccentTint.opacity(0.14))
                .frame(width: 52, height: 52)
                .overlay(
                    Image(systemName: medication.isAsNeeded == true ? "cross.case.circle.fill" : "pills.fill")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(detailAccentTint)
                )
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    TintedCard(tint: detailAccentTint) {
                        VStack(alignment: .leading, spacing: 14) {
                            // Row 1: Icon + Name/Dose (left) + Supply snapshot (right)
                            HStack(alignment: .top, spacing: 12) {
                                heroMedicationThumbnail
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(medication.name)
                                        .appFont(.title)
                                        .fontWeight(.bold)
                                        .lineLimit(2)
                                    Text(medication.dose)
                                        .appFont(.headline)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer(minLength: 4)
                                // Supply / course countdown on the right
                                if let snippet = heroSupplySnippet {
                                    VStack(alignment: .trailing, spacing: 2) {
                                        Text(snippet.value)
                                            .appFont(.title)
                                            .fontWeight(.bold)
                                            .foregroundStyle(snippet.tint)
                                            .monospacedDigit()
                                        Text(snippet.label)
                                            .appFont(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }

                            // Row 2: Key attributes (compact info rows)
                            if !heroAttributes.isEmpty {
                                VStack(alignment: .leading, spacing: 6) {
                                    ForEach(heroAttributes, id: \.label) { attr in
                                        HStack(spacing: 6) {
                                            Image(systemName: attr.icon)
                                                .font(.system(size: 12, weight: .medium))
                                                .foregroundStyle(attr.tint)
                                                .frame(width: 16)
                                            Text(attr.label)
                                                .appFont(.subheadline)
                                                .foregroundStyle(.primary)
                                        }
                                    }
                                }
                            }

                            // Row 3: Tags
                            FlowLayout(spacing: 6) {
                                reminderBadge(reminderStateLabel, tint: reminderStateTint)
                                reminderBadge(modeLabel, tint: modeTint)
                                if let categoryName = medication.displayCategoryName {
                                    reminderBadge(categoryName, tint: .secondary)
                                }
                            }
                        }
                    }

                    Card {
                        VStack(alignment: .leading, spacing: 14) {
                            HStack {
                                Text(NSLocalizedString("Next Dose", comment: ""))
                                    .appFont(.headline)
                                Spacer()
                                reminderBadge(detailStatusLine, tint: reminderStateTint)
                            }
                            LazyVGrid(columns: snapshotColumns, spacing: 10) {
                                detailMetric(value: nextDoseText, label: NSLocalizedString("Scheduled", comment: ""), tint: .blue)
                                detailMetric(value: lastTakenText, label: NSLocalizedString("Last taken", comment: ""), tint: .green)
                            }
                            InsetPanel(tint: reminderRiskTint) {
                                VStack(alignment: .leading, spacing: 6) {
                                    HStack {
                                        Text(NSLocalizedString("Reminder Strategy", comment: ""))
                                            .appFont(.subheadline)
                                            .fontWeight(.semibold)
                                        Spacer()
                                        reminderBadge(reminderRiskLabel, tint: reminderRiskTint)
                                    }
                                    Text(reminderSummary)
                                        .appFont(.caption)
                                        .foregroundStyle(.secondary)
                                        .fixedSize(horizontal: false, vertical: true)
                                    Text(reminderExplanation)
                                        .appFont(.caption)
                                        .foregroundStyle(.secondary)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                            if medication.isAsNeeded != true && (!medication.remindersEnabled || medication.timesOfDay.isEmpty) {
                                Button(NSLocalizedString("Fix Reminder Setup", comment: "")) {
                                    onEdit(medication)
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                            }
                        }
                    }

                    Card {
                        VStack(alignment: .leading, spacing: 14) {
                            Text(NSLocalizedString("Adherence", comment: ""))
                                .appFont(.headline)
                            LazyVGrid(columns: snapshotColumns, spacing: 10) {
                                detailMetric(value: String(format: "%.0f%%", adherence7 * 100), label: NSLocalizedString("7-day", comment: ""), tint: adherence7 >= 0.8 ? .green : adherence7 >= 0.5 ? .orange : .red)
                                detailMetric(value: String(format: "%.0f%%", adherence30 * 100), label: NSLocalizedString("30-day", comment: ""), tint: adherence30 >= 0.8 ? .green : adherence30 >= 0.5 ? .orange : .red)
                                detailMetric(value: "\(streakCount)", label: NSLocalizedString("day streak", comment: ""), tint: .blue)
                                detailMetric(value: "\(monthlyTakenCount)", label: NSLocalizedString("this month", comment: ""), tint: .purple)
                            }

                            NavigationLink {
                                AdherenceCalendarView(medicationID: medication.id)
                            } label: {
                                InsetPanel {
                                    HStack {
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(NSLocalizedString("Adherence History", comment: ""))
                                                .appFont(.headline)
                                            Text(NSLocalizedString("Review daily check-ins and missed doses.", comment: ""))
                                                .appFont(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                        Spacer()
                                        Image(systemName: "chevron.right")
                                            .font(.system(size: 12, weight: .semibold))
                                            .foregroundStyle(.tertiary)
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    if correlatedTypes.isEmpty {
                        Card {
                            EmptyStateView(
                                systemImage: "waveform.badge.questionmark",
                                title: NSLocalizedString("No linked health signals", comment: ""),
                                subtitle: NSLocalizedString("Choose a medication category if you want this page to connect the medication with related measurements like blood pressure or glucose.", comment: "")
                            )
                        }
                    }

                    ForEach(correlatedTypes, id: \.self) { measurementType in
                        if let data = relatedMeasurements(for: measurementType) {
                            Card {
                                VStack(alignment: .leading, spacing: 12) {
                                    HStack {
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(NSLocalizedString("Related Measurements", comment: ""))
                                                .appFont(.headline)
                                            Text(measurementType.displayName)
                                                .appFont(.subheadline)
                                                .foregroundStyle(measurementType.tint)
                                        }
                                        Spacer()
                                        Text(relatedMeasurementSummary(for: measurementType, data: data))
                                            .appFont(.caption)
                                            .foregroundStyle(.secondary)
                                    }

                                    InsetPanel(tint: measurementType.tint) {
                                        Chart(data) { measurement in
                                            LineMark(
                                                x: .value("Date", measurement.date),
                                                y: .value("Value", measurement.value)
                                            )
                                            .foregroundStyle(measurementType.tint)
                                            .interpolationMethod(.catmullRom)

                                            PointMark(
                                                x: .value("Date", measurement.date),
                                                y: .value("Value", measurement.value)
                                            )
                                            .foregroundStyle(measurementType.tint)
                                            .symbolSize(18)
                                        }
                                        .frame(height: 120)
                                        .chartXAxis(.hidden)
                                        .chartYAxis {
                                            AxisMarks(position: .leading, values: .automatic(desiredCount: 3))
                                        }
                                    }

                                    Text(relatedMeasurementTrendText(for: measurementType, data: data))
                                        .appFont(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }

                    if !correlatedTypes.isEmpty && !hasRelatedMeasurementData {
                        Card {
                            EmptyStateView(
                                systemImage: "waveform.path.ecg.rectangle",
                                title: NSLocalizedString("No related measurements yet", comment: ""),
                                subtitle: NSLocalizedString("Log measurements like blood pressure or glucose to see whether this medication lines up with recent trends.", comment: "")
                            )
                        }
                    }

                    if !maintenanceSummary.isEmpty {
                        Card {
                            VStack(alignment: .leading, spacing: 10) {
                                Text(NSLocalizedString("Maintenance", comment: ""))
                                    .appFont(.headline)
                                InsetPanel(tint: maintenanceTint) {
                                    VStack(alignment: .leading, spacing: 10) {
                                        ForEach(maintenanceSummary, id: \.self) { item in
                                            HStack(alignment: .top, spacing: 8) {
                                                Circle()
                                                    .fill(Color.secondary.opacity(0.45))
                                                    .frame(width: 5, height: 5)
                                                    .padding(.top, 7)
                                                Text(item)
                                                    .appFont(.subheadline)
                                                    .foregroundStyle(.secondary)
                                                    .fixedSize(horizontal: false, vertical: true)
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }

                }
                .padding(16)
            }
            .navigationTitle(NSLocalizedString("Medication Detail", comment: ""))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(NSLocalizedString("Edit", comment: "")) {
                        onEdit(medication)
                    }
                }
            }
        }
    }

    private func detailMetric(value: String, label: String, tint: Color) -> some View {
        InsetPanel(tint: tint) {
            VStack(alignment: .leading, spacing: 4) {
                Text(value)
                    .appFontNumeric(.headline)
                    .foregroundStyle(tint)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Text(label)
                    .appFont(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, minHeight: 40, alignment: .leading)
        }
    }

    private func reminderBadge(_ text: String, tint: Color) -> some View {
        AppBadge(text: text, tint: tint)
    }
}
