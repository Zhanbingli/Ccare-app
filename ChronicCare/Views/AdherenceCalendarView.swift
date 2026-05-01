import SwiftUI

struct AdherenceCalendarView: View {
    @EnvironmentObject var store: DataStore
    var medicationID: UUID? = nil

    @State private var displayedMonth: Date = Date()
    @State private var selectedDay: Date?
    @State private var deleteTarget: IntakeLog?

    private let calendar = Calendar.current
    private let weekdaySymbols: [String] = {
        let f = DateFormatter()
        f.locale = Locale.current
        return f.veryShortWeekdaySymbols
    }()

    private var year: Int { calendar.component(.year, from: displayedMonth) }
    private var month: Int { calendar.component(.month, from: displayedMonth) }

    private var monthTitle: String {
        let f = DateFormatter()
        f.dateFormat = "LLLL yyyy"
        return f.string(from: displayedMonth)
    }

    var body: some View {
        let adherenceData = store.monthlyAdherence(for: medicationID, year: year, month: month)
        let monthStats = computeMonthStats(adherenceData)

        ScrollView {
            VStack(spacing: 14) {
                // Month navigation
                HStack {
                    Button { shiftMonth(-1) } label: {
                        Image(systemName: "chevron.left")
                            .font(.body.weight(.semibold))
                            .frame(width: 36, height: 36)
                    }
                    Spacer()
                    Text(monthTitle)
                        .appFont(.headline)
                    Spacer()
                    Button { shiftMonth(1) } label: {
                        Image(systemName: "chevron.right")
                            .font(.body.weight(.semibold))
                            .frame(width: 36, height: 36)
                    }
                    .disabled(isCurrentMonth)
                }
                .padding(.horizontal)

                // Weekday headers
                HStack(spacing: 0) {
                    ForEach(Array(weekdaySymbols.enumerated()), id: \.offset) { _, sym in
                        Text(sym)
                            .appFont(.caption)
                            .fontWeight(.medium)
                            .foregroundStyle(AppColor.textSecondary)
                            .frame(maxWidth: .infinity)
                    }
                }
                .padding(.horizontal, 8)

                // Calendar grid
                let days = calendarDays()
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 0), count: 7), spacing: 8) {
                    ForEach(Array(days.enumerated()), id: \.offset) { _, day in
                        if let day = day {
                            let data = adherenceData[calendar.startOfDay(for: day)]
                            calendarCell(day: day, data: data)
                                .onTapGesture {
                                    withAnimation(.easeInOut(duration: 0.2)) {
                                        if selectedDay == day {
                                            selectedDay = nil
                                        } else if data != nil {
                                            selectedDay = day
                                        }
                                    }
                                }
                        } else {
                            Color.clear.frame(height: 44)
                        }
                    }
                }
                .padding(.horizontal, 8)

                // Legend + stats in one line
                if monthStats.totalDays > 0 {
                    HStack(spacing: 8) {
                        legendItem(color: AppColor.primary, label: NSLocalizedString("All Taken", comment: ""))
                        legendItem(color: AppColor.textSecondary, label: NSLocalizedString("Partial", comment: ""))
                        legendItem(color: AppColor.warning, label: NSLocalizedString("Missed", comment: ""))
                        Spacer()
                        Text(String(format: "%.0f%%", monthStats.avgPercent * 100))
                            .appFont(.caption)
                            .fontWeight(.bold)
                            .foregroundStyle(AppColor.textPrimary)
                        Text(NSLocalizedString("Avg", comment: ""))
                            .appFont(.caption)
                            .foregroundStyle(AppColor.textSecondary)
                    }
                    .padding(.horizontal, AppSpacing.small)
                    .padding(.vertical, AppSpacing.xSmall)
                    .background(
                        RoundedRectangle(cornerRadius: AppRadius.small, style: .continuous)
                            .fill(AppColor.surface)
                            .overlay(
                                RoundedRectangle(cornerRadius: AppRadius.small, style: .continuous)
                                    .stroke(AppColor.divider, lineWidth: 1)
                            )
                    )
                    .padding(.horizontal)
                } else {
                    Text(NSLocalizedString("No medication data for this month.", comment: ""))
                        .appFont(.caption)
                        .foregroundStyle(AppColor.textSecondary)
                        .padding(.vertical, 12)
                }

