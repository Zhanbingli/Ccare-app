import SwiftUI

struct AdherenceCalendarView: View {
    @EnvironmentObject var store: DataStore
    var medicationID: UUID? = nil

    @State private var displayedMonth: Date = Date()
    @State private var selectedDay: Date?

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
                    ForEach(weekdaySymbols, id: \.self) { sym in
                        Text(sym)
                            .appFont(.caption)
                            .fontWeight(.medium)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity)
                    }
                }
                .padding(.horizontal, 8)

                // Calendar grid
                let days = calendarDays()
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 0), count: 7), spacing: 8) {
                    ForEach(days, id: \.self) { day in
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
                        legendItem(color: .green, label: NSLocalizedString("All Taken", comment: ""))
                        legendItem(color: .orange, label: NSLocalizedString("Partial", comment: ""))
                        legendItem(color: .red, label: NSLocalizedString("Missed", comment: ""))
                        Spacer()
                        Text(String(format: "%.0f%%", monthStats.avgPercent * 100))
                            .appFont(.caption)
                            .fontWeight(.bold)
                            .foregroundStyle(.primary)
                        Text(NSLocalizedString("Avg", comment: ""))
                            .appFont(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Color(.secondarySystemBackground))
                    )
                    .padding(.horizontal)
                } else {
                    Text(NSLocalizedString("No medication data for this month.", comment: ""))
                        .appFont(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 12)
                }

                // Inline day detail (no sheet)
                if let day = selectedDay {
                    dayDetailInline(date: day)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
            .padding(.vertical)
        }
        .navigationTitle(NSLocalizedString("Adherence Calendar", comment: ""))
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Helpers

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
            RoundedRectangle(cornerRadius: 10)
                .fill(cellFill(data: data))
                .frame(height: 44)

            // Today ring
            if isToday {
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(Color.accentColor, lineWidth: 2)
                    .frame(height: 44)
            }

            // Selected highlight
            if isSelected {
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(Color.primary.opacity(0.4), lineWidth: 1.5)
                    .frame(height: 44)
            }

            // Day number + indicator dot
            VStack(spacing: 3) {
                Text("\(dayNum)")
                    .appFont(.caption)
                    .fontWeight(isToday ? .bold : .regular)
                    .foregroundStyle(data != nil ? .primary : .tertiary)

                // Small dot indicator
                Circle()
                    .fill(cellDotColor(data: data))
                    .frame(width: 5, height: 5)
                    .opacity((data?.total ?? 0) > 0 ? 1 : 0)
            }
        }
    }

    private func cellFill(data: (taken: Int, total: Int)?) -> Color {
        guard let data = data, data.total > 0 else { return Color(.systemBackground) }
        let pct = Double(data.taken) / Double(data.total)
        if pct >= 1.0 { return Color.green.opacity(0.18) }
        if pct > 0 { return Color.orange.opacity(0.16) }
        return Color.red.opacity(0.14)
    }

    private func cellDotColor(data: (taken: Int, total: Int)?) -> Color {
        guard let data = data, data.total > 0 else { return .clear }
        let pct = Double(data.taken) / Double(data.total)
        if pct >= 1.0 { return .green }
        if pct > 0 { return .orange }
        return .red
    }

    // MARK: - Legend

    private func legendItem(color: Color, label: String) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(label)
                .appFont(.caption)
                .foregroundStyle(.secondary)
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
                                HStack(spacing: 10) {
                                    statusIcon(log.status)
                                        .frame(width: 20)
                                    Text(med.name)
                                        .appFont(.subheadline)
                                    if let key = log.scheduleKey {
                                        Text(key)
                                            .appFont(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Text(timeString(log.date))
                                        .appFont(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                .padding(.horizontal, 14)
                                .padding(.vertical, 6)
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
                                .foregroundStyle(.secondary)
                                .frame(width: 20)
                            Text(med.name)
                                .appFont(.subheadline)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text(NSLocalizedString("No Record", comment: ""))
                                .appFont(.caption)
                                .foregroundStyle(.tertiary)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 6)
                    }
                }
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(.secondarySystemBackground))
        )
        .padding(.horizontal)
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

    @ViewBuilder
    private func statusIcon(_ status: IntakeStatus) -> some View {
        switch status {
        case .taken:
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 16))
                .foregroundStyle(.green)
        case .skipped:
            Image(systemName: "xmark.circle.fill")
                .font(.system(size: 16))
                .foregroundStyle(.orange)
        case .snoozed:
            Image(systemName: "zzz")
                .font(.system(size: 14))
                .foregroundStyle(.blue)
        }
    }
}
