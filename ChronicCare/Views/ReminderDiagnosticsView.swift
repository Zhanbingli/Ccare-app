import SwiftUI
import UserNotifications

// MARK: - ReminderDiagnosticsView

struct ReminderDiagnosticsView: View {
    @EnvironmentObject var store: DataStore
    let notificationStatus: UNAuthorizationStatus
    let scheduledWithoutRemindersCount: Int
    let untimedScheduledCount: Int
    @State private var editTarget: Medication? = nil

    private var disabledReminderMeds: [Medication] {
        store.medications.filter { $0.isAsNeeded != true && !$0.timesOfDay.isEmpty && !$0.remindersEnabled }
    }

    private var untimedScheduledMeds: [Medication] {
        store.medications.filter { $0.isAsNeeded != true && $0.timesOfDay.isEmpty }
    }

    private var prnMeds: [Medication] {
        store.medications.filter { $0.isAsNeeded == true }
    }

    private var hasCoverageIssues: Bool {
        notificationStatus == .denied || !disabledReminderMeds.isEmpty || !untimedScheduledMeds.isEmpty
    }

    private func enableReminders(for medication: Medication) async {
        let granted = await NotificationManager.shared.ensureAuthorization()
        await MainActor.run {
            guard granted else {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
                return
            }
            var updated = medication
            updated.remindersEnabled = true
            store.updateMedication(updated)
            store.syncNotifications()
            Haptics.success()
        }
    }

