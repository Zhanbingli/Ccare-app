import SwiftUI

/// Always-in-view 7-day adherence indicator at the top of Today. Each dot is
/// one day; today is the rightmost and ringed. Tapping anywhere opens the
/// adherence calendar — the natural deepening of "how am I doing this week".
///
/// Replaces the old `WeeklyAdherenceCard` that sat below the actionable content
/// and competed with it. The sparkline stays out of the way but present.
struct WeekSparkline: View {
    @EnvironmentObject var store: DataStore
    var onTap: () -> Void

    private let calendar = Calendar.current

    private struct DaySnapshot: Identifiable {
        let date: Date
        let taken: Int
        let total: Int

        var id: Date { date }
        var percent: Double {
            total > 0 ? Double(taken) / Double(total) : 0
        }
    }

    private var week: [DaySnapshot] {
        let endDay = calendar.startOfDay(for: Date())
        let startDay = calendar.date(byAdding: .day, value: -6, to: endDay) ?? endDay

        return (0..<7).compactMap { offset in
            guard let day = calendar.date(byAdding: .day, value: offset, to: startDay) else {
                return nil
            }
            let dayKey = calendar.startOfDay(for: day)
            let counts = AdherenceCalculator.dayCounts(
                dayKey: dayKey,
                medications: store.medications,
                logs: store.intakeLogs,
                now: Date(),
                calendar: calendar
            )
            return DaySnapshot(date: dayKey, taken: counts.taken, total: counts.total)
        }
    }

    private var todaySnapshot: DaySnapshot? {
        week.last
    }

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 10) {
                Text(NSLocalizedString("This Week", comment: "Top of Today weekly adherence header"))
                    .appFont(.headline)

                HStack(spacing: 10) {
                    ForEach(week) { snapshot in
                        dayColumn(snapshot)
                    }
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilitySummary)
        .accessibilityHint(NSLocalizedString("Opens adherence calendar.", comment: ""))
    }

    private func dayColumn(_ snapshot: DaySnapshot) -> some View {
        let isToday = calendar.isDateInToday(snapshot.date)

        return VStack(spacing: 6) {
            ZStack {
                if isToday {
                    Circle()
                        .strokeBorder(AppColor.textPrimary.opacity(0.35), lineWidth: 1.5)
                        .frame(width: 22, height: 22)
                }

                Circle()
                    .fill(fillColor(for: snapshot))
                    .frame(width: isToday ? 14 : 12, height: isToday ? 14 : 12)
            }
            .frame(height: 22)

            Text(weekdayLetter(snapshot.date))
                .font(.caption2)
                .fontWeight(isToday ? .semibold : .regular)
                .foregroundStyle(isToday ? AppColor.textPrimary : AppColor.textSecondary)
        }
        .frame(maxWidth: .infinity)
    }

    private func fillColor(for snapshot: DaySnapshot) -> Color {
        if snapshot.total == 0 {
            return AppColor.textTertiary.opacity(0.30)
        }
        if snapshot.percent >= 1.0 {
            return AppColor.primary
        }
        if snapshot.percent > 0 {
            return AppColor.textSecondary
        }
        return AppColor.warning
    }

    private func weekdayLetter(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale.current
        let symbols = formatter.veryShortWeekdaySymbols ?? ["S", "M", "T", "W", "T", "F", "S"]
        let weekday = calendar.component(.weekday, from: date)
        return symbols[(weekday - 1 + symbols.count) % symbols.count]
    }

    private var accessibilitySummary: String {
        guard let todaySnapshot else {
            return NSLocalizedString("This week adherence.", comment: "weekly adherence accessibility")
        }

        if todaySnapshot.total > 0 {
            return String(
                format: NSLocalizedString(
                    "This week adherence. Today %lld of %lld doses taken.",
                    comment: "weekly adherence accessibility"
                ),
                todaySnapshot.taken,
                todaySnapshot.total
            )
        }

        return NSLocalizedString("This week adherence.", comment: "weekly adherence accessibility")
    }
}
