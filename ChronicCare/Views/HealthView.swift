import SwiftUI
import UserNotifications
import Charts

struct HealthView: View {
    @EnvironmentObject var store: DataStore
    @Binding var deepLinkMedicationID: UUID?
    @State private var scrollProxy: ScrollViewProxy?
    @State private var showAdd = false
    @State private var showAddMeasurement = false
    @State private var showSettings = false
    @State private var detailTarget: Medication? = nil
    @State private var editTarget: Medication? = nil
    @State private var showNotificationDeniedAlert = false
    @State private var deniedMedName: String? = nil
    @State private var notificationStatus: UNAuthorizationStatus = .notDetermined

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 16) {
                        if notificationStatus == .denied {
                            notificationWarningCard
                        }

                        healthOverviewCard
                        quickLinksCard

                        if let latest = store.measurements.first {
                            latestMeasurementCard(latest)
                        } else {
                            emptyMeasurementCard
                        }

                        medicationLibrary
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .padding(.bottom, 24)
                }
                .scrollDismissesKeyboard(.interactively)
                .onAppear { scrollProxy = proxy }
                .onChange(of: store.medications.count) { _ in scrollProxy = proxy }
            }
            .navigationTitle(NSLocalizedString("Health", comment: ""))
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button {
                            showAddMeasurement = true
                        } label: {
                            Label(NSLocalizedString("Log Measurement", comment: ""), systemImage: "waveform.path.ecg")
                        }

                        Button {
                            showSettings = true
                        } label: {
                            Label(NSLocalizedString("Settings", comment: ""), systemImage: "gearshape")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showAdd = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $showAdd) {
                AddMedicationView { med in
                    store.addMedication(med)
                    NotificationManager.shared.syncAll(medications: store.medications, intakeLogs: store.intakeLogs)
                    NotificationManager.shared.updateBadge(store: store)
                    refreshNotificationStatus()
                }
            }
            .sheet(isPresented: $showAddMeasurement) {
                AddMeasurementView { measurement in
                    store.addMeasurement(measurement)
                    Haptics.success()
                }
                .presentationDetents([.medium, .large])
            }
            .sheet(isPresented: $showSettings) {
                ProfileView()
                    .environmentObject(store)
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
                EditMedicationView(medication: med, onSave: { updated in
                    store.updateMedication(updated)
                    NotificationManager.shared.syncAll(medications: store.medications, intakeLogs: store.intakeLogs)
                    NotificationManager.shared.updateBadge(store: store)
                    refreshNotificationStatus()
                }, onDelete: {
                    if let idx = store.medications.firstIndex(where: { $0.id == med.id }) {
                        NotificationManager.shared.cancelAll(for: med)
                        removeMedImage(path: med.imagePath)
                        store.removeMedication(at: IndexSet(integer: idx))
                        NotificationManager.shared.syncAll(medications: store.medications, intakeLogs: store.intakeLogs)
                        NotificationManager.shared.updateBadge(store: store)
                        refreshNotificationStatus()
                    }
                })
            }
            .onAppear(perform: refreshNotificationStatus)
            .onChange(of: store.medications.count) { _ in refreshNotificationStatus() }
            .onChange(of: deepLinkMedicationID) { target in
                if let id = target {
                    withAnimation { scrollProxy?.scrollTo(id, anchor: .top) }
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

// MARK: - Medication List Helpers

private extension HealthView {
    var activeMedicationCount: Int {
        store.medications.filter { $0.remindersEnabled }.count
    }

    var courseReminderThresholdDays: Int {
        UserDefaults.standard.object(forKey: "prefs.courseEndThresholdDays") as? Int ?? 3
    }

    var lowSupplyCount: Int {
        store.medications.filter { $0.isLowSupply }.count
    }

    var reviewCount: Int {
        store.medications.filter { $0.isLowSupply || needsCourseAttention($0) }.count
    }

    var reminderRiskCount: Int {
        scheduledWithoutRemindersCount + untimedScheduledCount + (notificationStatus == .denied ? 1 : 0)
    }

    var scheduledWithoutRemindersCount: Int {
        store.medications.filter {
            $0.isAsNeeded != true && !$0.timesOfDay.isEmpty && !$0.remindersEnabled
        }.count
    }

    var untimedScheduledCount: Int {
        store.medications.filter {
            $0.isAsNeeded != true && $0.timesOfDay.isEmpty
        }.count
    }

    var reminderRiskText: String {
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

    var medicationSectionSubtitle: String {
        String(format: NSLocalizedString("%lld medications · %lld active", comment: ""), store.medications.count, activeMedicationCount)
    }

    var hasEmergencyCardContent: Bool {
        let info = store.emergencyInfo
        return !(info?.bloodType?.isEmpty ?? true)
            || !(info?.allergies?.isEmpty ?? true)
            || !(info?.medicalConditions?.isEmpty ?? true)
            || !((info?.emergencyContacts ?? []).isEmpty)
    }

    var emergencyCardSubtitle: String {
        hasEmergencyCardContent
            ? NSLocalizedString("View allergies, conditions, contacts, and current medications in one place.", comment: "")
            : NSLocalizedString("Add allergies, conditions, and contacts so emergency details are ready when needed.", comment: "")
    }

    var caregiversSubtitle: String {
        if store.caregivers.isEmpty {
            return NSLocalizedString("Add someone you trust so missed-dose support has a real contact path.", comment: "")
        }
        if store.caregivers.contains(where: \.notifyOnMiss) {
            return NSLocalizedString("Your support network is set up for missed-dose follow-up.", comment: "")
        }
        return NSLocalizedString("Caregivers are saved, but missed-dose support is still turned off for them.", comment: "")
    }

    private var notificationWarningCard: some View {
        TintedCard(tint: .orange) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "bell.slash.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.orange)
                VStack(alignment: .leading, spacing: 6) {
                    Text(NSLocalizedString("Notifications Disabled", comment: ""))
                        .appFont(.headline)
                    Text(NSLocalizedString("Turn notifications on in Settings to receive medication reminders.", comment: ""))
                        .appFont(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button(NSLocalizedString("Open", comment: "")) {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
    }

    private var healthOverviewCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 14) {
                Text(NSLocalizedString("Health Workspace", comment: ""))
                    .appFont(.title)
                    .fontWeight(.bold)
                Text(NSLocalizedString("Manage medications, review trends, and keep your latest readings close.", comment: ""))
                    .appFont(.caption)
                    .foregroundStyle(.secondary)

                HStack(spacing: 8) {
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
                    .padding(12)
                    .background(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(Color(.secondarySystemBackground))
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var quickLinksCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                Text(NSLocalizedString("Quick Links", comment: ""))
                    .appFont(.headline)

                VStack(spacing: 10) {
                    quickLinkRow(
                        title: NSLocalizedString("Emergency Card", comment: ""),
                        subtitle: emergencyCardSubtitle,
                        systemImage: "person.text.rectangle",
                        tint: .red
                    ) {
                        EmergencyCardView()
                            .environmentObject(store)
                    }

                    quickLinkRow(
                        title: NSLocalizedString("Caregivers", comment: ""),
                        subtitle: caregiversSubtitle,
                        systemImage: "person.2.fill",
                        tint: .blue
                    ) {
                        CaregiversView()
                            .environmentObject(store)
                    }

                    if activeMedicationCount > 0 {
                        quickLinkRow(
                            title: NSLocalizedString("Adherence Calendar", comment: ""),
                            subtitle: NSLocalizedString("Review your medication consistency across recent days.", comment: ""),
                            systemImage: "calendar",
                            tint: .green
                        ) {
                            AdherenceCalendarView()
                        }
                    }

                    quickLinkRow(
                        title: NSLocalizedString("View Trends", comment: ""),
                        subtitle: NSLocalizedString("See blood pressure, glucose, weight, and heart rate trends.", comment: ""),
                        systemImage: "chart.line.uptrend.xyaxis",
                        tint: .orange
                    ) {
                        EnhancedTrendsView()
                            .environmentObject(store)
                    }
                }
            }
        }
    }

    private func latestMeasurementCard(_ measurement: Measurement) -> some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text(NSLocalizedString("Latest Measurement", comment: ""))
                        .appFont(.headline)
                    Spacer()
                    Text(measurement.date, format: .dateTime.month(.abbreviated).day().hour().minute())
                        .appFont(.caption)
                        .foregroundStyle(.secondary)
                }

                latestMeasurementRow(measurement)
            }
        }
    }

    private var emptyMeasurementCard: some View {
        Card {
            EmptyStateView(
                systemImage: "waveform.path.ecg",
                title: NSLocalizedString("No measurements yet", comment: ""),
                subtitle: NSLocalizedString("Use the top-right menu to log your first blood pressure, glucose, weight, or heart rate reading.", comment: ""),
                actionTitle: NSLocalizedString("Log Measurement", comment: ""),
                action: { showAddMeasurement = true }
            )
        }
    }

    private var medicationLibrary: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(NSLocalizedString("Medication Library", comment: ""))
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
                ForEach(store.medications) { med in
                    medicationCard(for: med)
                        .id(med.id)
                }
            }
        }
    }

    private func overviewMetric(
        value: String,
        label: String,
        tint: Color
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(value)
                .font(.system(size: 24, weight: .bold, design: .rounded))
                .foregroundStyle(tint)
                .monospacedDigit()
            Text(label)
                .appFont(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, minHeight: 74, alignment: .topLeading)
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(tint.opacity(0.08))
        )
    }

    private func quickLinkRow<Destination: View>(
        title: String,
        subtitle: String,
        systemImage: String,
        tint: Color,
        @ViewBuilder destination: @escaping () -> Destination
    ) -> some View {
        NavigationLink(destination: destination) {
            HStack(alignment: .center, spacing: 12) {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(tint.opacity(0.14))
                    .frame(width: 40, height: 40)
                    .overlay(
                        Image(systemName: systemImage)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(tint)
                    )

                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .appFont(.subheadline)
                        .foregroundStyle(.primary)
                    Text(subtitle)
                        .appFont(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color(.secondarySystemBackground))
            )
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    func medicationCard(for med: Medication) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 10) {
                medicationThumbnail(for: med)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(med.name).appFont(.headline).lineLimit(1)
                        if med.isAsNeeded != true && med.timesOfDay.isEmpty {
                            libraryBadge(NSLocalizedString("Needs Setup", comment: ""), tint: .orange)
                        }
                        if !med.remindersEnabled {
                            libraryBadge(NSLocalizedString("Paused", comment: ""), tint: .orange)
                        }
                        if med.isAsNeeded == true {
                            libraryBadge(NSLocalizedString("PRN", comment: ""), tint: .blue)
                        }
                    }
                    HStack(spacing: 4) {
                        Text(med.dose).appFont(.caption).foregroundStyle(.secondary)
                        if !med.timesOfDay.isEmpty {
                            Text("·").foregroundStyle(.secondary)
                            timesText(for: med)
                        }
                    }
                }
                Spacer(minLength: 4)
                reminderToggle(for: med)
            }

            HStack(spacing: 8) {
                if let remaining = med.pillsRemaining {
                    compactSupplyLabel(remaining: remaining, med: med)
                }
                compactCourseLabel(for: med)
                if let (status, date) = latestTodayAction(for: med) {
                    inlineStatusLabel(status: status, date: date)
                }
                Spacer(minLength: 0)
                if med.remindersEnabled {
                    compactQuickTakeButton(for: med)
                }
            }

            if med.isLowSupply || needsCourseAttention(med) {
                quickMaintenanceActions(for: med)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(.systemBackground))
                .shadow(color: .black.opacity(0.06), radius: 4, x: 0, y: 2)
        )
        .contentShape(Rectangle())
        .onTapGesture { detailTarget = med }
        .padding(.vertical, 2)
    }

    private func libraryBadge(_ text: String, tint: Color) -> some View {
        AppBadge(text: text, tint: tint)
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

    func inlineStatusLabel(status: IntakeStatus, date: Date) -> some View {
        HStack(spacing: 5) {
            Image(systemName: latestStatusIcon(status)).font(.system(size: 14, weight: .semibold)).foregroundStyle(statusTint(for: status))
            Text(statusPrefix(for: status)).appFont(.caption).foregroundStyle(statusTint(for: status))
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
                store.upsertIntake(
                    medicationID: med.id,
                    status: .taken,
                    scheduleTime: dose.comps,
                    scheduledDate: dose.scheduledDate
                )
                store.decrementPills(for: med.id)
                NotificationManager.shared.suppressToday(for: med.id, timeComponents: dose.comps)
                NotificationManager.shared.cancelDoseNotifications(for: med.id, timeComponents: dose.comps)
                NotificationManager.shared.syncAll(medications: store.medications, intakeLogs: store.intakeLogs)
                NotificationManager.shared.updateBadge(store: store)
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
                  scheduledDate <= now else { continue }
            if !resolved {
                let formatter = DateFormatter(); formatter.timeStyle = .short
                let timeStr = formatter.string(from: scheduledDate)
                return (comps, scheduledDate, timeStr)
            }
        }
        return nil
    }

    @ViewBuilder
    func medicationThumbnail(for med: Medication) -> some View {
        if let path = med.imagePath, let ui = loadMedImage(path: path) {
            Image(uiImage: ui).resizable().scaledToFill()
                .frame(width: 40, height: 40)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        } else {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
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
        return Text(times.joined(separator: ", ")).appFont(.caption).foregroundStyle(.secondary).lineLimit(1)
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
                                deniedMedName = med.name
                                showNotificationDeniedAlert = true
                                var reverted = med; reverted.remindersEnabled = false
                                store.updateMedication(reverted)
                                refreshNotificationStatus()
                                return
                            }
                            var updated = med; updated.remindersEnabled = true
                            store.updateMedication(updated)
                            NotificationManager.shared.syncAll(medications: store.medications, intakeLogs: store.intakeLogs)
                            NotificationManager.shared.updateBadge(store: store)
                            Haptics.impact(.light)
                            refreshNotificationStatus()
                        }
                    } else {
                        await MainActor.run {
                            var updated = med; updated.remindersEnabled = false
                            store.updateMedication(updated)
                            NotificationManager.shared.syncAll(medications: store.medications, intakeLogs: store.intakeLogs)
                            NotificationManager.shared.updateBadge(store: store)
                            Haptics.impact(.light)
                            refreshNotificationStatus()
                        }
                    }
                }
            }
        )) { Text(NSLocalizedString("Remind", comment: "")) }
        .labelsHidden()
    }

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
        NotificationManager.shared.syncAll(medications: store.medications, intakeLogs: store.intakeLogs)
        NotificationManager.shared.updateBadge(store: store)
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
        NotificationManager.shared.syncAll(medications: store.medications, intakeLogs: store.intakeLogs)
        NotificationManager.shared.updateBadge(store: store)
        Haptics.success()
    }

    func refreshNotificationStatus() {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            DispatchQueue.main.async { self.notificationStatus = settings.authorizationStatus }
        }
    }
}

