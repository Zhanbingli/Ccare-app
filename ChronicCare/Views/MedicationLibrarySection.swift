import SwiftUI
import UserNotifications

// MARK: - MedicationLibrarySection

/// Scrollable medication workbench list that appears inside HealthView.
struct MedicationLibrarySection: View {
    @EnvironmentObject var store: DataStore
    @Binding var showAdd: Bool
    @Binding var detailTarget: Medication?
    @Binding var editTarget: Medication?
    let onNotificationStatusChanged: () -> Void
    let onShowNotificationDenied: (String) -> Void

    private var courseReminderThresholdDays: Int {
        UserDefaults.standard.object(forKey: "prefs.courseEndThresholdDays") as? Int ?? 3
    }

    private var activeMedicationCount: Int {
        store.medications.filter { $0.remindersEnabled }.count
    }

    private var medicationSectionSubtitle: String {
        String(format: NSLocalizedString("%lld medications · %lld active", comment: ""), store.medications.count, activeMedicationCount)
    }

    private var attentionMedications: [Medication] {
        store.medications.filter { med in
            med.isLowSupply
                || needsCourseAttention(med)
                || (med.isAsNeeded != true && med.timesOfDay.isEmpty)
                || (med.isAsNeeded != true && !med.timesOfDay.isEmpty && !med.remindersEnabled)
        }
    }

    private var attentionMedicationIDs: Set<UUID> {
        Set(attentionMedications.map(\.id))
    }

    private var recentActiveMedications: [Medication] {
        store.medications.filter { med in
            !attentionMedicationIDs.contains(med.id)
                && (latestTodayAction(for: med) != nil || nextUntakenDose(for: med) != nil)
        }
    }

    private var medicationWorkbenchItems: [Medication] {
        Array((attentionMedications + recentActiveMedications + store.medications).uniquedByID().prefix(4))
    }

    private var hiddenMedicationCount: Int {
        max(store.medications.count - medicationWorkbenchItems.count, 0)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(NSLocalizedString("Medication Workbench", comment: ""))
                        .appFont(.headline)
                    Text(medicationSectionSubtitle)
                        .appFont(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }

            if store.medications.isEmpty {
                Card {
                    EmptyStateView(
                        systemImage: "pills.fill",
                        title: NSLocalizedString("No medications added", comment: ""),
                        subtitle: NSLocalizedString("Tap + to add your first medication.", comment: ""),
                        actionTitle: NSLocalizedString("Add Medication", comment: ""),
                        action: { showAdd = true }
                    )
                }
            } else {
                if !attentionMedications.isEmpty {
                    workbenchSummaryRow(
                        title: NSLocalizedString("Needs review", comment: ""),
                        subtitle: String(format: NSLocalizedString("%lld medications need setup, refill, course, or reminder attention.", comment: ""), attentionMedications.count),
                        tint: .orange,
                        systemImage: "exclamationmark.triangle.fill"
                    )
                }

                ForEach(medicationWorkbenchItems) { med in
                    medicationCard(for: med)
                        .id(med.id)
                }

                if hiddenMedicationCount > 0 {
                    NavigationLink {
                        allMedicationsDestination
                    } label: {
                        InsetPanel {
                            HStack(spacing: 10) {
                                Image(systemName: "list.bullet")
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundStyle(.blue)
                                    .frame(width: 34, height: 34)
                                    .background(Circle().fill(Color.blue.opacity(0.12)))
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(NSLocalizedString("View All Medications", comment: ""))
                                        .appFont(.subheadline)
                                        .foregroundStyle(.primary)
                                    Text(String(format: NSLocalizedString("%lld more saved in your library.", comment: ""), hiddenMedicationCount))
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
        }
    }

    // MARK: - All Medications Destination

    private var allMedicationsDestination: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 12) {
                Text(NSLocalizedString("All Medications", comment: ""))
                    .appFont(.title)
                Text(medicationSectionSubtitle)
                    .appFont(.caption)
                    .foregroundStyle(.secondary)

                ForEach(store.medications) { med in
                    medicationCard(for: med)
                        .id(med.id)
                }
            }
            .padding(16)
        }
        .navigationTitle(NSLocalizedString("Medication Library", comment: ""))
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Medication Card

    @ViewBuilder
    func medicationCard(for med: Medication) -> some View {
        let accentTint = medicationAccentTint(for: med)

        InsetPanel(tint: accentTint) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 12) {
                    medicationThumbnail(for: med)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(med.name)
                            .appFont(.headline)
                            .lineLimit(1)
                            .minimumScaleFactor(0.85)
                        HStack(spacing: 4) {
                            Text(med.dose)
                                .appFont(.caption)
                                .foregroundStyle(.secondary)
                            if !med.timesOfDay.isEmpty {
                                Text("·").foregroundStyle(.secondary)
                                timesText(for: med)
                            }
                        }

                        HStack(spacing: 6) {
                            if med.isAsNeeded != true && med.timesOfDay.isEmpty {
                                libraryBadge(NSLocalizedString("Needs Setup", comment: ""), tint: .orange)
                            }
                            if med.isAsNeeded != true && !med.remindersEnabled {
                                libraryBadge(NSLocalizedString("Paused", comment: ""), tint: .orange)
                            }
                            if med.isAsNeeded == true {
                                libraryBadge(NSLocalizedString("PRN", comment: ""), tint: .blue)
                            }

                            if let (status, _) = latestTodayAction(for: med) {
                                inlineStatusLabel(status: status)
                            }
                        }
                    }
                    Spacer(minLength: 4)
                    if med.isAsNeeded != true {
                        reminderToggle(for: med)
                            .padding(.top, 2)
                    }
                }

                HStack(spacing: 8) {
                    if let remaining = med.pillsRemaining {
                        compactSupplyLabel(remaining: remaining, med: med)
                    }
                    compactCourseLabel(for: med)
                    Spacer(minLength: 0)
                    if med.isAsNeeded != true && med.remindersEnabled {
                        compactQuickTakeButton(for: med)
                    }
                }

                if med.isLowSupply || needsCourseAttention(med) {
                    quickMaintenanceActions(for: med)
                }
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { detailTarget = med }
        .padding(.vertical, 2)
    }

