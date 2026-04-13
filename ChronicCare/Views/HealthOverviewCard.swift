import SwiftUI
import UserNotifications

// MARK: - HealthOverviewCard

/// Summary KPI card at the top of HealthView showing medication counts and reminder coverage.
struct HealthOverviewCard: View {
    @EnvironmentObject var store: DataStore
    let notificationStatus: UNAuthorizationStatus
    let scheduledWithoutRemindersCount: Int
    let untimedScheduledCount: Int
    let reviewCount: Int

    private let overviewColumns = Array(repeating: GridItem(.flexible(), spacing: 10), count: 3)

    private var activeMedicationCount: Int {
        store.medications.filter { $0.remindersEnabled }.count
    }

    private var reminderRiskCount: Int {
        scheduledWithoutRemindersCount + untimedScheduledCount + (notificationStatus == .denied ? 1 : 0)
    }

    private var reminderRiskText: String {
        if notificationStatus == .denied {
            return NSLocalizedString("System notifications are off. Medication reminders will not fire.", comment: "")
        }
        if scheduledWithoutRemindersCount > 0 {
            return String(format: NSLocalizedString("%lld scheduled medications currently have reminders turned off.", comment: ""), scheduledWithoutRemindersCount)
        }
        if untimedScheduledCount > 0 {
            return String(format: NSLocalizedString("%lld medications are missing scheduled reminder times.", comment: ""), untimedScheduledCount)
        }
        return NSLocalizedString("Reminder coverage looks healthy.", comment: "")
    }

    var body: some View {
        TintedCard(tint: .blue) {
            VStack(alignment: .leading, spacing: 16) {
                Text(NSLocalizedString("Health Workspace", comment: ""))
                    .appFont(.title)
                    .fontWeight(.bold)
                Text(NSLocalizedString("Manage medications, review trends, and keep your latest readings close.", comment: ""))
                    .appFont(.caption)
                    .foregroundStyle(.secondary)

                LazyVGrid(columns: overviewColumns, spacing: 10) {
                    overviewMetric(
                        value: "\(store.medications.count)",
                        label: NSLocalizedString("Medications", comment: ""),
                        tint: .blue
                    )
                    overviewMetric(
                        value: "\(activeMedicationCount)",
                        label: NSLocalizedString("Active", comment: ""),
                        tint: .green
                    )
                    overviewMetric(
                        value: "\(reviewCount)",
                        label: NSLocalizedString("Needs Review", comment: ""),
                        tint: reviewCount > 0 ? .orange : .secondary
                    )
                }

                NavigationLink {
                    ReminderDiagnosticsView(
                        notificationStatus: notificationStatus,
                        scheduledWithoutRemindersCount: scheduledWithoutRemindersCount,
                        untimedScheduledCount: untimedScheduledCount
                    )
                    .environmentObject(store)
                } label: {
                    InsetPanel(tint: reminderRiskCount > 0 ? .orange : .green) {
                        HStack(alignment: .center, spacing: 12) {
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill((reminderRiskCount > 0 ? Color.orange : Color.green).opacity(0.14))
                                .frame(width: 40, height: 40)
                                .overlay(
                                    Image(systemName: reminderRiskCount > 0 ? "bell.badge.fill" : "bell.fill")
                                        .font(.system(size: 16, weight: .semibold))
                                        .foregroundStyle(reminderRiskCount > 0 ? .orange : .green)
                                )

                            VStack(alignment: .leading, spacing: 3) {
                                Text(NSLocalizedString("Reminder Coverage", comment: ""))
                                    .appFont(.subheadline)
                                    .foregroundStyle(.primary)
                                Text(reminderRiskText)
                                    .appFont(.caption)
                                    .foregroundStyle(.secondary)
                                    .multilineTextAlignment(.leading)
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
    }

    private func overviewMetric(value: String, label: String, tint: Color) -> some View {
        InsetPanel(tint: tint) {
            VStack(alignment: .leading, spacing: 6) {
                Text(value)
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                    .foregroundStyle(tint)
                    .monospacedDigit()
                Text(label)
                    .appFont(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity, minHeight: 74, alignment: .topLeading)
        }
    }
}