                // Inline day detail (no sheet)
                if let day = selectedDay {
                    dayDetailInline(date: day)
                        .id(day)
                        .transition(.opacity)
                }
            }
            .padding(.vertical)
        }
        .background(AppColor.background)
        .navigationTitle(NSLocalizedString("Adherence Calendar", comment: ""))
        .navigationBarTitleDisplayMode(.inline)
        .alert(NSLocalizedString("Delete Intake Log", comment: ""), isPresented: deleteConfirmationBinding) {
            Button(NSLocalizedString("Delete", comment: ""), role: .destructive) {
                deleteSelectedIntakeLog()
            }
            Button(NSLocalizedString("Cancel", comment: ""), role: .cancel) {
                deleteTarget = nil
            }
        } message: {
            Text(NSLocalizedString("This intake record will be removed from adherence history and future visit summaries.", comment: ""))
        }
    }

    // MARK: - Helpers

    private var deleteConfirmationBinding: Binding<Bool> {
        Binding(
            get: { deleteTarget != nil },
            set: { if !$0 { deleteTarget = nil } }
        )
    }

    private var isCurrentMonth: Bool {
        calendar.isDate(displayedMonth, equalTo: Date(), toGranularity: .month)
    }

    private func shiftMonth(_ offset: Int) {
        if let newDate = calendar.date(byAdding: .month, value: offset, to: displayedMonth) {
            withAnimation(.easeInOut(duration: 0.2)) {
                displayedMonth = newDate
                selectedDay = nil
            }
        }
    }

    private func calendarDays() -> [Date?] {
        guard let monthStart = calendar.date(from: DateComponents(year: year, month: month, day: 1)),
              let range = calendar.range(of: .day, in: .month, for: monthStart) else { return [] }
        let firstWeekday = calendar.component(.weekday, from: monthStart)
        let leadingBlanks = (firstWeekday - calendar.firstWeekday + 7) % 7
        var days: [Date?] = Array(repeating: nil, count: leadingBlanks)
        for d in range {
            days.append(calendar.date(from: DateComponents(year: year, month: month, day: d)))
        }
        return days
    }

    // MARK: - Calendar Cell

    @ViewBuilder
    private func calendarCell(day: Date, data: (taken: Int, total: Int)?) -> some View {
        let dayNum = calendar.component(.day, from: day)
        let isToday = calendar.isDateInToday(day)
        let isSelected = selectedDay == day

        ZStack {
            // Background fill based on adherence
            RoundedRectangle(cornerRadius: AppRadius.small)
                .fill(cellFill(data: data))
                .frame(height: 44)

            // Today ring
            if isToday {
                RoundedRectangle(cornerRadius: AppRadius.small)
                    .strokeBorder(AppColor.primary, lineWidth: 2)
                    .frame(height: 44)
            }

            // Selected highlight
            if isSelected {
                RoundedRectangle(cornerRadius: AppRadius.small)
                    .strokeBorder(AppColor.textPrimary.opacity(0.4), lineWidth: 1.5)
                    .frame(height: 44)
            }

            // Day number + indicator dot
            VStack(spacing: 3) {
                Text("\(dayNum)")
                    .appFont(.caption)
                    .fontWeight(isToday ? .bold : .regular)
                    .foregroundStyle(data != nil ? AppColor.textPrimary : AppColor.textTertiary)

                // Small dot indicator
                Circle()
                    .fill(cellDotColor(data: data))
                    .frame(width: 5, height: 5)
                    .opacity((data?.total ?? 0) > 0 ? 1 : 0)
            }
        }
    }

    private func cellFill(data: (taken: Int, total: Int)?) -> Color {
        guard let data = data, data.total > 0 else { return AppColor.surface }
        let pct = Double(data.taken) / Double(data.total)
        if pct >= 1.0 { return AppColor.primary.opacity(0.12) }
        if pct > 0 { return AppColor.textSecondary.opacity(0.10) }
        return AppColor.warning.opacity(0.10)
    }

    private func cellDotColor(data: (taken: Int, total: Int)?) -> Color {
        guard let data = data, data.total > 0 else { return .clear }
        let pct = Double(data.taken) / Double(data.total)
        if pct >= 1.0 { return AppColor.primary }
        if pct > 0 { return AppColor.textSecondary }
        return AppColor.warning
    }

    // MARK: - Legend

    private func legendItem(color: Color, label: String) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(label)
                .appFont(.caption)
                .foregroundStyle(AppColor.textSecondary)
        }
    }

    // MARK: - Month Stats

    private struct MonthStats {
        let totalDays: Int
        let avgPercent: Double
        let perfectDays: Int
        let missedDays: Int
    }

    private func computeMonthStats(_ data: [Date: (taken: Int, total: Int)]) -> MonthStats {
        let entries = data.values.filter { $0.total > 0 }
        guard !entries.isEmpty else { return MonthStats(totalDays: 0, avgPercent: 0, perfectDays: 0, missedDays: 0) }
        let pcts = entries.map { Double($0.taken) / Double($0.total) }
        let avg = pcts.reduce(0, +) / Double(pcts.count)
        let perfect = pcts.filter { $0 >= 1.0 }.count
        let missed = pcts.filter { $0 == 0 }.count
        return MonthStats(totalDays: entries.count, avgPercent: avg, perfectDays: perfect, missedDays: missed)
    }

    // MARK: - Inline Day Detail

    @ViewBuilder
    private func dayDetailInline(date: Date) -> some View {
        let logs = store.intakeLogs(for: date, medicationID: medicationID)
        let meds = medicationID != nil ? store.medications.filter { $0.id == medicationID } : store.medications

        VStack(alignment: .leading, spacing: 0) {
            // Day header
            HStack {
                Text(dayTitle(date))
                    .appFont(.subheadline)
                    .foregroundStyle(.primary)
                Spacer()
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) { selectedDay = nil }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)

            Divider().padding(.horizontal, 14)

            if logs.isEmpty {
                Text(NSLocalizedString("No intake logs for this day.", comment: ""))
                    .appFont(.caption)
                    .foregroundStyle(.secondary)
                    .padding(14)
            } else {
                VStack(spacing: 0) {
                    ForEach(meds) { med in
                        let medLogs = logs.filter { $0.medicationID == med.id }
                        if !medLogs.isEmpty {
                            ForEach(medLogs) { log in
                                intakeLogRow(log: log, medication: med)
                            }
                        }
                    }

                    // Medications with no logs
                    let loggedMedIDs = Set(logs.map { $0.medicationID })
                    let missedMeds = meds.filter { !loggedMedIDs.contains($0.id) && $0.remindersEnabled }
                    ForEach(missedMeds) { med in
                        HStack(spacing: 10) {
                            Image(systemName: "minus.circle")
                                .font(.system(size: 16))
                                .foregroundStyle(AppColor.textSecondary)
                                .frame(width: 20)
                            Text(med.name)
                                .appFont(.subheadline)
                                .foregroundStyle(AppColor.textSecondary)
                            Spacer()
                            Text(NSLocalizedString("No Record", comment: ""))
                                .appFont(.caption)
                                .foregroundStyle(AppColor.textTertiary)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 6)
                    }
                }
            }
        }
        .background(
            RoundedRectangle(cornerRadius: AppRadius.medium, style: .continuous)
                .fill(AppColor.surface)
                .overlay(
                    RoundedRectangle(cornerRadius: AppRadius.medium, style: .continuous)
                        .stroke(AppColor.divider, lineWidth: 1)
                )
        )
        .padding(.horizontal)
    }

    private func intakeLogRow(log: IntakeLog, medication: Medication) -> some View {
        HStack(spacing: 10) {
            statusIcon(log.status)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 2) {
                Text(medication.name)
                    .appFont(.subheadline)
                Text(medication.dose)
                    .appFont(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text(timeString(log.date))
                    .appFont(.caption)
                    .foregroundStyle(.secondary)
                Text(statusText(log.status))
                    .font(.caption2)
                    .foregroundStyle(AppColor.textTertiary)
            }

            Button(role: .destructive) {
                deleteTarget = log
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 14, weight: .regular))
                    .foregroundStyle(AppColor.warning)
                    .frame(width: 32, height: 32)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(NSLocalizedString("Delete Intake Log", comment: ""))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
    }

    private func deleteSelectedIntakeLog() {
        guard let deleteTarget else { return }
        store.removeIntakeLog(deleteTarget)
        store.syncNotifications()
        self.deleteTarget = nil
        Haptics.notification(.warning)
    }

    private func dayTitle(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateStyle = .medium
        return f.string(from: date)
    }

    private func timeString(_ date: Date) -> String {
        let f = DateFormatter()
        f.timeStyle = .short
        return f.string(from: date)
    }

    private func statusText(_ status: IntakeStatus) -> String {
        switch status {
        case .taken: return NSLocalizedString("Taken", comment: "")
        case .skipped: return NSLocalizedString("Skipped", comment: "")
        case .snoozed: return NSLocalizedString("Snoozed", comment: "")
        }
    }

    @ViewBuilder
    private func statusIcon(_ status: IntakeStatus) -> some View {
        switch status {
        case .taken:
            Image(systemName: "checkmark.circle")
                .font(.system(size: 16))
                .foregroundStyle(AppColor.primary)
        case .skipped:
            Image(systemName: "xmark.circle")
                .font(.system(size: 16))
                .foregroundStyle(AppColor.warning)
        case .snoozed:
            Image(systemName: "zzz")
                .font(.system(size: 14))
                .foregroundStyle(AppColor.textSecondary)
        }
    }
}