private struct MedicationDetailView: View {
    @EnvironmentObject var store: DataStore
    let medication: Medication
    let onEdit: (Medication) -> Void
    private let snapshotColumns = [GridItem(.flexible()), GridItem(.flexible())]

    private var reminderStrategy: AdaptiveReminderStrategy {
        AdaptiveReminderEngine.strategy(for: medication, intakeLogs: store.intakeLogs)
    }

    private var reminderProfile: AdherenceProfile {
        AdaptiveReminderEngine.profile(for: medication, intakeLogs: store.intakeLogs)
    }

    private var lastTakenLog: IntakeLog? {
        store.intakeLogs
            .filter { $0.medicationID == medication.id && $0.status == .taken }
            .max(by: { $0.effectiveRecordedAt < $1.effectiveRecordedAt })
    }

    private var adherence7: Double {
        store.adherencePercent(for: medication.id, days: 7)
    }

    private var adherence30: Double {
        store.adherencePercent(for: medication.id, days: 30)
    }

    private var streakCount: Int {
        store.currentStreak(for: medication.id)
    }

    private var scheduleText: String {
        guard medication.isAsNeeded != true else {
            return NSLocalizedString("Log doses when needed from Today.", comment: "")
        }
        guard !medication.timesOfDay.isEmpty else {
            return NSLocalizedString("No fixed times are configured yet.", comment: "")
        }
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        let values = medication.timesOfDay.compactMap { comps -> String? in
            guard let hour = comps.hour,
                  let minute = comps.minute,
                  let date = Calendar.current.date(bySettingHour: hour, minute: minute, second: 0, of: Date()) else { return nil }
            return formatter.string(from: date)
        }
        return values.joined(separator: ", ")
    }

