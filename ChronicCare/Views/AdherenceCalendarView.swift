import SwiftUI

struct AdherenceCalendarView: View {
    @EnvironmentObject var store: DataStore
    var medicationID: UUID? = nil

    @State private var displayedMonth: Date = Date()
    @State private var selectedDay: Date?
    @State private var showDayDetail = false

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

        VStack(spacing: 16) {
            // Month navigation
            HStack {
                Button { shiftMonth(-1) } label: {
                    Image(systemName: "chevron.left")
                        .font(.title3.weight(.semibold))
                        .frame(width: 44, height: 44)
                }
                Spacer()
                Text(monthTitle)
                    .appFont(.headline)
                Spacer()
                Button { shiftMonth(1) } label: {
                    Image(systemName: "chevron.right")
                        .font(.title3.weight(.semibold))
                        .frame(width: 44, height: 44)
                }
                .disabled(isCurrentMonth)
            }
            .padding(.horizontal)

            // Weekday headers
            HStack(spacing: 0) {
                ForEach(weekdaySymbols, id: \.self) { sym in
                    Text(sym)
                        .appFont(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                }
            }

            // Calendar grid
            let days = calendarDays()
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 0), count: 7), spacing: 8) {
                ForEach(days, id: \.self) { day in
                    if let day = day {
                        let data = adherenceData[calendar.startOfDay(for: day)]
                        calendarCell(day: day, data: data)
                            .onTapGesture {
                                if data != nil {
                                    selectedDay = day
                                    showDayDetail = true
                                }
                            }
                    } else {
                        Color.clear.frame(height: 44)
                    }
                }
            }
            .padding(.horizontal, 8)

            // Legend
            HStack(spacing: 16) {
                legendDot(color: .green, label: NSLocalizedString("All Taken", comment: ""))
                legendDot(color: .yellow, label: NSLocalizedString("Partial", comment: ""))
                legendDot(color: .red, label: NSLocalizedString("Missed", comment: ""))
                legendDot(color: Color(.systemGray4), label: NSLocalizedString("No Data", comment: ""))
            }
            .appFont(.caption)
            .padding(.top, 4)

            // Monthly summary
            let monthStats = computeMonthStats(adherenceData)
            if adherenceData.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "calendar.badge.clock")
                        .font(.system(size: 36))
                        .foregroundStyle(.secondary)
                    Text(NSLocalizedString("No medication data for this month.", comment: ""))
                        .appFont(.subheadline)
                        .foregroundStyle(.secondary)
                    Text(NSLocalizedString("Start logging doses to see your adherence here.", comment: ""))
                        .appFont(.caption)
                        .foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 20)
            }
            if monthStats.totalDays > 0 {
                VStack(spacing: 8) {
                    HStack(spacing: 20) {
                        statPill(label: NSLocalizedString("Avg", comment: ""), value: String(format: "%.0f%%", monthStats.avgPercent * 100), color: .blue)
                        statPill(label: NSLocalizedString("Perfect Days", comment: ""), value: "\(monthStats.perfectDays)", color: .green)
                        statPill(label: NSLocalizedString("Missed Days", comment: ""), value: "\(monthStats.missedDays)", color: .red)
                    }
                }
                .padding()
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
                .padding(.horizontal)
            }

            Spacer()
        }
        .padding(.top)
        .navigationTitle(NSLocalizedString("Adherence Calendar", comment: ""))
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showDayDetail) {
            if let day = selectedDay {
                DayDetailView(store: store, date: day, medicationID: medicationID)
                    .presentationDetents([.medium, .large])
            }
        }
    }

    // MARK: - Helpers

    private var isCurrentMonth: Bool {
        calendar.isDate(displayedMonth, equalTo: Date(), toGranularity: .month)
    }

    private func shiftMonth(_ offset: Int) {
        if let newDate = calendar.date(byAdding: .month, value: offset, to: displayedMonth) {
            withAnimation(.easeInOut(duration: 0.2)) { displayedMonth = newDate }
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

    @ViewBuilder
    private func calendarCell(day: Date, data: (taken: Int, total: Int)?) -> some View {
        let dayNum = calendar.component(.day, from: day)
        let isToday = calendar.isDateInToday(day)

        ZStack {
            RoundedRectangle(cornerRadius: 8)
                .fill(cellColor(data: data))
                .frame(height: 44)

            if isToday {
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(Color.accentColor, lineWidth: 2)
                    .frame(height: 44)
            }

            Text("\(dayNum)")
                .appFont(.body)
                .fontWeight(isToday ? .bold : .regular)
                .foregroundStyle(data != nil ? .primary : .secondary)
        }
    }

    private func cellColor(data: (taken: Int, total: Int)?) -> Color {
        guard let data = data else { return Color(.systemGray6) }
        if data.total == 0 { return Color(.systemGray5) }
        let pct = Double(data.taken) / Double(data.total)
        if pct >= 1.0 { return Color.green.opacity(0.35) }
        if pct > 0 { return Color.yellow.opacity(0.35) }
        return Color.red.opacity(0.3)
    }

    @ViewBuilder
    private func legendDot(color: Color, label: String) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color.opacity(color == Color(.systemGray4) ? 1 : 0.5)).frame(width: 10, height: 10)
            Text(label).foregroundStyle(.secondary)
        }
    }

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

    @ViewBuilder
    private func statPill(label: String, value: String, color: Color) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .appFont(.headline)
                .foregroundStyle(color)
            Text(label)
                .appFont(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Day Detail View

private struct DayDetailView: View {
    let store: DataStore
    let date: Date
    var medicationID: UUID?

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            let logs = store.intakeLogs(for: date, medicationID: medicationID)
            let meds = medicationID != nil ? store.medications.filter { $0.id == medicationID } : store.medications

            List {
                if logs.isEmpty {
                    Text(NSLocalizedString("No intake logs for this day.", comment: ""))
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(meds) { med in
                        let medLogs = logs.filter { $0.medicationID == med.id }
                        if !medLogs.isEmpty {
                            Section(med.name) {
                                ForEach(medLogs) { log in
                                    HStack {
                                        statusIcon(log.status)
                                        VStack(alignment: .leading, spacing: 2) {
                                            HStack {
                                                if let key = log.scheduleKey {
                                                    Text(key).appFont(.subheadline)
                                                }
                                                Text(log.status.rawValue.capitalized)
                                                    .appFont(.subheadline)
                                                    .foregroundStyle(statusColor(log.status))
                                            }
                                            if let note = log.note, !note.isEmpty {
                                                Text(note)
                                                    .appFont(.caption)
                                                    .foregroundStyle(.secondary)
                                                    .italic()
                                            }
                                            Text(timeString(log.date))
                                                .appFont(.caption)
                                                .foregroundStyle(.tertiary)
                                        }
                                        Spacer()
                                    }
                                }
                            }
                        }
                    }

                    // Show medications with no logs (missed)
                    let loggedMedIDs = Set(logs.map { $0.medicationID })
                    let missedMeds = meds.filter { !loggedMedIDs.contains($0.id) }
                    if !missedMeds.isEmpty {
                        Section(NSLocalizedString("No Record", comment: "")) {
                            ForEach(missedMeds) { med in
                                HStack {
                                    Image(systemName: "questionmark.circle")
                                        .foregroundStyle(.secondary)
                                    Text(med.name)
                                        .appFont(.body)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle(dateTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(NSLocalizedString("Close", comment: "")) { dismiss() }
                }
            }
        }
    }

    private var dateTitle: String {
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
            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
        case .skipped:
            Image(systemName: "xmark.circle.fill").foregroundStyle(.orange)
        case .snoozed:
            Image(systemName: "zzz").foregroundStyle(.blue)
        }
    }

    private func statusColor(_ status: IntakeStatus) -> Color {
        switch status {
        case .taken: return .green
        case .skipped: return .orange
        case .snoozed: return .blue
        }
    }
}