    // MARK: - Card Sub-components

    private func medicationAccentTint(for med: Medication) -> Color? {
        if med.isLowSupply || needsCourseAttention(med) { return .orange }
        if med.isAsNeeded == true { return .blue }
        if med.isAsNeeded != true && med.timesOfDay.isEmpty { return .orange }
        return nil
    }

    private func libraryBadge(_ text: String, tint: Color) -> some View {
        AppBadge(text: text, tint: tint)
    }

    private func workbenchSummaryRow(title: String, subtitle: String, tint: Color, systemImage: String) -> some View {
        InsetPanel(tint: tint) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: systemImage)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(tint)
                    .frame(width: 34, height: 34)
                    .background(Circle().fill(tint.opacity(0.12)))
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .appFont(.subheadline)
                    Text(subtitle)
                        .appFont(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
            }
        }
    }

    @ViewBuilder
    func medicationThumbnail(for med: Medication) -> some View {
        if let path = med.imagePath, let ui = loadMedicationImage(path: path) {
            Image(uiImage: ui).resizable().scaledToFill()
                .frame(width: 40, height: 40)
                .clipShape(RoundedRectangle(cornerRadius: AppRadius.small, style: .continuous))
        } else {
            RoundedRectangle(cornerRadius: AppRadius.small, style: .continuous)
                .fill(Color.accentColor.opacity(0.10))
                .frame(width: 40, height: 40)
                .overlay(
                    Image(systemName: "pills.fill").font(.system(size: 18, weight: .semibold)).foregroundStyle(Color.accentColor)
                )
        }
    }

    func timesText(for med: Medication) -> some View {
        let formatter: DateFormatter = { let f = DateFormatter(); f.timeStyle = .short; return f }()
        let cal = Calendar.current
        let times = med.timesOfDay.compactMap { comps -> String? in
            guard let h = comps.hour, let m = comps.minute,
                  let date = cal.date(bySettingHour: h, minute: m, second: 0, of: Date()) else { return nil }
            return formatter.string(from: date)
        }
        return Text(times.joined(separator: ", ")).appFont(.caption).foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(0.85)
    }

    @ViewBuilder
    func compactSupplyLabel(remaining: Int, med: Medication) -> some View {
        let isLow = med.isLowSupply
        HStack(spacing: 4) {
            if isLow {
                Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 13)).foregroundStyle(.red)
            }
            if remaining == 0 {
                Text(NSLocalizedString("Out of pills", comment: ""))
                    .appFont(.caption)
                    .foregroundStyle(.red)
            } else if let days = med.daysOfSupplyRemaining, days > 0 {
                Text(String(format: NSLocalizedString("%lld pills · %lld d left", comment: ""), remaining, days))
                    .appFont(.caption).foregroundStyle(isLow ? .red : .secondary)
            } else {
                Text(String(format: NSLocalizedString("%lld pills", comment: ""), remaining))
                    .appFont(.caption).foregroundStyle(isLow ? .red : .secondary)
            }
        }
    }

    @ViewBuilder
    func compactCourseLabel(for med: Medication) -> some View {
        if let courseState = med.courseState(thresholdDays: courseReminderThresholdDays) {
            switch courseState {
            case .endingSoon(let daysRemaining):
                HStack(spacing: 4) {
                    Image(systemName: "calendar.badge.exclamationmark").font(.system(size: 13))
                    Text(String(format: NSLocalizedString("Ends in %lld d", comment: ""), daysRemaining)).appFont(.caption)
                }
                .foregroundStyle(.orange)
            case .endsToday:
                HStack(spacing: 4) {
                    Image(systemName: "calendar.badge.exclamationmark").font(.system(size: 13))
                    Text(NSLocalizedString("Ends today", comment: "")).appFont(.caption)
                }
                .foregroundStyle(.orange)
            case .ended:
                HStack(spacing: 4) {
                    Image(systemName: "calendar.badge.exclamationmark").font(.system(size: 13))
                    Text(NSLocalizedString("Course ended", comment: "")).appFont(.caption)
                }
                .foregroundStyle(.red)
            default:
                EmptyView()
            }
        }
    }

    func needsCourseAttention(_ med: Medication) -> Bool {
        switch med.courseState(thresholdDays: courseReminderThresholdDays) {
        case .endingSoon, .endsToday, .ended:
            return true
        default:
            return false
        }
    }

    @ViewBuilder
    func quickMaintenanceActions(for med: Medication) -> some View {
        HStack(spacing: 8) {
            if med.isLowSupply {
                Button {
                    applyQuickRefill(to: med, addedPills: 30)
                } label: {
                    Label(NSLocalizedString("Refill +30", comment: ""), systemImage: "cross.case.fill")
                        .appFont(.caption)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            if needsCourseAttention(med) {
                Button {
                    extendCourse(for: med, byDays: 7)
                } label: {
                    Label(NSLocalizedString("Extend +7d", comment: ""), systemImage: "calendar.badge.plus")
                        .appFont(.caption)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            Button(NSLocalizedString("Review", comment: "")) {
                detailTarget = med
            }
            .buttonStyle(.borderless)
            .appFont(.caption)
            .foregroundStyle(.secondary)
        }
    }

    func inlineStatusLabel(status: IntakeStatus) -> some View {
        HStack(spacing: 5) {
            Image(systemName: latestStatusIcon(status))
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(statusTint(for: status))
            Text(statusPrefix(for: status))
                .appFont(.caption)
                .foregroundStyle(statusTint(for: status))
        }
    }

    @ViewBuilder
    func compactQuickTakeButton(for med: Medication) -> some View {
        if let dose = nextUntakenDose(for: med) {
            Button {
                let dupCheck = MedicationRules.checkDuplicateTaken(
                    medicationID: med.id, scheduleTime: dose.comps, intakeLogs: store.intakeLogs
                )
                if case .blocked = dupCheck {
                    Haptics.notification(.warning)
                    return
                }
                store.recordTakenDose(
                    medicationID: med.id,
                    scheduleTime: dose.comps,
                    scheduledDate: dose.scheduledDate
                )
                NotificationManager.shared.suppressToday(for: med.id, timeComponents: dose.comps)
                NotificationManager.shared.cancelDoseNotifications(for: med.id, timeComponents: dose.comps, scheduledDate: dose.scheduledDate, now: dose.scheduledDate)
                store.syncNotifications()
                Haptics.success()
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "checkmark").font(.system(size: 13, weight: .bold))
                    Text(dose.timeStr).appFont(.caption)
                }
                .padding(.horizontal, 12).padding(.vertical, 8)
            }
            .buttonStyle(.borderedProminent)
            .tint(.green)
            .controlSize(.small)
        }
    }

    func reminderToggle(for med: Medication) -> some View {
        Toggle(isOn: Binding(
            get: { med.remindersEnabled },
            set: { newVal in
                Task {
                    if newVal {
                        let granted = await NotificationManager.shared.ensureAuthorization()
                        await MainActor.run {
                            guard granted else {
                                onShowNotificationDenied(med.name)
                                var reverted = med; reverted.remindersEnabled = false
                                store.updateMedication(reverted)
                                onNotificationStatusChanged()
                                return
                            }
                            var updated = med; updated.remindersEnabled = true
                            store.updateMedication(updated)
                            store.syncNotifications()
                            Haptics.impact(.light)
                            onNotificationStatusChanged()
                        }
                    } else {
                        await MainActor.run {
                            var updated = med; updated.remindersEnabled = false
                            store.updateMedication(updated)
                            store.syncNotifications()
                            Haptics.impact(.light)
                            onNotificationStatusChanged()
                        }
                    }
                }
            }
        )) { Text(NSLocalizedString("Remind", comment: "")) }
        .labelsHidden()
    }

    // MARK: - Dose Helpers

    func nextUntakenDose(for med: Medication) -> (comps: DateComponents, scheduledDate: Date, timeStr: String)? {
        let cal = Calendar.current
        let now = Date()
        let dayStart = cal.startOfDay(for: now)
        guard let dayEnd = cal.date(byAdding: .day, value: 1, to: dayStart) else { return nil }
        let todayLogs = store.intakeLogs.filter { $0.medicationID == med.id && $0.date >= dayStart && $0.date < dayEnd }
        let sorted = med.timesOfDay.sorted { ($0.hour ?? 0) * 60 + ($0.minute ?? 0) < ($1.hour ?? 0) * 60 + ($1.minute ?? 0) }
        for comps in sorted {
            let key = String(format: "%02d:%02d", comps.hour ?? 0, comps.minute ?? 0)
            let resolved = todayLogs.contains { $0.scheduleKey == key && ($0.status == .taken || $0.status == .skipped) }
            guard !resolved,
                  let scheduledDate = cal.date(bySettingHour: comps.hour ?? 0, minute: comps.minute ?? 0, second: 0, of: now),
                  med.isDoseActive(on: scheduledDate),
                  scheduledDate <= now else { continue }
            if !resolved {
                let formatter = DateFormatter(); formatter.timeStyle = .short
                let timeStr = formatter.string(from: scheduledDate)
                return (comps, scheduledDate, timeStr)
            }
        }
        return nil
    }

    func latestTodayAction(for med: Medication) -> (IntakeStatus, Date)? {
        let cal = Calendar.current
        let start = cal.startOfDay(for: Date())
        let end = cal.date(byAdding: .day, value: 1, to: start)!
        let logs = store.intakeLogs
            .filter { $0.medicationID == med.id && $0.date >= start && $0.date < end }
            .sorted { $0.date > $1.date }
        guard let last = logs.first else { return nil }
        return (last.status, last.date)
    }

    func applyQuickRefill(to med: Medication, addedPills: Int) {
        guard let current = med.pillsRemaining else {
            editTarget = med
            return
        }
        var updated = med
        updated.pillsRemaining = current + addedPills
        store.updateMedication(updated)
        store.syncNotifications()
        Haptics.success()
    }

    func extendCourse(for med: Medication, byDays days: Int) {
        guard let currentEnd = med.courseEndDate else {
            editTarget = med
            return
        }
        var updated = med
        updated.courseEndDate = Calendar.current.date(byAdding: .day, value: days, to: currentEnd) ?? currentEnd
        store.updateMedication(updated)
        store.syncNotifications()
        Haptics.success()
    }

    // MARK: - Status Helpers

    func latestStatusIcon(_ status: IntakeStatus) -> String {
        switch status {
        case .taken: return "checkmark.circle.fill"
        case .skipped: return "xmark.circle.fill"
        case .snoozed: return "zzz"
        }
    }

    func statusTint(for status: IntakeStatus) -> Color {
        switch status {
        case .taken: return .green
        case .skipped: return .orange
        case .snoozed: return .blue
        }
    }

    func statusPrefix(for status: IntakeStatus) -> LocalizedStringKey {
        switch status {
        case .taken: return "Taken"
        case .skipped: return "Skipped"
        case .snoozed: return "Snoozed"
        }
    }
}

// MARK: - Array+uniquedByID (shared utility)

extension Array where Element == Medication {
    func uniquedByID() -> [Medication] {
        var seen = Set<UUID>()
        return filter { seen.insert($0.id).inserted }
    }
}