    private func enableAllDisabledReminders() async {
        let granted = await NotificationManager.shared.ensureAuthorization()
        await MainActor.run {
            guard granted else {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
                return
            }
            for med in disabledReminderMeds {
                var updated = med
                updated.remindersEnabled = true
                store.updateMedication(updated)
            }
            store.syncNotifications()
            Haptics.success()
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                TintedCard(tint: hasCoverageIssues ? .orange : .green) {
                    VStack(alignment: .leading, spacing: 14) {
                        Text(NSLocalizedString("Reminder Coverage", comment: ""))
                            .appFont(.title)
                            .fontWeight(.bold)
                        Text(systemStatusText)
                            .appFont(.caption)
                            .foregroundStyle(.secondary)

                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                            diagnosticMetric(
                                title: NSLocalizedString("Permission", comment: ""),
                                value: permissionLabel,
                                tint: notificationStatus == .authorized || notificationStatus == .provisional ? .green : .orange
                            )
                            diagnosticMetric(
                                title: NSLocalizedString("Reminders Off", comment: ""),
                                value: "\(scheduledWithoutRemindersCount)",
                                tint: scheduledWithoutRemindersCount > 0 ? .orange : .secondary
                            )
                            diagnosticMetric(
                                title: NSLocalizedString("Missing Times", comment: ""),
                                value: "\(untimedScheduledCount)",
                                tint: untimedScheduledCount > 0 ? .orange : .secondary
                            )
                            diagnosticMetric(
                                title: NSLocalizedString("PRN", comment: ""),
                                value: "\(prnMeds.count)",
                                tint: .blue
                            )
                        }

                        if notificationStatus == .denied {
                            Button(NSLocalizedString("Open System Settings", comment: "")) {
                                if let url = URL(string: UIApplication.openSettingsURLString) {
                                    UIApplication.shared.open(url)
                                }
                            }
                            .buttonStyle(.borderedProminent)
                        }
                    }
                }

                if !hasCoverageIssues {
                    Card {
                        Label(NSLocalizedString("All scheduled medications currently have reminder coverage.", comment: ""), systemImage: "checkmark.circle.fill")
                            .appFont(.subheadline)
                            .foregroundStyle(.green)
                    }
                }

                if !disabledReminderMeds.isEmpty {
                    diagnosticSectionCard(
                        title: NSLocalizedString("Reminders Turned Off", comment: ""),
                        subtitle: NSLocalizedString("These medications already have times, but fixed reminders are disabled.", comment: ""),
                        actionTitle: disabledReminderMeds.count > 1 ? NSLocalizedString("Turn On All", comment: "") : nil
                    ) {
                        if disabledReminderMeds.count > 1 {
                            Task {
                                await enableAllDisabledReminders()
                            }
                        }
                    } content: {
                        ForEach(disabledReminderMeds) { med in
                            diagnosticMedicationRow(
                                med,
                                reason: NSLocalizedString("Scheduled medication with reminder times, but reminders are off.", comment: ""),
                                actionTitle: NSLocalizedString("Turn On", comment: "")
                            ) {
                                Task {
                                    await enableReminders(for: med)
                                }
                            }
                        }
                    }
                }

                if !untimedScheduledMeds.isEmpty {
                    diagnosticSectionCard(
                        title: NSLocalizedString("Needs Schedule Times", comment: ""),
                        subtitle: NSLocalizedString("These medications are scheduled, but they still need reminder times.", comment: "")
                    ) {
                        ForEach(untimedScheduledMeds) { med in
                            diagnosticMedicationRow(
                                med,
                                reason: NSLocalizedString("This medication is scheduled but does not yet have reminder times.", comment: ""),
                                actionTitle: NSLocalizedString("Set Up", comment: "")
                            ) {
                                editTarget = med
                            }
                        }
                    }
                }

                if !prnMeds.isEmpty {
                    diagnosticSectionCard(
                        title: NSLocalizedString("As Needed Medications", comment: ""),
                        subtitle: NSLocalizedString("PRN medications are logged manually and do not create fixed reminders.", comment: "")
                    ) {
                        ForEach(prnMeds) { med in
                            diagnosticMedicationRow(med, reason: NSLocalizedString("Tracked manually from Today when you take a dose.", comment: ""))
                        }
                    }
                }
            }
            .padding(16)
        }
        .navigationTitle(NSLocalizedString("Reminder Coverage", comment: ""))
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $editTarget) { med in
            MedicationFormView(editing: med, onSave: { updated in
                store.updateMedication(updated)
                store.syncNotifications()
            }, onDelete: {
                if let idx = store.medications.firstIndex(where: { $0.id == med.id }) {
                    NotificationManager.shared.cancelAll(for: med)
                    store.removeMedication(at: IndexSet(integer: idx))
                    store.syncNotifications()
                }
            })
            .environmentObject(store)
        }
    }

    private var permissionLabel: String {
        switch notificationStatus {
        case .authorized:
            return NSLocalizedString("Authorized", comment: "")
        case .provisional:
            return NSLocalizedString("Provisional", comment: "")
        case .denied:
            return NSLocalizedString("Denied", comment: "")
        case .notDetermined:
            return NSLocalizedString("Not Determined", comment: "")
        case .ephemeral:
            return NSLocalizedString("Ephemeral", comment: "")
        @unknown default:
            return NSLocalizedString("Unknown", comment: "")
        }
    }

    private var systemStatusText: String {
        if notificationStatus == .denied {
            return NSLocalizedString("System notifications are blocked, so medication reminders cannot fire until permission is restored.", comment: "")
        }
        if scheduledWithoutRemindersCount == 0 && untimedScheduledCount == 0 {
            return NSLocalizedString("No obvious reminder gaps were detected for your scheduled medications.", comment: "")
        }
        return NSLocalizedString("Some medications still need reminder setup or have reminders turned off.", comment: "")
    }

    private func diagnosticMetric(title: String, value: String, tint: Color) -> some View {
        InsetPanel(tint: tint) {
            VStack(alignment: .leading, spacing: 6) {
                Text(value)
                    .appFont(.headline)
                    .foregroundStyle(tint)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Text(title)
                    .appFont(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, minHeight: 74, alignment: .topLeading)
        }
    }

    private func diagnosticSectionCard<Content: View>(
        title: String,
        subtitle: String,
        actionTitle: String? = nil,
        action: (() -> Void)? = nil,
        @ViewBuilder content: () -> Content
    ) -> some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(title)
                            .appFont(.headline)
                        Text(subtitle)
                            .appFont(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer()
                    if let actionTitle, let action {
                        Button(actionTitle, action: action)
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                    }
                }
                VStack(spacing: 10) {
                    content()
                }
            }
        }
    }

    private func diagnosticMedicationRow(
        _ medication: Medication,
        reason: String,
        actionTitle: String? = nil,
        action: (() -> Void)? = nil
    ) -> some View {
        InsetPanel {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(medication.name)
                        .appFont(.subheadline)
                    Text("\(medication.dose) · \(reason)")
                        .appFont(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                if let actionTitle, let action {
                    Button(actionTitle, action: action)
                        .buttonStyle(.bordered)
                        .controlSize(.regular)
                }
            }
        }
    }
}
