import SwiftUI
import UserNotifications

// MARK: - ReminderDiagnosticsView

struct ReminderDiagnosticsView: View {
    @EnvironmentObject var store: DataStore
    let notificationStatus: UNAuthorizationStatus
    let scheduledWithoutRemindersCount: Int
    let untimedScheduledCount: Int
    @State private var editTarget: Medication? = nil
    @State private var adaptivePreferenceRevision = 0

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

    private var adaptiveSuggestions: [AdaptiveReminderSuggestion] {
        _ = adaptivePreferenceRevision
        return AdaptiveReminderEngine.suggestions(for: store.medications, intakeLogs: store.intakeLogs)
    }

    private var adaptiveEnabledMeds: [Medication] {
        _ = adaptivePreferenceRevision
        return store.medications.filter {
            $0.remindersEnabled
            && $0.isAsNeeded != true
            && !$0.timesOfDay.isEmpty
            && AdaptiveReminderPreferenceStore.isAdaptiveSchedulingEnabled(for: $0.id)
        }
    }

    private var hasAdaptiveAgentContent: Bool {
        !adaptiveSuggestions.isEmpty || !adaptiveEnabledMeds.isEmpty
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

    private func applyAdaptiveSuggestion(_ suggestion: AdaptiveReminderSuggestion) {
        AdaptiveReminderPreferenceStore.setAdaptiveSchedulingEnabled(true, for: suggestion.medicationID)
        AdaptiveReminderPreferenceStore.clearDismissal(suggestion.kind, for: suggestion.medicationID)
        adaptivePreferenceRevision &+= 1
        store.syncNotifications()
        Haptics.success()
    }

    private func keepStandardReminders(for suggestion: AdaptiveReminderSuggestion) {
        AdaptiveReminderPreferenceStore.setAdaptiveSchedulingEnabled(false, for: suggestion.medicationID)
        AdaptiveReminderPreferenceStore.dismissSuggestion(suggestion.kind, for: suggestion.medicationID)
        adaptivePreferenceRevision &+= 1
        store.syncNotifications()
        Haptics.impact(.light)
    }

    private func disableAdaptiveReminders(for medication: Medication) {
        AdaptiveReminderPreferenceStore.setAdaptiveSchedulingEnabled(false, for: medication.id)
        adaptivePreferenceRevision &+= 1
        store.syncNotifications()
        Haptics.impact(.light)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Card {
                    VStack(alignment: .leading, spacing: 14) {
                        Text(NSLocalizedString("Reminder Coverage", comment: ""))
                            .appFont(.title)
                            .fontWeight(.bold)
                            .foregroundStyle(AppColor.textPrimary)
                        Text(systemStatusText)
                            .appFont(.caption)
                            .foregroundStyle(AppColor.textSecondary)

                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                            diagnosticMetric(
                                title: NSLocalizedString("Permission", comment: ""),
                                value: permissionLabel,
                                tint: notificationStatus == .authorized || notificationStatus == .provisional ? AppColor.primary : AppColor.warning
                            )
                            diagnosticMetric(
                                title: NSLocalizedString("Reminders Off", comment: ""),
                                value: "\(scheduledWithoutRemindersCount)",
                                tint: scheduledWithoutRemindersCount > 0 ? AppColor.warning : AppColor.textSecondary
                            )
                            diagnosticMetric(
                                title: NSLocalizedString("Missing Times", comment: ""),
                                value: "\(untimedScheduledCount)",
                                tint: untimedScheduledCount > 0 ? AppColor.warning : AppColor.textSecondary
                            )
                            diagnosticMetric(
                                title: NSLocalizedString("PRN", comment: ""),
                                value: "\(prnMeds.count)",
                                tint: AppColor.textSecondary
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
                        Label(NSLocalizedString("All scheduled medications currently have reminder coverage.", comment: ""), systemImage: "checkmark.circle")
                            .appFont(.subheadline)
                            .foregroundStyle(AppColor.primary)
                    }
                }

                if hasAdaptiveAgentContent {
                    adaptiveReminderAgentSection
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
        .background(AppColor.background)
        .navigationTitle(NSLocalizedString("Reminder Coverage", comment: ""))
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $editTarget) { med in
            MedicationFormView(editing: med, onSave: { updated in
                let result = store.updateMedication(updated)
                if result == nil {
                    store.syncNotifications()
                }
                return result
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
                    .appFontNumeric(.headline)
                    .foregroundStyle(tint)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Text(title)
                    .appFont(.caption)
                    .foregroundStyle(AppColor.textSecondary)
            }
            .frame(maxWidth: .infinity, minHeight: 74, alignment: .topLeading)
        }
    }

    private var adaptiveReminderAgentSection: some View {
        diagnosticSectionCard(
            title: NSLocalizedString("Adaptive Reminder Agent", comment: "Reminder diagnostics adaptive agent title"),
            subtitle: NSLocalizedString("The app can adjust reminder pressure from adherence patterns, but only after you confirm each medication.", comment: "Reminder diagnostics adaptive agent subtitle")
        ) {
            ForEach(adaptiveSuggestions) { suggestion in
                adaptiveSuggestionRow(suggestion)
            }
            ForEach(adaptiveEnabledMeds) { medication in
                adaptiveEnabledRow(medication)
            }
        }
    }

    private func adaptiveSuggestionRow(_ suggestion: AdaptiveReminderSuggestion) -> some View {
        InsetPanel(tint: adaptiveTint(for: suggestion.kind)) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: adaptiveIcon(for: suggestion.kind))
                        .font(.system(size: 15, weight: .regular))
                        .foregroundStyle(adaptiveTint(for: suggestion.kind))
                        .frame(width: 20)
                        .padding(.top, 1)

                    VStack(alignment: .leading, spacing: 5) {
                        Text(suggestion.title)
                            .appFont(.subheadline)
                            .foregroundStyle(AppColor.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(suggestion.detail)
                            .appFont(.caption)
                            .foregroundStyle(AppColor.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(suggestion.effectSummary)
                            .appFont(.caption)
                            .foregroundStyle(AppColor.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                HStack(spacing: 10) {
                    Button(NSLocalizedString("Apply", comment: "Adaptive reminder apply action")) {
                        applyAdaptiveSuggestion(suggestion)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)

                    Button(NSLocalizedString("Keep Standard", comment: "Adaptive reminder dismiss action")) {
                        keepStandardReminders(for: suggestion)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
        }
    }

    private func adaptiveEnabledRow(_ medication: Medication) -> some View {
        let strategy = AdaptiveReminderEngine.strategy(for: medication, intakeLogs: store.intakeLogs)
        return InsetPanel(tint: AppColor.primary) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 15, weight: .regular))
                    .foregroundStyle(AppColor.primary)
                    .frame(width: 20)
                    .padding(.top, 1)

                VStack(alignment: .leading, spacing: 5) {
                    Text(String(format: NSLocalizedString("Adaptive reminders on for %@", comment: "Adaptive reminder enabled title"), medication.name))
                        .appFont(.subheadline)
                        .foregroundStyle(AppColor.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(AdaptiveReminderEngine.confirmedStrategySummary(strategy))
                        .appFont(.caption)
                        .foregroundStyle(AppColor.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()

                Button(NSLocalizedString("Use Standard", comment: "Adaptive reminder disable action")) {
                    disableAdaptiveReminders(for: medication)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
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
                            .foregroundStyle(AppColor.textPrimary)
                        Text(subtitle)
                            .appFont(.caption)
                            .foregroundStyle(AppColor.textSecondary)
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
                        .foregroundStyle(AppColor.textPrimary)
                    Text("\(medication.dose) · \(reason)")
                        .appFont(.caption)
                        .foregroundStyle(AppColor.textSecondary)
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

    private func adaptiveIcon(for kind: AdaptiveReminderSuggestion.Kind) -> String {
        switch kind {
        case .increaseSupport: return "bell.badge"
        case .shiftEarlier: return "clock.arrow.circlepath"
        case .reduceNoise: return "bell"
        }
    }

    private func adaptiveTint(for kind: AdaptiveReminderSuggestion.Kind) -> Color {
        switch kind {
        case .increaseSupport: return AppColor.warning
        case .shiftEarlier, .reduceNoise: return AppColor.primary
        }
    }
}
