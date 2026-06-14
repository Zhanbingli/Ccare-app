import SwiftUI
import UserNotifications

// MARK: - Home alert cards
//
// Self-contained cards extracted from DashboardView. Each receives only the
// data and callbacks it needs, so it can be reasoned about, previewed, and
// changed in isolation — no access to the dashboard's shared @State.

/// Gentle nudge shown when no scheduled dose has been recorded in a while.
struct InactivityWarningCard: View {
    let daysSince: Int
    var onShowTodaysDoses: () -> Void
    var onUpdatePlan: () -> Void

    var body: some View {
        TintedCard(tint: AppColor.warning) {
            VStack(alignment: .leading, spacing: EditorialSpacing.sm) {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 18, weight: .regular))
                        .foregroundStyle(AppColor.warning)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(NSLocalizedString("No recent activity", comment: ""))
                            .appFont(.headline)
                        Text(String(format: NSLocalizedString("No scheduled dose has been recorded in the last %lld days. If the medication plan changed, update the medication list.", comment: "Dashboard medication inactivity warning"), daysSince))
                            .appFont(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 4)
                }

                HStack(spacing: EditorialSpacing.sm) {
                    Button {
                        onShowTodaysDoses()
                    } label: {
                        Text(NSLocalizedString("Show today's doses", comment: "Medication inactivity action"))
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                    Button {
                        onUpdatePlan()
                    } label: {
                        Text(NSLocalizedString("Update medication plan", comment: "Medication inactivity action"))
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
        }
    }
}

/// Surfaced when reminders can't fire — notifications blocked, a scheduled med
/// has no time, or reminders are switched off.
struct ReminderRepairCard: View {
    let notificationStatus: UNAuthorizationStatus
    let untimedScheduledMeds: [Medication]
    let disabledReminderMeds: [Medication]
    var onRepair: () -> Void

    private var issueText: String {
        if notificationStatus == .denied {
            return NSLocalizedString("System notifications are blocked. Scheduled medication reminders cannot fire.", comment: "")
        }
        if let first = untimedScheduledMeds.first {
            return String(format: NSLocalizedString("%@ needs a reminder time before it can notify you.", comment: ""), first.name)
        }
        if disabledReminderMeds.count == 1, let first = disabledReminderMeds.first {
            return String(format: NSLocalizedString("%@ has reminder times, but reminders are turned off.", comment: ""), first.name)
        }
        return String(format: NSLocalizedString("%lld medications have reminders turned off.", comment: ""), disabledReminderMeds.count)
    }

    private var actionTitle: String {
        if notificationStatus == .denied {
            return NSLocalizedString("Open Settings", comment: "")
        }
        if !untimedScheduledMeds.isEmpty {
            return NSLocalizedString("Set Time", comment: "")
        }
        return NSLocalizedString("Turn On", comment: "")
    }

    var body: some View {
        TintedCard(tint: AppColor.warning) {
            HStack(alignment: .center, spacing: 12) {
                Image(systemName: "bell.badge")
                    .font(.system(size: 18, weight: .regular))
                    .foregroundStyle(AppColor.warning)
                    .frame(width: 24, height: 24)

                VStack(alignment: .leading, spacing: 4) {
                    Text(NSLocalizedString("Reminder Setup Needs Attention", comment: ""))
                        .appFont(.headline)
                    Text(issueText)
                        .appFont(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 8)

                Button(actionTitle) {
                    onRepair()
                }
                .buttonStyle(.borderedProminent)
                .tint(AppColor.warning)
                .controlSize(.small)
            }
        }
    }
}

/// The single due/overdue dose, with Take / Skip. Caller formats the dose-time
/// line and supplies the two actions.
struct CurrentDoseActionCard: View {
    let medicationName: String
    let doseTimeText: String
    var onTake: () -> Void
    var onSkip: () -> Void

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: EditorialSpacing.md) {
                Label(NSLocalizedString("Medication due now", comment: "Current medication action title"), systemImage: "pills.fill")
                    .appFont(.headline)
                    .fontWeight(.semibold)
                    .foregroundStyle(EditorialPalette.textPrimary)

                VStack(alignment: .leading, spacing: EditorialSpacing.xs) {
                    Text(medicationName)
                        .appFont(.headline)
                        .foregroundStyle(EditorialPalette.textPrimary)
                    Text(doseTimeText)
                        .appFont(.caption)
                        .foregroundStyle(EditorialPalette.textSecondary)
                }

                HStack(spacing: EditorialSpacing.sm) {
                    EditorialButton(NSLocalizedString("Take", comment: ""), kind: .primary) {
                        onTake()
                    }

                    EditorialButton(NSLocalizedString("Skip", comment: ""), kind: .secondary) {
                        onSkip()
                    }
                }
            }
        }
    }
}

/// Medication safety notice: either a record gap (with recovery actions) or a
/// schedule overlap. Action routing is delegated to the caller.
struct SafetyNoticeCard: View {
    let summary: MedicationRules.DailySafetySummary
    let state: TodayState
    var onTakeDose: (MedSchedule) -> Void
    var onShowTodaysDoses: () -> Void
    var onUpdatePlan: (UUID) -> Void

    private let tint: Color = AppColor.warning

    var body: some View {
        TintedCard(tint: tint) {
            VStack(alignment: .leading, spacing: EditorialSpacing.md) {
                if let primary = summary.missEscalations.first {
                    recordGapHeader(primary, extraCount: summary.missEscalations.count - 1)
                    recordGapActions(for: primary)
                } else {
                    header(
                        title: NSLocalizedString("Schedule overlap", comment: ""),
                        detail: summary.timingConflicts.first ?? ""
                    )
                }
            }
        }
    }

    private func recordGapHeader(
        _ escalation: MedicationRules.DailySafetySummary.MissEscalation,
        extraCount: Int
    ) -> some View {
        let detail = extraCount > 0
            ? "\(escalation.message) \(String(format: NSLocalizedString("%lld more medications need review.", comment: "Medication safety extra count"), Int64(extraCount)))"
            : escalation.message

        return header(
            title: NSLocalizedString("Medication record gap", comment: "Medication safety card title"),
            detail: detail
        )
    }

    private func header(title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 17, weight: .regular))
                .foregroundStyle(tint)
                .frame(width: 22, height: 22)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .appFont(.headline)
                    .foregroundStyle(AppColor.textPrimary)
                if !detail.isEmpty {
                    Text(detail)
                        .appFont(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
        }
    }

    @ViewBuilder
    private func recordGapActions(
        for escalation: MedicationRules.DailySafetySummary.MissEscalation
    ) -> some View {
        HStack(spacing: EditorialSpacing.sm) {
            if let dose = attentionSchedule(for: escalation) {
                Button {
                    onTakeDose(dose)
                } label: {
                    Text(NSLocalizedString("I took today's dose", comment: "Medication safety action"))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .tint(AppColor.primary)
            } else {
                Button {
                    onShowTodaysDoses()
                } label: {
                    Text(NSLocalizedString("Show today's doses", comment: "Medication safety action"))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .tint(AppColor.primary)
            }

            Button {
                onUpdatePlan(escalation.medicationID)
            } label: {
                Text(NSLocalizedString("Update plan", comment: "Medication safety compact action"))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
    }

    private func attentionSchedule(
        for escalation: MedicationRules.DailySafetySummary.MissEscalation
    ) -> MedSchedule? {
        state.actionableSchedules.first { $0.med.id == escalation.medicationID }
    }
}