    private var modeLabel: String {
        medication.isAsNeeded == true ? NSLocalizedString("As Needed", comment: "") : NSLocalizedString("Scheduled", comment: "")
    }

    private var modeTint: Color {
        medication.isAsNeeded == true ? .blue : .green
    }

    private var reminderStateLabel: String {
        if medication.isAsNeeded == true {
            return NSLocalizedString("Manual Logging", comment: "")
        }
        if !medication.remindersEnabled {
            return NSLocalizedString("Reminders Off", comment: "")
        }
        if medication.timesOfDay.isEmpty {
            return NSLocalizedString("Times Missing", comment: "")
        }
        return NSLocalizedString("Reminders On", comment: "")
    }

    private var reminderStateTint: Color {
        if medication.isAsNeeded == true { return .blue }
        if !medication.remindersEnabled || medication.timesOfDay.isEmpty { return .orange }
        return .green
    }

    private var nextDoseText: String {
        guard medication.isAsNeeded != true else { return NSLocalizedString("PRN", comment: "") }
        guard medication.remindersEnabled else { return NSLocalizedString("Off", comment: "") }

        let calendar = Calendar.current
        let now = Date()
        let sorted = medication.timesOfDay.sorted { ($0.hour ?? 0, $0.minute ?? 0) < ($1.hour ?? 0, $1.minute ?? 0) }
        for offset in 0..<2 {
            guard let day = calendar.date(byAdding: .day, value: offset, to: calendar.startOfDay(for: now)) else { continue }
            for comps in sorted {
                guard let hour = comps.hour,
                      let minute = comps.minute,
                      let scheduled = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day),
                      scheduled >= now else { continue }
                return scheduled.formatted(offset == 0 ? .dateTime.hour().minute() : .dateTime.weekday(.abbreviated).hour().minute())
            }
        }
        return NSLocalizedString("Not scheduled", comment: "")
    }

    private var lastTakenText: String {
        guard let lastTakenLog else { return NSLocalizedString("None", comment: "") }
        if Calendar.current.isDateInToday(lastTakenLog.effectiveRecordedAt) {
            return lastTakenLog.effectiveRecordedAt.formatted(date: .omitted, time: .shortened)
        }
        return lastTakenLog.effectiveRecordedAt.formatted(date: .abbreviated, time: .shortened)
    }

    private var detailStatusLine: String {
        if medication.isAsNeeded == true {
            return NSLocalizedString("Manual logging only.", comment: "")
        }
        if !medication.remindersEnabled {
            return NSLocalizedString("Fixed reminders are off.", comment: "")
        }
        if medication.timesOfDay.isEmpty {
            return NSLocalizedString("Reminder times need setup.", comment: "")
        }
        return String(format: NSLocalizedString("Next: %@", comment: ""), nextDoseText)
    }

    private var reminderSummary: String {
        if medication.isAsNeeded == true {
            return NSLocalizedString("This medication is set to as-needed, so fixed reminders are off.", comment: "")
        }
        if !medication.remindersEnabled {
            return NSLocalizedString("Fixed reminders are turned off for this medication.", comment: "")
        }
        if medication.timesOfDay.isEmpty {
            return NSLocalizedString("No reminder times are set yet.", comment: "")
        }

        let startText = reminderStrategy.leadMinutes > 0
            ? String(format: NSLocalizedString("Starts %lld minutes early", comment: ""), reminderStrategy.leadMinutes)
            : NSLocalizedString("Starts at the scheduled time", comment: "")
        let followUpText = reminderStrategy.followUpIntervals.isEmpty
            ? NSLocalizedString("No follow-up reminders", comment: "")
            : String(format: NSLocalizedString("%lld follow-up reminders", comment: ""), reminderStrategy.followUpIntervals.count)
        return "\(startText) · \(followUpText)"
    }

    private var reminderExplanation: String {
        if medication.isAsNeeded == true {
            return NSLocalizedString("No fixed notifications for PRN medications.", comment: "")
        }
        if !medication.remindersEnabled {
            return NSLocalizedString("Turn reminders on to include this medication in scheduling.", comment: "")
        }
        if reminderProfile.sampleCount == 0 {
            return NSLocalizedString("The reminder pattern will adapt after more scheduled logs.", comment: "")
        }

        switch reminderStrategy.riskLevel {
        case .high:
            return String(format: NSLocalizedString("Higher recent miss risk. Using %lld follow-ups.", comment: ""), reminderStrategy.followUpIntervals.count)
        case .medium:
            return String(format: NSLocalizedString("Some recent delays or snoozes. Using %lld follow-ups.", comment: ""), reminderStrategy.followUpIntervals.count)
        case .low:
            return NSLocalizedString("Recent history looks consistent. Keeping reminders lighter.", comment: "")
        }
    }

    private var reminderRiskLabel: String {
        switch reminderStrategy.riskLevel {
        case .high:
            return NSLocalizedString("High Attention", comment: "")
        case .medium:
            return NSLocalizedString("Balanced", comment: "")
        case .low:
            return NSLocalizedString("Light Touch", comment: "")
        }
    }

    private var reminderRiskTint: Color {
        switch reminderStrategy.riskLevel {
        case .high: return .orange
        case .medium: return .blue
        case .low: return .green
        }
    }

    private var maintenanceSummary: [String] {
        var items: [String] = []
        if let remaining = medication.pillsRemaining {
            if let days = medication.daysOfSupplyRemaining {
                items.append(String(format: NSLocalizedString("%lld pills left, about %lld days remaining.", comment: ""), remaining, days))
            } else {
                items.append(String(format: NSLocalizedString("%lld pills left.", comment: ""), remaining))
            }
        }
        if let courseState = medication.courseState() {
            switch courseState {
            case .ended(let daysPast):
                items.append(String(format: NSLocalizedString("Course ended %lld days ago.", comment: ""), daysPast))
            case .endsToday:
                items.append(NSLocalizedString("Course ends today.", comment: ""))
            case .endingSoon(let daysRemaining):
                items.append(String(format: NSLocalizedString("Course ends in %lld days.", comment: ""), daysRemaining))
            case .scheduled(let daysRemaining):
                items.append(String(format: NSLocalizedString("Course ends in %lld days.", comment: ""), daysRemaining))
            }
        }
        return items
    }

    private var correlatedTypes: [MeasurementType] {
        (medication.category == .unspecified ? nil : medication.category)?.correlatedMeasurementTypes ?? []
    }

    private func relatedMeasurements(for type: MeasurementType) -> [Measurement]? {
        let data = store.measurements
            .filter { $0.type == type }
            .sorted { $0.date < $1.date }
            .suffix(30)
        return data.count >= 2 ? Array(data) : nil
    }

    private func relatedMeasurementSummary(for type: MeasurementType, data: [Measurement]) -> String {
        guard let latest = data.last else { return NSLocalizedString("No recent readings.", comment: "") }
        if type == .bloodPressure, let dia = latest.diastolic {
            return String(format: NSLocalizedString("Latest: %d/%d mmHg", comment: ""), Int(latest.value), Int(dia))
        }
        if type == .bloodGlucose {
            let preferred = UnitPreferences.mgdlToPreferred(latest.value)
            let formatted = UnitPreferences.glucoseUnit == .mgdL ? String(format: "%.0f", preferred) : String(format: "%.1f", preferred)
            return String(format: NSLocalizedString("Latest: %@ %@", comment: ""), formatted, UnitPreferences.glucoseUnit.rawValue)
        }
        return String(format: NSLocalizedString("Latest: %.1f %@", comment: ""), latest.value, type.unit)
    }

    private func relatedMeasurementTrendText(for type: MeasurementType, data: [Measurement]) -> String {
        guard let first = data.first, let last = data.last else {
            return NSLocalizedString("No recent trend available.", comment: "")
        }
        let delta = last.value - first.value
        let threshold: Double = type == .bloodPressure ? 4 : type == .bloodGlucose ? 8 : 1
        if abs(delta) < threshold {
            return NSLocalizedString("Recent readings look fairly stable.", comment: "")
        }
        return delta < 0
            ? NSLocalizedString("Recent readings are trending lower.", comment: "")
            : NSLocalizedString("Recent readings are trending higher.", comment: "")
    }

    private var hasRelatedMeasurementData: Bool {
        correlatedTypes.contains { relatedMeasurements(for: $0) != nil }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Card {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack(alignment: .top) {
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(medication.name)
                                        .appFont(.title)
                                        .fontWeight(.bold)
                                    Text(medication.dose)
                                        .appFont(.headline)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                reminderBadge(reminderStateLabel, tint: reminderStateTint)
                            }

                            HStack(spacing: 8) {
                                reminderBadge(modeLabel, tint: modeTint)
                                if let categoryName = medication.displayCategoryName {
                                    reminderBadge(categoryName, tint: .secondary)
                                }
                            }

                            Text(scheduleText)
                                .appFont(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }

                    Card {
                        VStack(alignment: .leading, spacing: 14) {
                            HStack {
                                Text(NSLocalizedString("Snapshot", comment: ""))
                                    .appFont(.headline)
                                Spacer()
                                reminderBadge(detailStatusLine, tint: reminderStateTint)
                            }
                            LazyVGrid(columns: snapshotColumns, spacing: 10) {
                                detailMetric(value: lastTakenText, label: NSLocalizedString("Last taken", comment: ""), tint: .green)
                                detailMetric(value: nextDoseText, label: NSLocalizedString("Next dose", comment: ""), tint: .blue)
                                detailMetric(value: String(format: "%.0f%%", adherence7 * 100), label: NSLocalizedString("7-day", comment: ""), tint: adherence7 >= 0.8 ? .green : adherence7 >= 0.5 ? .orange : .red)
                                detailMetric(value: "\(streakCount)", label: NSLocalizedString("day streak", comment: ""), tint: .blue)
                            }
                        }
                    }

                    Card {
                        NavigationLink {
                            AdherenceCalendarView(medicationID: medication.id)
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(NSLocalizedString("Adherence History", comment: ""))
                                        .appFont(.headline)
                                    Text(NSLocalizedString("Review daily check-ins and missed doses.", comment: ""))
                                        .appFont(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(.tertiary)
                            }
                        }
                        .buttonStyle(.plain)
                    }

                    Card {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Text(NSLocalizedString("Reminder Strategy", comment: ""))
                                    .appFont(.headline)
                                Spacer()
                                reminderBadge(reminderRiskLabel, tint: reminderRiskTint)
                            }
                            Text(reminderSummary)
                                .appFont(.subheadline)
                                .fontWeight(.semibold)
                            Text(reminderExplanation)
                                .appFont(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                            if medication.isAsNeeded != true && (!medication.remindersEnabled || medication.timesOfDay.isEmpty) {
                                Button(NSLocalizedString("Fix Reminder Setup", comment: "")) {
                                    onEdit(medication)
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                            }
                        }
                    }

                    if correlatedTypes.isEmpty {
                        Card {
                            EmptyStateView(
                                systemImage: "waveform.badge.questionmark",
                                title: NSLocalizedString("No linked health signals", comment: ""),
                                subtitle: NSLocalizedString("Choose a medication category if you want this page to connect the medication with related measurements like blood pressure or glucose.", comment: "")
                            )
                        }
                    }

                    ForEach(correlatedTypes, id: \.self) { measurementType in
                        if let data = relatedMeasurements(for: measurementType) {
                            Card {
                                VStack(alignment: .leading, spacing: 12) {
                                    HStack {
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(NSLocalizedString("Related Measurements", comment: ""))
                                                .appFont(.headline)
                                            Text(measurementType.displayName)
                                                .appFont(.subheadline)
                                                .foregroundStyle(measurementType.tint)
                                        }
                                        Spacer()
                                        Text(relatedMeasurementSummary(for: measurementType, data: data))
                                            .appFont(.caption)
                                            .foregroundStyle(.secondary)
                                    }

                                    Chart(data) { measurement in
                                        LineMark(
                                            x: .value("Date", measurement.date),
                                            y: .value("Value", measurement.value)
                                        )
                                        .foregroundStyle(measurementType.tint)
                                        .interpolationMethod(.catmullRom)

                                        PointMark(
                                            x: .value("Date", measurement.date),
                                            y: .value("Value", measurement.value)
                                        )
                                        .foregroundStyle(measurementType.tint)
                                        .symbolSize(18)
                                    }
                                    .frame(height: 120)
                                    .chartXAxis(.hidden)
                                    .chartYAxis {
                                        AxisMarks(position: .leading, values: .automatic(desiredCount: 3))
                                    }

                                    Text(relatedMeasurementTrendText(for: measurementType, data: data))
                                        .appFont(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }

                    if !correlatedTypes.isEmpty && !hasRelatedMeasurementData {
                        Card {
                            EmptyStateView(
                                systemImage: "waveform.path.ecg.rectangle",
                                title: NSLocalizedString("No related measurements yet", comment: ""),
                                subtitle: NSLocalizedString("Log measurements like blood pressure or glucose to see whether this medication lines up with recent trends.", comment: "")
                            )
                        }
                    }

                    if !maintenanceSummary.isEmpty {
                        Card {
                            VStack(alignment: .leading, spacing: 10) {
                                Text(NSLocalizedString("Maintenance", comment: ""))
                                    .appFont(.headline)
                                ForEach(maintenanceSummary, id: \.self) { item in
                                    HStack(alignment: .top, spacing: 8) {
                                        Circle()
                                            .fill(Color.secondary.opacity(0.45))
                                            .frame(width: 5, height: 5)
                                            .padding(.top, 7)
                                        Text(item)
                                            .appFont(.subheadline)
                                            .foregroundStyle(.secondary)
                                            .fixedSize(horizontal: false, vertical: true)
                                    }
                                }
                            }
                        }
                    }

                    Button {
                        onEdit(medication)
                    } label: {
                        Text(NSLocalizedString("Edit Medication", comment: ""))
                            .appFont(.subheadline)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding(16)
            }
            .navigationTitle(NSLocalizedString("Medication Detail", comment: ""))
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private func detailMetric(value: String, label: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value)
                .appFont(.headline)
                .foregroundStyle(tint)
                .monospacedDigit()
            Text(label)
                .appFont(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(tint.opacity(0.08))
        )
    }

    private func reminderBadge(_ text: String, tint: Color) -> some View {
        AppBadge(text: text, tint: tint)
    }
}

private struct ReminderDiagnosticsView: View {
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
            NotificationManager.shared.syncAll(medications: store.medications, intakeLogs: store.intakeLogs)
            NotificationManager.shared.updateBadge(store: store)
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
            NotificationManager.shared.syncAll(medications: store.medications, intakeLogs: store.intakeLogs)
            NotificationManager.shared.updateBadge(store: store)
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
            EditMedicationView(medication: med, onSave: { updated in
                store.updateMedication(updated)
                NotificationManager.shared.syncAll(medications: store.medications, intakeLogs: store.intakeLogs)
                NotificationManager.shared.updateBadge(store: store)
            }, onDelete: {
                if let idx = store.medications.firstIndex(where: { $0.id == med.id }) {
                    NotificationManager.shared.cancelAll(for: med)
                    store.removeMedication(at: IndexSet(integer: idx))
                    NotificationManager.shared.syncAll(medications: store.medications, intakeLogs: store.intakeLogs)
                    NotificationManager.shared.updateBadge(store: store)
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
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(tint.opacity(0.08))
        )
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
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(.secondarySystemBackground))
        )
    }
}

// MARK: - Measurement Row

private extension HealthView {
    func latestMeasurementRow(_ m: Measurement) -> some View {
        HStack(spacing: 10) {
            Circle().fill(m.type.tint).frame(width: 8, height: 8)
            Text(m.type.rawValue).appFont(.subheadline)
            Spacer()
            Group {
                if m.type == .bloodPressure, let dia = m.diastolic {
                    Text("\(Int(m.value))/\(Int(dia)) \(m.type.unit)")
                } else if m.type == .bloodGlucose {
                    let v = UnitPreferences.mgdlToPreferred(m.value)
                    let formatted = UnitPreferences.glucoseUnit == .mgdL ? String(format: "%.0f", v) : String(format: "%.1f", v)
                    Text("\(formatted) \(UnitPreferences.glucoseUnit.rawValue)")
                } else {
                    Text("\(String(format: "%.1f", m.value)) \(m.type.unit)")
                }
            }
            .appFont(.subheadline)
            .fontWeight(.medium)
        }
    }
}
