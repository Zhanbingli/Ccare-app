import SwiftUI
import PhotosUI
import UIKit
import UserNotifications
import Charts

struct MedicationsView: View {
    @EnvironmentObject var store: DataStore
    @Binding var deepLinkMedicationID: UUID?
    @State private var scrollProxy: ScrollViewProxy?
    @State private var showAdd = false
    @State private var detailTarget: Medication? = nil
    @State private var editTarget: Medication? = nil
    @State private var showSettings = false
    @State private var showNotificationDeniedAlert = false
    @State private var deniedMedName: String? = nil
    @State private var notificationStatus: UNAuthorizationStatus = .notDetermined
    @State private var searchText: String = ""
    @State private var scrollToMedicationID: UUID? = nil

    init(deepLinkMedicationID: Binding<UUID?> = .constant(nil)) {
        self._deepLinkMedicationID = deepLinkMedicationID
    }

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                List {
                    if notificationStatus == .denied {
                        Section {
                            warningRow
                        }
                    }

                    if store.medications.isEmpty {
                        Section {
                            EmptyStateView(
                                systemImage: "pills.circle.fill",
                                title: NSLocalizedString("No medications added", comment: ""),
                                subtitle: NSLocalizedString("Add your first medication to build your daily schedule.", comment: ""),
                                actionTitle: NSLocalizedString("Add Medication", comment: ""),
                                action: { showAdd = true }
                            )
                        }
                    } else if filteredMedications.isEmpty {
                        Section {
                            Text(NSLocalizedString("No medications match your search.", comment: ""))
                                .appFont(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        if !setupMedications.isEmpty {
                            Section(NSLocalizedString("Needs Setup", comment: "")) {
                                ForEach(setupMedications) { med in
                                    medicationManagementRow(for: med)
                                        .id(med.id)
                                }
                            }
                        }

                        if !activeScheduledMedications.isEmpty {
                            Section(NSLocalizedString("Active Medications", comment: "")) {
                                ForEach(activeScheduledMedications) { med in
                                    medicationManagementRow(for: med)
                                        .id(med.id)
                                }
                            }
                        }

                        if !asNeededMedications.isEmpty {
                            Section(NSLocalizedString("As Needed", comment: "")) {
                                ForEach(asNeededMedications) { med in
                                    medicationManagementRow(for: med)
                                        .id(med.id)
                                }
                            }
                        }

                        if !pausedMedications.isEmpty {
                            Section(NSLocalizedString("Paused", comment: "")) {
                                ForEach(pausedMedications) { med in
                                    medicationManagementRow(for: med)
                                        .id(med.id)
                                }
                            }
                        }

                    }
                }
                .listStyle(.insetGrouped)
                .onAppear { scrollProxy = proxy }
                .onChange(of: store.medications.count) { _ in scrollProxy = proxy }
            }
            .navigationTitle(NSLocalizedString("Medications", comment: ""))
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { showSettings = true } label: {
                        Image(systemName: "gearshape")
                    }
                    .accessibilityLabel(NSLocalizedString("Settings", comment: ""))
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showAdd = true } label: { Image(systemName: "plus") }
                        .accessibilityLabel(NSLocalizedString("Add Medication", comment: ""))
                }
            }
            .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always), prompt: NSLocalizedString("Search medications", comment: ""))
            .sheet(isPresented: $showAdd) {
                MedicationFormView(editing: nil, onSave: { med in
                    let result = store.addMedication(med)
                    if result == nil {
                        store.syncNotifications()
                        refreshNotificationStatus()
                    }
                    return result
                })
            }
            .sheet(item: $detailTarget) { med in
                MedicationDetailView(medication: med) { selected in
                    detailTarget = nil
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                        editTarget = selected
                    }
                }
                .environmentObject(store)
            }
            .sheet(item: $editTarget) { med in
                MedicationFormView(editing: med, onSave: { updated in
                    let result = store.updateMedication(updated)
                    if result == nil {
                        store.syncNotifications()
                        refreshNotificationStatus()
                    }
                    return result
                }, onDelete: {
                    if let idx = store.medications.firstIndex(where: { $0.id == med.id }) {
                        NotificationManager.shared.cancelAll(for: med)
                        deleteMedicationImage(path: med.imagePath)
                        store.removeMedication(at: IndexSet(integer: idx))
                        store.syncNotifications()
                        refreshNotificationStatus()
                    }
                })
            }
            .sheet(isPresented: $showSettings) {
                ProfileView()
                    .environmentObject(store)
            }
            .onAppear(perform: refreshNotificationStatus)
            .onChange(of: store.medications.count) { _ in refreshNotificationStatus() }
            .onChange(of: scrollToMedicationID) { target in
                if let id = target {
                    withAnimation {
                        scrollProxy?.scrollTo(id, anchor: .top)
                    }
                    scrollToMedicationID = nil
                }
            }
            .onChange(of: deepLinkMedicationID) { target in
                if let id = target {
                    scrollToMedicationID = id
                    if let med = store.medications.first(where: { $0.id == id }) {
                        detailTarget = med
                    }
                    deepLinkMedicationID = nil
                }
            }
            .alert(isPresented: $showNotificationDeniedAlert) {
                let message = deniedMedName.map { String(format: NSLocalizedString("Enable notifications in Settings to get reminders for %@.", comment: ""), $0) } ?? NSLocalizedString("Enable notifications in Settings to get reminders.", comment: "")
                return Alert(
                    title: Text(NSLocalizedString("Notifications Disabled", comment: "")),
                    message: Text(message),
                    primaryButton: .default(Text(NSLocalizedString("Open Settings", comment: ""))) {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                    },
                    secondaryButton: .cancel()
                )
            }
        }
    }
}

