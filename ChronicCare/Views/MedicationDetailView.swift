import SwiftUI
import Charts

// MARK: - MedicationDetailView

struct MedicationDetailView: View {
    @EnvironmentObject var store: DataStore
    let medication: Medication
    let onEdit: (Medication) -> Void
    private let snapshotColumns = [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)]

    private var lastTakenLog: IntakeLog? {
        store.intakeLogs
            .filter { $0.medicationID == medication.id && $0.status == .taken }
            .max(by: { $0.effectiveRecordedAt < $1.effectiveRecordedAt })
    }

    private var adherence30: Double {
        store.adherencePercent(for: medication.id, days: 30)
    }

    private var streakCount: Int {
        store.currentStreak(for: medication.id)
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
        medication.isAsNeeded == true ? AppColor.textSecondary : AppColor.primary
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
        if medication.isAsNeeded == true { return AppColor.textSecondary }
        if !medication.remindersEnabled || medication.timesOfDay.isEmpty { return AppColor.warning }
        return AppColor.primary
    }

    private var detailAccentTint: Color {
        if medication.isLowSupply {
            return AppColor.warning
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
        if let trend = weeklyMeasurementTrend(for: type, data: data) {
            let threshold: Double = type == .bloodPressure ? 4 : type == .bloodGlucose ? 8 : 1
            if abs(trend.change) < threshold {
                return String(format: NSLocalizedString("Recent average is stable at %@ compared with the previous week.", comment: "Outcome trend stable text"), formattedMeasurementAverage(trend.recentAverage, type: type))
            }
            let direction = trend.change < 0
                ? NSLocalizedString("lower", comment: "Measurement trend direction")
                : NSLocalizedString("higher", comment: "Measurement trend direction")
            return String(
                format: NSLocalizedString("Recent average is %@, %@ by %@ from the previous week.", comment: "Outcome trend comparison text"),
                formattedMeasurementAverage(trend.recentAverage, type: type),
                direction,
                formattedMeasurementDelta(abs(trend.change), type: type)
            )
        }

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

    private struct WeeklyMeasurementTrend {
        let recentAverage: Double
        let previousAverage: Double
        let recentCount: Int
        let previousCount: Int

        var change: Double {
            recentAverage - previousAverage
        }
    }

    private func weeklyMeasurementTrend(for type: MeasurementType, data: [Measurement], now: Date = Date()) -> WeeklyMeasurementTrend? {
        let cal = Calendar.current
        guard let sevenDaysAgo = cal.date(byAdding: .day, value: -7, to: now),
              let fourteenDaysAgo = cal.date(byAdding: .day, value: -14, to: now) else { return nil }

        let recentValues = data
            .filter { $0.date >= sevenDaysAgo && $0.date <= now }
            .map(\.value)
        let previousValues = data
            .filter { $0.date >= fourteenDaysAgo && $0.date < sevenDaysAgo }
            .map(\.value)

        guard recentValues.count >= 2, previousValues.count >= 2 else { return nil }
        let recentAverage = recentValues.reduce(0, +) / Double(recentValues.count)
        let previousAverage = previousValues.reduce(0, +) / Double(previousValues.count)
        return WeeklyMeasurementTrend(
            recentAverage: recentAverage,
            previousAverage: previousAverage,
            recentCount: recentValues.count,
            previousCount: previousValues.count
        )
    }

    private func formattedMeasurementAverage(_ value: Double, type: MeasurementType) -> String {
        if type == .bloodGlucose {
            let preferred = UnitPreferences.mgdlToPreferred(value)
            let formatted = UnitPreferences.glucoseUnit == .mgdL ? String(format: "%.0f", preferred) : String(format: "%.1f", preferred)
            return "\(formatted) \(UnitPreferences.glucoseUnit.rawValue)"
        }
        if type == .bloodPressure {
            return String(format: NSLocalizedString("%.0f mmHg systolic", comment: "Systolic blood pressure average"), value)
        }
        return String(format: "%.1f %@", value, type.unit)
    }

    private func formattedMeasurementDelta(_ value: Double, type: MeasurementType) -> String {
        if type == .bloodGlucose {
            let preferred = UnitPreferences.mgdlToPreferred(value)
            let formatted = UnitPreferences.glucoseUnit == .mgdL ? String(format: "%.0f", preferred) : String(format: "%.1f", preferred)
            return "\(formatted) \(UnitPreferences.glucoseUnit.rawValue)"
        }
        if type == .bloodPressure {
            return String(format: NSLocalizedString("%.0f mmHg", comment: "Blood pressure delta"), value)
        }
        return String(format: "%.1f %@", value, type.unit)
    }

    private func outcomeLinkageContextText(for type: MeasurementType) -> String {
        let cal = Calendar.current
        let now = Date()
        guard let fourteenDaysAgo = cal.date(byAdding: .day, value: -14, to: now) else {
            return NSLocalizedString("Trend context only; this does not prove the medication caused the change.", comment: "Outcome trend disclaimer")
        }

        let readingCount = store.measurements.filter {
            $0.type == type && $0.date >= fourteenDaysAgo && $0.date <= now
        }.count
        let takenCount = store.intakeLogs.filter {
            $0.medicationID == medication.id &&
            $0.status == .taken &&
            $0.effectiveRecordedAt >= fourteenDaysAgo &&
            $0.effectiveRecordedAt <= now
        }.count

        return String(
            format: NSLocalizedString("Trend context only: %lld readings and %lld taken logs in the past 14 days; this does not prove the medication caused the change.", comment: "Outcome trend disclaimer with counts"),
            readingCount,
            takenCount
        )
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
            let tint: Color = days <= 7 ? AppColor.warning : AppColor.primary
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
            let tint: Color = pills <= 10 ? AppColor.warning : AppColor.primary
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
                    tint: AppColor.warning
                )
            case .endsToday:
                return HeroSnippet(
                    value: NSLocalizedString("Today", comment: ""),
                    label: NSLocalizedString("ends", comment: "course ends today"),
                    tint: AppColor.warning
                )
            case .endingSoon(let d), .scheduled(let d):
                let tint: Color = d <= 3 ? AppColor.warning : AppColor.primary
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
                tint: AppColor.textSecondary
            ))
        } else if !medication.timesOfDay.isEmpty {
            attrs.append(HeroAttribute(
                icon: "clock",
                label: scheduleText,
                tint: AppColor.primary
            ))
        }

        // Special instructions
        if let si = medication.specialInstructions, !si.trimmingCharacters(in: .whitespaces).isEmpty {
            attrs.append(HeroAttribute(
                icon: "exclamationmark.triangle",
                label: si,
                tint: AppColor.warning
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
                tint: AppColor.textSecondary
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
                .fill(AppColor.surface)
                .frame(width: 52, height: 52)
                .overlay(
                    Image(systemName: medication.isAsNeeded == true ? "cross.case.circle" : "pills")
                        .font(.system(size: 22, weight: .regular))
                        .foregroundStyle(detailAccentTint)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: AppRadius.panel, style: .continuous)
                        .stroke(AppColor.divider, lineWidth: 1)
                )
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: EditorialSpacing.xl) {
                    medicationOverviewSection
                    nextDoseSection
                    adherenceSection

                    ForEach(correlatedTypes, id: \.self) { measurementType in
                        if let data = relatedMeasurements(for: measurementType) {
                            relatedMeasurementCard(for: measurementType, data: data)
                        }
                    }

                }
                .padding(16)
            }
            .background(AppColor.background)
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

    private var medicationOverviewSection: some View {
        VStack(alignment: .leading, spacing: EditorialSpacing.md) {
            HStack(alignment: .top, spacing: EditorialSpacing.md) {
                heroMedicationThumbnail

                VStack(alignment: .leading, spacing: EditorialSpacing.xs) {
                    Text(medication.name)
                        .appFont(.displayTitle)
                        .foregroundStyle(AppColor.textPrimary)
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(medication.dose)
                        .appFont(.headline)
                        .foregroundStyle(AppColor.textSecondary)
                }

                Spacer(minLength: EditorialSpacing.sm)

                if let snippet = heroSupplySnippet {
                    VStack(alignment: .trailing, spacing: EditorialSpacing.xs) {
                        Text(snippet.value)
                            .appFontNumeric(.title)
                            .fontWeight(.bold)
                            .foregroundStyle(snippet.tint)
                        Text(snippet.label)
                            .appFont(.caption)
                            .foregroundStyle(AppColor.textSecondary)
                    }
                }
            }

            if !heroAttributes.isEmpty {
                AppDivider()

                VStack(alignment: .leading, spacing: EditorialSpacing.sm) {
                    ForEach(heroAttributes, id: \.label) { attr in
                        HStack(spacing: EditorialSpacing.sm) {
                            Image(systemName: attr.icon)
                                .font(.system(size: 14, weight: .regular))
                                .foregroundStyle(attr.tint)
                                .frame(width: 18)
                            Text(attr.label)
                                .appFont(.body)
                                .foregroundStyle(AppColor.textPrimary)
                        }
                    }
                }
            }

            FlowLayout(spacing: EditorialSpacing.sm) {
                reminderBadge(reminderStateLabel, tint: reminderStateTint)
                reminderBadge(modeLabel, tint: modeTint)
                if let categoryName = medication.displayCategoryName {
                    reminderBadge(categoryName, tint: AppColor.textSecondary)
                }
            }
        }
    }

    private var nextDoseSection: some View {
        VStack(alignment: .leading, spacing: EditorialSpacing.md) {
            sectionHeader(
                title: NSLocalizedString("Next Dose", comment: ""),
                trailing: detailStatusLine,
                trailingTint: reminderStateTint
            )

            AppDivider()

            LazyVGrid(columns: snapshotColumns, spacing: EditorialSpacing.md) {
                detailMetric(value: nextDoseText, label: NSLocalizedString("Scheduled", comment: ""), tint: AppColor.primary)
                detailMetric(value: lastTakenText, label: NSLocalizedString("Last taken", comment: ""), tint: AppColor.textSecondary)
            }

            if medication.isAsNeeded != true && (!medication.remindersEnabled || medication.timesOfDay.isEmpty) {
                Button {
                    Haptics.impact(.light)
                    onEdit(medication)
                } label: {
                    Label(NSLocalizedString("Fix Reminder Setup", comment: ""), systemImage: "bell.badge")
                        .appFont(.body)
                        .foregroundStyle(AppColor.primary)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(AppColor.divider, lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var adherenceSection: some View {
        VStack(alignment: .leading, spacing: EditorialSpacing.md) {
            sectionHeader(title: NSLocalizedString("Adherence", comment: ""))

            AppDivider()

            LazyVGrid(columns: snapshotColumns, spacing: EditorialSpacing.md) {
                detailMetric(
                    value: String(format: "%.0f%%", adherence30 * 100),
                    label: NSLocalizedString("30-day", comment: ""),
                    tint: adherence30 >= 0.5 ? AppColor.primary : AppColor.warning
                )
                detailMetric(
                    value: "\(streakCount)",
                    label: NSLocalizedString("day streak", comment: ""),
                    tint: AppColor.textSecondary
                )
            }

            NavigationLink {
                AdherenceCalendarView(medicationID: medication.id)
            } label: {
                HStack(spacing: EditorialSpacing.md) {
                    VStack(alignment: .leading, spacing: EditorialSpacing.xs) {
                        Text(NSLocalizedString("Adherence History", comment: ""))
                            .appFont(.body)
                            .foregroundStyle(AppColor.textPrimary)
                        Text(NSLocalizedString("Review daily check-ins and missed doses.", comment: ""))
                            .appFont(.caption)
                            .foregroundStyle(AppColor.textSecondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(AppColor.textTertiary)
                }
                .padding(.vertical, EditorialSpacing.sm)
            }
            .buttonStyle(EditorialRowButtonStyle())
        }
    }

    private func sectionHeader(title: String, trailing: String? = nil, trailingTint: Color = AppColor.textSecondary) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .appFont(.headline)
                .foregroundStyle(AppColor.textPrimary)
            Spacer()
            if let trailing {
                Text(trailing)
                    .appFont(.caption)
                    .foregroundStyle(trailingTint)
            }
        }
    }

    private func relatedMeasurementCard(for measurementType: MeasurementType, data: [Measurement]) -> some View {
        let summary = relatedMeasurementSummary(for: measurementType, data: data)
        let trendText = relatedMeasurementTrendText(for: measurementType, data: data)
        let contextText = outcomeLinkageContextText(for: measurementType)

        return VStack(alignment: .leading, spacing: EditorialSpacing.md) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: EditorialSpacing.xs) {
                    Text(NSLocalizedString("Related Measurements", comment: ""))
                        .appFont(.headline)
                        .foregroundStyle(AppColor.textPrimary)
                    Text(measurementType.displayName)
                        .appFont(.caption)
                        .foregroundStyle(AppColor.primary)
                }
                Spacer()
                Text(summary)
                    .appFont(.caption)
                    .foregroundStyle(AppColor.textSecondary)
            }

            AppDivider()

            relatedMeasurementChart(for: measurementType, data: data)
                .padding(.vertical, EditorialSpacing.sm)

            Text(trendText)
                .appFont(.caption)
                .foregroundStyle(AppColor.textSecondary)
            Text(contextText)
                .font(.caption2)
                .foregroundStyle(AppColor.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            }
    }

    private func relatedMeasurementChart(for measurementType: MeasurementType, data: [Measurement]) -> some View {
        Chart(data) { measurement in
            LineMark(
                x: .value("Date", measurement.date),
                y: .value("Value", measurement.value)
            )
            .foregroundStyle(AppColor.primary)
            .interpolationMethod(.catmullRom)

            PointMark(
                x: .value("Date", measurement.date),
                y: .value("Value", measurement.value)
            )
            .foregroundStyle(AppColor.primary)
            .symbolSize(18)
        }
        .frame(height: 120)
        .chartXAxis(.hidden)
        .chartYAxis {
            AxisMarks(position: .leading, values: .automatic(desiredCount: 3))
        }
    }

    private func detailMetric(value: String, label: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: EditorialSpacing.xs) {
            Text(value)
                .appFontNumeric(.headline)
                .foregroundStyle(tint)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Text(label)
                .appFont(.caption)
                .foregroundStyle(AppColor.textSecondary)
        }
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
    }

    private func reminderBadge(_ text: String, tint: Color) -> some View {
        AppBadge(text: text, tint: tint)
    }
}