// Old AddMedicationView and EditMedicationView removed — replaced by MedicationFormView.swift

#Preview {
    MedicationsView().environmentObject(DataStore())
}

// MARK: - Image helpers
private extension MedicationsView {
    var filteredMedications: [Medication] {
        store.medications.filter { med in
            let matchesSearch: Bool
            if searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                matchesSearch = true
            } else {
                let query = searchText.lowercased()
                matchesSearch = med.name.lowercased().contains(query) || med.dose.lowercased().contains(query)
            }
            return matchesSearch
        }
    }

    var setupMedications: [Medication] {
        filteredMedications.filter { $0.isAsNeeded != true && $0.timesOfDay.isEmpty }
    }

    var activeScheduledMedications: [Medication] {
        filteredMedications.filter {
            $0.isAsNeeded != true && !$0.timesOfDay.isEmpty && $0.remindersEnabled
        }
    }

    var asNeededMedications: [Medication] {
        filteredMedications.filter { $0.isAsNeeded == true }
    }

    var pausedMedications: [Medication] {
        filteredMedications.filter {
            $0.isAsNeeded != true && !$0.timesOfDay.isEmpty && !$0.remindersEnabled
        }
    }

    var warningRow: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "bell.slash.fill")
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 6) {
                Text(NSLocalizedString("Notifications Disabled", comment: ""))
                    .appFont(.subheadline)
                Text(NSLocalizedString("Turn notifications on in Settings to receive medication reminders.", comment: ""))
                    .appFont(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private func medicationManagementRow(for med: Medication) -> some View {
        Button {
            detailTarget = med
        } label: {
            HStack(alignment: .center, spacing: 12) {
                medicationThumbnail(for: med)
                VStack(alignment: .leading, spacing: 3) {
                    Text(med.name)
                        .appFont(.subheadline)
                        .foregroundStyle(.primary)
                    Text(medicationScheduleSummary(for: med))
                        .appFont(.caption)
                        .foregroundStyle(.secondary)
                    HStack(spacing: 6) {
                        Text(nextDoseSummary(for: med))
                        if let fi = med.foodInstruction {
                            Text("· \(fi.shortLabel)")
                                .foregroundStyle(.orange)
                        }
                    }
                    .appFont(.caption)
                    .foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                VStack(alignment: .trailing, spacing: 6) {
                    AppBadge(text: medicationStateLabel(for: med), tint: medicationStateTint(for: med))
                    if med.isLowSupply, let days = med.daysOfSupplyRemaining {
                        AppBadge(
                            text: String(format: NSLocalizedString("%lld days left", comment: "supply badge"), days),
                            tint: days <= 3 ? .red : .orange
                        )
                    } else if med.isLowSupply {
                        AppBadge(text: NSLocalizedString("Low supply", comment: ""), tint: .orange)
                    }
                }
            }
        }
        .buttonStyle(.plain)
    }

    private func managementLinkRow(title: String, subtitle: String, systemImage: String, tint: Color) -> some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(tint.opacity(0.14))
                .frame(width: 38, height: 38)
                .overlay(
                    Image(systemName: systemImage)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(tint)
                )
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .appFont(.subheadline)
                    .foregroundStyle(.primary)
                Text(subtitle)
                    .appFont(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.tertiary)
        }
    }

    private func medicationScheduleSummary(for med: Medication) -> String {
        if med.isAsNeeded == true {
            return "\(med.dose) • \(NSLocalizedString("Take only when needed", comment: ""))"
        }
        if med.timesOfDay.isEmpty {
            return "\(med.dose) • \(NSLocalizedString("No schedule set", comment: ""))"
        }
        return "\(med.dose) • \(timesJoined(for: med))"
    }

    private func nextDoseSummary(for med: Medication) -> String {
        if med.isAsNeeded == true {
            return NSLocalizedString("Logged manually from Today", comment: "")
        }
        if !med.remindersEnabled {
            return NSLocalizedString("Reminders are paused", comment: "")
        }
        if med.timesOfDay.isEmpty {
            return NSLocalizedString("Add times to start reminders", comment: "")
        }
        return String(format: NSLocalizedString("Next: %@", comment: ""), nextDoseText(for: med))
    }

    private func medicationStateLabel(for med: Medication) -> String {
        if med.isAsNeeded == true {
            return NSLocalizedString("As needed", comment: "")
        }
        if med.timesOfDay.isEmpty {
            return NSLocalizedString("Needs setup", comment: "")
        }
        if !med.remindersEnabled {
            return NSLocalizedString("Paused", comment: "")
        }
        return NSLocalizedString("Active", comment: "")
    }

    private func medicationStateTint(for med: Medication) -> Color {
        if med.isAsNeeded == true {
            return .blue
        }
        if med.timesOfDay.isEmpty || !med.remindersEnabled {
            return .orange
        }
        return .green
    }

    private func timesJoined(for med: Medication) -> String {
        let formatter: DateFormatter = {
            let f = DateFormatter()
            f.timeStyle = .short
            return f
        }()
        let cal = Calendar.current
        let times = med.timesOfDay.compactMap { comps -> String? in
            guard let h = comps.hour, let m = comps.minute,
                  let date = cal.date(bySettingHour: h, minute: m, second: 0, of: Date()) else { return nil }
            return formatter.string(from: date)
        }
        return times.joined(separator: ", ")
    }

    private func nextDoseText(for med: Medication) -> String {
        let calendar = Calendar.current
        let now = Date()
        let sorted = med.timesOfDay.sorted { ($0.hour ?? 0, $0.minute ?? 0) < ($1.hour ?? 0, $1.minute ?? 0) }
        for offset in 0..<2 {
            guard let day = calendar.date(byAdding: .day, value: offset, to: calendar.startOfDay(for: now)) else { continue }
            for comps in sorted {
                guard let hour = comps.hour,
                      let minute = comps.minute,
                      let scheduled = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day),
                      med.isDoseActive(on: scheduled),
                      scheduled >= now else { continue }
                return scheduled.formatted(offset == 0 ? .dateTime.hour().minute() : .dateTime.weekday(.abbreviated).hour().minute())
            }
        }
        return NSLocalizedString("Not scheduled", comment: "")
    }

    @ViewBuilder
    private func medicationCard(for med: Medication) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            // Row 1: thumbnail + name/dose + status/toggle
            HStack(alignment: .center, spacing: 10) {
                medicationThumbnail(for: med)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(med.name)
                            .appFont(.headline)
                            .lineLimit(1)
                        if med.isAsNeeded != true && !med.remindersEnabled {
                            Text(NSLocalizedString("Paused", comment: ""))
                                .appFont(.caption)
                                .foregroundStyle(.orange)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Capsule().fill(Color.orange.opacity(0.12)))
                        }
                        if med.isAsNeeded == true {
                            Text(NSLocalizedString("PRN", comment: ""))
                                .appFont(.caption)
                                .foregroundStyle(.blue)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Capsule().fill(Color.blue.opacity(0.12)))
                        }
                    }
                    // Dose + times inline
                    HStack(spacing: 4) {
                        Text(med.dose)
                            .appFont(.caption)
                            .foregroundStyle(.secondary)
                        if !med.timesOfDay.isEmpty {
                            Text("·").foregroundStyle(.secondary)
                            timesText(for: med)
                        }
                    }
                }
                Spacer(minLength: 4)
                if med.isAsNeeded != true {
                    reminderToggle(for: med)
                }
            }

            // Row 2: supply + status + quick-take (all inline)
            HStack(spacing: 8) {
                if let remaining = med.pillsRemaining {
                    compactSupplyLabel(remaining: remaining, med: med)
                }
                compactCourseLabel(for: med)
                if let (status, date) = latestTodayAction(for: med) {
                    inlineStatusLabel(status: status, date: date)
                }
                Spacer(minLength: 0)
                if med.isAsNeeded != true && med.remindersEnabled {
                    compactQuickTakeButton(for: med)
                }
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(.secondarySystemBackground))
        )
        .contentShape(Rectangle())
        .onTapGesture { detailTarget = med }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private func compactSupplyLabel(remaining: Int, med: Medication) -> some View {
        let isLow = med.isLowSupply
        HStack(spacing: 4) {
            if isLow {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 13))
                    .foregroundStyle(.red)
            }
            if remaining == 0 {
                Text(NSLocalizedString("Out of pills", comment: ""))
                    .appFont(.caption)
                    .foregroundStyle(.red)
            } else if let days = med.daysOfSupplyRemaining, days > 0 {
                Text(String(format: NSLocalizedString("%lld pills · %lld d left", comment: "pills and days short"), remaining, days))
                    .appFont(.caption)
                    .foregroundStyle(isLow ? .red : .secondary)
            } else {
                Text(String(format: NSLocalizedString("%lld pills", comment: ""), remaining))
                    .appFont(.caption)
                    .foregroundStyle(isLow ? .red : .secondary)
            }
        }
    }

    @ViewBuilder
    private func compactCourseLabel(for med: Medication) -> some View {
        let threshold = UserDefaults.standard.object(forKey: "prefs.courseEndThresholdDays") as? Int ?? 3
        if let courseState = med.courseState(thresholdDays: threshold) {
            switch courseState {
            case .endingSoon(let daysRemaining):
                HStack(spacing: 4) {
                    Image(systemName: "calendar.badge.exclamationmark")
                        .font(.system(size: 13))
                    Text(String(format: NSLocalizedString("Ends in %lld d", comment: ""), daysRemaining))
                        .appFont(.caption)
                }
                .foregroundStyle(.orange)
            case .endsToday:
                HStack(spacing: 4) {
                    Image(systemName: "calendar.badge.exclamationmark")
                        .font(.system(size: 13))
                    Text(NSLocalizedString("Ends today", comment: ""))
                        .appFont(.caption)
                }
                .foregroundStyle(.orange)
            case .ended:
                HStack(spacing: 4) {
                    Image(systemName: "calendar.badge.exclamationmark")
                        .font(.system(size: 13))
                    Text(NSLocalizedString("Course ended", comment: ""))
                        .appFont(.caption)
                }
                .foregroundStyle(.red)
            default:
                EmptyView()
            }
        }
    }

    private func inlineStatusLabel(status: IntakeStatus, date: Date) -> some View {
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
    private func compactQuickTakeButton(for med: Medication) -> some View {
        if let dose = nextUntakenDose(for: med) {
            Button {
                // Rule: duplicate taken guard
                let dupCheck = MedicationRules.checkDuplicateTaken(
                    medicationID: med.id,
                    scheduleTime: dose.comps,
                    intakeLogs: store.intakeLogs
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
                    Image(systemName: "checkmark")
                        .font(.system(size: 13, weight: .bold))
                    Text(dose.timeStr)
                        .appFont(.caption)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }
            .buttonStyle(.borderedProminent)
            .tint(.green)
            .controlSize(.small)
        }
    }

    private func nextUntakenDose(for med: Medication) -> (comps: DateComponents, scheduledDate: Date, timeStr: String)? {
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
                let formatter = DateFormatter()
                formatter.timeStyle = .short
                let timeStr = formatter.string(from: scheduledDate)
                return (comps, scheduledDate, timeStr)
            }
        }
        return nil
    }

    @ViewBuilder
    private func medicationThumbnail(for med: Medication) -> some View {
        if let path = med.imagePath, let ui = loadMedicationImage(path: path) {
            Image(uiImage: ui)
                .resizable()
                .scaledToFill()
                .frame(width: 40, height: 40)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .accessibilityLabel(String(format: NSLocalizedString("%@ photo", comment: "Medication thumbnail accessibility"), med.name))
        } else {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.accentColor.opacity(0.10))
                .frame(width: 40, height: 40)
                .overlay(
                    Image(systemName: "pills.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(Color.accentColor)
                )
                .accessibilityHidden(true)
        }
    }

    private func timesText(for med: Medication) -> some View {
        let formatter: DateFormatter = {
            let f = DateFormatter()
            f.timeStyle = .short
            return f
        }()
        let cal = Calendar.current
        let times = med.timesOfDay.compactMap { comps -> String? in
            guard let h = comps.hour, let m = comps.minute,
                  let date = cal.date(bySettingHour: h, minute: m, second: 0, of: Date()) else { return nil }
            return formatter.string(from: date)
        }
        return Text(times.joined(separator: ", "))
            .appFont(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(1)
    }

    private func reminderToggle(for med: Medication) -> some View {
        Toggle(isOn: Binding(
            get: { med.remindersEnabled },
            set: { newVal in
                Task {
                    if newVal {
                        let granted = await NotificationManager.shared.ensureAuthorization()
                        await MainActor.run {
                            guard granted else {
                                deniedMedName = med.name
                                showNotificationDeniedAlert = true
                                var reverted = med
                                reverted.remindersEnabled = false
                                store.updateMedication(reverted)
                                refreshNotificationStatus()
                                return
                            }
                            var updated = med
                            updated.remindersEnabled = true
                            store.updateMedication(updated)
                            store.syncNotifications()
                            Haptics.impact(.light)
                            refreshNotificationStatus()
                        }
                    } else {
                        await MainActor.run {
                            var updated = med
                            updated.remindersEnabled = false
                            store.updateMedication(updated)
                            store.syncNotifications()
                            Haptics.impact(.light)
                            refreshNotificationStatus()
                        }
                    }
                }
            }
        )) {
            Text(NSLocalizedString("Remind", comment: ""))
        }
        .labelsHidden()
    }


    private func latestStatusIcon(_ status: IntakeStatus) -> String {
        switch status {
        case .taken: return "checkmark.circle.fill"
        case .skipped: return "xmark.circle.fill"
        case .snoozed: return "zzz"
        }
    }

    private func statusTint(for status: IntakeStatus) -> Color {
        switch status {
        case .taken: return .green
        case .skipped: return .orange
        case .snoozed: return .blue
        }
    }

    private func statusPrefix(for status: IntakeStatus) -> LocalizedStringKey {
        switch status {
        case .taken: return "Taken"
        case .skipped: return "Skipped"
        case .snoozed: return "Snoozed"
        }
    }


    private func latestTodayAction(for med: Medication) -> (IntakeStatus, Date)? {
        let cal = Calendar.current
        let start = cal.startOfDay(for: Date())
        let end = cal.date(byAdding: .day, value: 1, to: start)!
        let logs = store.intakeLogs
            .filter { $0.medicationID == med.id && $0.date >= start && $0.date < end }
            .sorted { $0.date > $1.date }
        guard let last = logs.first else { return nil }
        return (last.status, last.date)
    }
}

private extension MedicationsView {
    func refreshNotificationStatus() {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            DispatchQueue.main.async {
                self.notificationStatus = settings.authorizationStatus
            }
        }
    }

    func delete(at offsets: IndexSet) {
        let ids = offsets.map { filteredMedications[$0].id }
        let items = store.medications.filter { ids.contains($0.id) }
        items.forEach {
            NotificationManager.shared.cancelAll(for: $0)
            deleteMedicationImage(path: $0.imagePath)
        }
        let toRemove = IndexSet(store.medications.enumerated().compactMap { ids.contains($0.element.id) ? $0.offset : nil })
        store.removeMedication(at: toRemove)
        store.syncNotifications()
    }
}
