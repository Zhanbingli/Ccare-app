import SwiftUI
import UserNotifications

struct DashboardView: View {
    @EnvironmentObject var store: DataStore
    @State private var showAddMedication = false
    @State private var reminderFixTarget: Medication? = nil
    @State private var notificationStatus: UNAuthorizationStatus = .notDetermined
    @State private var showTakenConfirmation = false
    @State private var takenMedName: String = ""
    @State private var pendingNoteItem: MedSchedule?
    @State private var showDuplicateAlert = false
    @State private var duplicateAlertMinutes: Int = 0
    @State private var safetyAlerts: [String] = []
    @State private var showSafetyAlerts = false
    @AppStorage("units.glucose") private var glucoseUnitRaw: String = GlucoseUnit.mgdL.rawValue
    @AppStorage("prefs.graceMinutes") private var graceMinutes: Int = 30
    @State private var tick = false
    private let refreshTimer = Timer.publish(every: 60, on: .main, in: .common).autoconnect()

    private struct MedSchedule: Identifiable {
        let id: String // medID_HH:MM
        let med: Medication
        let time: Date
        var scheduleKey: String {
            let comps = Calendar.current.dateComponents([.hour, .minute], from: time)
            return String(format: "%@_%02d:%02d", med.id.uuidString, comps.hour ?? 0, comps.minute ?? 0)
        }
    }

    private struct ScheduleLookupKey: Hashable {
        let medicationID: UUID
        let scheduleKey: String?
    }

    private enum TodayMedStatus {
        case none
        case taken(Date)
        case skipped(Date)
        case snoozed(Date)
        case dueSoon // past scheduled time but within grace period
        case overdue

        var displayText: String {
            switch self {
            case .taken:   return NSLocalizedString("Taken", comment: "")
            case .skipped: return NSLocalizedString("Skipped", comment: "")
            case .snoozed: return NSLocalizedString("Snoozed", comment: "")
            case .overdue: return NSLocalizedString("Overdue", comment: "")
            case .dueSoon: return NSLocalizedString("Due now", comment: "")
            case .none:    return NSLocalizedString("Later", comment: "")
            }
        }

        var tint: Color {
            switch self {
            case .taken:   return .green
            case .skipped: return .orange
            case .snoozed: return .blue
            case .overdue: return .red
            case .dueSoon: return .orange
            case .none:    return .secondary
            }
        }

        var iconName: String {
            switch self {
            case .taken:   return "checkmark.circle.fill"
            case .skipped: return "xmark.circle.fill"
            case .snoozed: return "zzz"
            case .overdue: return "exclamationmark.circle.fill"
            case .dueSoon: return "clock.fill"
            case .none:    return "clock"
            }
        }

        var isFinal: Bool {
            switch self {
            case .taken, .skipped: return true
            default: return false
            }
        }
    }

    private struct TodayState {
        let schedules: [MedSchedule]
        let statusCache: [String: TodayMedStatus]
        let takenCount: Int
        let skippedCount: Int
        let totalCount: Int
        let overdueCount: Int
        let remainingCount: Int
        let actionableSchedules: [MedSchedule]
        let currentAction: MedSchedule?
        let nextUpcoming: MedSchedule?
        let prnMeds: [Medication]
    }

    private func buildTodayState() -> TodayState {
        let schedules = todaySchedules()
        let statusLookup = latestTodayLogMap()
        let statusCache: [String: TodayMedStatus] = Dictionary(uniqueKeysWithValues: schedules.map { item in
            let s = status(for: item.med, at: item.time, lookup: statusLookup)
            let resolved: TodayMedStatus = {
                switch s {
                case .none:
                    let now = Date()
                    let graceMin = Double(graceMinutes)
                    if now > item.time.addingTimeInterval(graceMin * 60) { return .overdue }
                    else if now > item.time { return .dueSoon }
                    else { return s }
                default: return s
                }
            }()
            return (item.id, resolved)
        })
        let takenCount = statusCache.values.filter { if case .taken = $0 { return true } else { return false } }.count
        let skippedCount = statusCache.values.filter { if case .skipped = $0 { return true } else { return false } }.count
        let totalCount = schedules.count
        let actionableSchedules = schedules.filter { canLogDose(for: $0, status: statusCache[$0.id] ?? .none) }
        let nextUpcoming = schedules.first {
            let status = statusCache[$0.id] ?? .none
            return !canLogDose(for: $0, status: status) && !status.isFinal
        }
        let overdueCount = schedules.filter {
            if case .overdue = statusCache[$0.id] ?? .none { return true }
            return false
        }.count
        return TodayState(
            schedules: schedules,
            statusCache: statusCache,
            takenCount: takenCount,
            skippedCount: skippedCount,
            totalCount: totalCount,
            overdueCount: overdueCount,
            remainingCount: max(totalCount - takenCount - skippedCount, 0),
            actionableSchedules: actionableSchedules,
            currentAction: actionableSchedules.first,
            nextUpcoming: nextUpcoming,
            prnMeds: store.medications.filter { $0.isAsNeeded == true }
        )
    }

    var body: some View {
        let _ = tick // force re-render on timer
        NavigationStack {
            let state = buildTodayState()
            let schedules = state.schedules
            let statusCache = state.statusCache
            let takenCount = state.takenCount
            let skippedCount = state.skippedCount
            let totalCount = state.totalCount
            let currentAction = state.currentAction
            let nextUpcoming = state.nextUpcoming
            let overdueCount = state.overdueCount
            let remainingCount = state.remainingCount
            let prnMeds = state.prnMeds

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if store.medications.isEmpty {
                        Card {
                            EmptyStateView(
                                systemImage: "pills.circle.fill",
                                title: NSLocalizedString("No medications yet", comment: ""),
                                subtitle: NSLocalizedString("Add your first medication to start daily reminders and logging.", comment: ""),
                                actionTitle: NSLocalizedString("Add Medication", comment: ""),
                                action: { showAddMedication = true }
                            )
                        }
                    } else {
                        todayHeader(
                            actionableCount: state.actionableSchedules.count,
                            takenCount: takenCount,
                            totalCount: totalCount
                        )

                        currentStateCard(
                            currentAction: currentAction,
                            nextUpcoming: nextUpcoming,
                            takenCount: takenCount,
                            totalCount: totalCount,
                            statusCache: statusCache
                        )

                        if !schedules.isEmpty {
                            todayTimelineCard(
                                schedules: schedules,
                                statusCache: statusCache
                            )
                        }

                        summaryStrip(
                            completedCount: takenCount,
                            overdueCount: overdueCount,
                            remainingCount: remainingCount
                        )

                        if !prnMeds.isEmpty {
                            asNeededCompactSection(medications: prnMeds)
                        }

                        if hasReminderSetupIssues {
                            reminderRepairCard()
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 6)
                .padding(.bottom, 24)
            }
            .sheet(isPresented: $showAddMedication) {
                MedicationFormView(editing: nil, onSave: { med in
                    store.addMedication(med)
                    store.syncNotifications()
                })
            }
            .sheet(item: $reminderFixTarget) { med in
                MedicationFormView(editing: med, onSave: { updated in
                    store.updateMedication(updated)
                    store.syncNotifications()
                    refreshNotificationStatus()
                })
            }
            .refreshable {
                let now = Date()
                store.syncNotifications(now: now)
                refreshNotificationStatus()
                store.objectWillChange.send()
            }
            .toolbar(.hidden, for: .navigationBar)
            .onReceive(refreshTimer) { _ in tick.toggle() }
            // Rule 1: Duplicate taken confirmation
            .alert(NSLocalizedString("Already Taken", comment: ""), isPresented: $showDuplicateAlert) {
                Button(NSLocalizedString("Take Again", comment: ""), role: .destructive) {
                    commitTaken(note: nil)
                }
                Button(NSLocalizedString("Cancel", comment: ""), role: .cancel) {
                    pendingNoteItem = nil
                }
            } message: {
                Text(String(format: NSLocalizedString("You took this %lld minutes ago. Are you sure you want to log another dose?", comment: ""), duplicateAlertMinutes))
            }
            .overlay {
                if showTakenConfirmation {
                    TakenConfirmationOverlay(medicationName: takenMedName)
                        .transition(.opacity)
                        .zIndex(100)
                }
            }
            .onAppear {
                refreshNotificationStatus()
                runDailySafetyCheck()
            }
            // Safety alerts from rule engine
            .alert(NSLocalizedString("Safety Check", comment: ""), isPresented: $showSafetyAlerts) {
                Button(NSLocalizedString("OK", comment: ""), role: .cancel) { }
            } message: {
                Text(safetyAlerts.joined(separator: "\n\n"))
            }
        }
    }
}

// MARK: - Taken Confirmation Overlay
private struct TakenConfirmationOverlay: View {
    let medicationName: String
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 72, weight: .bold))
                .foregroundStyle(.green)
                .symbolRenderingMode(.hierarchical)
            Text(medicationName)
                .appFont(.headline)
                .foregroundStyle(.primary)
            Text(NSLocalizedString("Taken!", comment: ""))
                .appFont(.title)
                .fontWeight(.bold)
                .foregroundStyle(.green)
        }
        .padding(40)
        .background(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(.ultraThickMaterial)
                .shadow(color: .black.opacity(0.15), radius: 20, y: 10)
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black.opacity(0.25).ignoresSafeArea())
    }
}

private extension DashboardView {
    private var untimedScheduledMeds: [Medication] {
        store.medications.filter { $0.isAsNeeded != true && $0.timesOfDay.isEmpty }
    }

    private var disabledReminderMeds: [Medication] {
        store.medications.filter { $0.isAsNeeded != true && !$0.timesOfDay.isEmpty && !$0.remindersEnabled }
    }

    private var hasReminderSetupIssues: Bool {
        notificationStatus == .denied || !untimedScheduledMeds.isEmpty || !disabledReminderMeds.isEmpty
    }

    private var sevenDayCheckInCount: Int {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        guard let start = calendar.date(byAdding: .day, value: -6, to: today) else { return 0 }
        let dayStarts = Set(store.intakeLogs.compactMap { log -> Date? in
            guard log.status == .taken, log.date >= start else { return nil }
            return calendar.startOfDay(for: log.date)
        })
        return min(dayStarts.count, 7)
    }

    private func todaySchedules() -> [MedSchedule] {
        let cal = Calendar.current
        let now = Date()
        var items: [MedSchedule] = []
        for med in store.medications where med.remindersEnabled && med.isAsNeeded != true {
            for t in med.timesOfDay {
                guard let h = t.hour, let m = t.minute else { continue }
                if let date = cal.date(bySettingHour: h, minute: m, second: 0, of: now) {
                    guard med.isDoseActive(on: date) else { continue }
                    let id = String(format: "%@_%02d:%02d", med.id.uuidString, h, m)
                    items.append(MedSchedule(id: id, med: med, time: date))
                }
            }
        }
        return items.sorted { $0.time < $1.time }
    }

    @ViewBuilder
    private func todayHeader(
        actionableCount: Int,
        takenCount: Int,
        totalCount: Int
    ) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text(NSLocalizedString("Today", comment: ""))
                    .appFont(.largeTitle)
                    .fontWeight(.bold)
                Text(Date(), format: .dateTime.weekday(.wide).month(.abbreviated).day())
                    .appFont(.subheadline)
                    .foregroundStyle(.secondary)
                Text(todayProgressText(taken: takenCount, total: totalCount))
                    .appFont(.footnote)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 12)

            if actionableCount > 0 {
                AppBadge(
                    text: "\(actionableCount)",
                    tint: actionableCount > 1 ? .orange : .green,
                    icon: "checklist"
                )
            }
        }
        .padding(.top, 8)
    }

    @ViewBuilder
    private func currentStateCard(
        currentAction: MedSchedule?,
        nextUpcoming: MedSchedule?,
        takenCount: Int,
        totalCount: Int,
        statusCache: [String: TodayMedStatus]
    ) -> some View {
        if let item = currentAction {
            let status = statusCache[item.id] ?? .none
            TintedCard(tint: heroTint(for: status)) {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(actionStatusHeadline(for: status))
                            .appFont(.caption)
                            .foregroundStyle(.secondary)
                        Text(item.med.name)
                            .appFont(.largeTitle)
                            .fontWeight(.bold)
                        Text("\(item.med.dose) • \(item.time.formatted(date: .omitted, time: .shortened))")
                            .appFont(.subheadline)
                            .foregroundStyle(.secondary)
                        Text(todayProgressText(taken: takenCount, total: totalCount))
                            .appFont(.caption)
                            .foregroundStyle(.secondary)
                    }

                    HStack(spacing: 10) {
                        Button {
                            beginTakeFlow(for: item)
                        } label: {
                            Text(NSLocalizedString("Take", comment: ""))
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        .tint(.green)

                        Button {
                            snoozeDose(for: item)
                        } label: {
                            Text(NSLocalizedString("Snooze", comment: ""))
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.large)
                        .tint(snoozeButtonTint(for: item))

                        Button {
                            skipDose(for: item)
                        } label: {
                            Text(NSLocalizedString("Skip", comment: ""))
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.large)
                        .tint(.orange)
                    }
                }
            }
        } else if let nextUpcoming {
            TintedCard(tint: .blue) {
                VStack(alignment: .leading, spacing: 12) {
                    Text(NSLocalizedString("No dose due right now", comment: ""))
                        .appFont(.headline)
                    Text(nextUpcoming.med.name)
                        .appFont(.title)
                        .fontWeight(.bold)
                    Text("\(nextUpcoming.med.dose) • \(nextUpcoming.time.formatted(date: .omitted, time: .shortened))")
                        .appFont(.subheadline)
                        .foregroundStyle(.secondary)
                    Text(todayProgressText(taken: takenCount, total: totalCount))
                        .appFont(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        } else {
            TintedCard(tint: .green) {
                VStack(alignment: .leading, spacing: 12) {
                    Text(NSLocalizedString("Today complete", comment: ""))
                        .appFont(.headline)
                    Text(NSLocalizedString("All scheduled doses are handled.", comment: ""))
                        .appFont(.subheadline)
                        .foregroundStyle(.secondary)
                    if let tomorrowText = tomorrowsFirstDoseText() {
                        Text(String(format: NSLocalizedString("Next dose: %@", comment: ""), tomorrowText))
                            .appFont(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private func todayTimelineCard(
        schedules: [MedSchedule],
        statusCache: [String: TodayMedStatus]
    ) -> some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                Text(NSLocalizedString("Today's Schedule", comment: ""))
                    .appFont(.headline)

                VStack(spacing: 10) {
                    ForEach(schedules) { item in
                        timelineRow(item: item, status: statusCache[item.id] ?? .none)
                    }
                }
            }
        }
    }

    private func timelineRow(item: MedSchedule, status: TodayMedStatus) -> some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: status.iconName)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(status.tint)
                .frame(width: 24)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                Text(item.med.name)
                    .appFont(.subheadline)
                    .foregroundStyle(.primary)
                Text("\(item.med.dose) • \(item.time.formatted(date: .omitted, time: .shortened))")
                    .appFont(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Text(status.displayText)
                .appFont(.caption)
                .foregroundStyle(status.tint)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(item.med.name), \(item.med.dose), \(item.time.formatted(date: .omitted, time: .shortened)), \(status.displayText)")
    }

    private func summaryStrip(
        completedCount: Int,
        overdueCount: Int,
        remainingCount: Int
    ) -> some View {
        Card {
            HStack(spacing: 0) {
                summaryMetric(value: "\(completedCount)", label: NSLocalizedString("Completed", comment: ""), tint: .green)
                summaryDivider
                summaryMetric(value: "\(overdueCount)", label: NSLocalizedString("Overdue", comment: ""), tint: overdueCount > 0 ? .red : .secondary)
                summaryDivider
                summaryMetric(value: "\(remainingCount)", label: NSLocalizedString("Remaining", comment: ""), tint: .secondary)
            }
        }
    }

    private var summaryDivider: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.08))
            .frame(width: 1, height: 36)
    }

    private func summaryMetric(value: String, label: String, tint: Color) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .appFont(.headline)
                .foregroundStyle(tint)
                .monospacedDigit()
            Text(label)
                .appFont(.footnote)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private func asNeededCompactSection(medications: [Medication]) -> some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text(NSLocalizedString("As Needed", comment: ""))
                        .appFont(.headline)
                    Spacer()
                    AppBadge(text: NSLocalizedString("Optional", comment: ""), tint: .secondary)
                }

                ForEach(Array(medications.prefix(3).enumerated()), id: \.element.id) { _, med in
                    InsetPanel {
                        prnMedRow(med: med)
                    }
                }
            }
        }
    }

    private func actionStatusHeadline(for status: TodayMedStatus) -> String {
        switch status {
        case .overdue:
            return NSLocalizedString("Dose overdue", comment: "")
        case .dueSoon:
            return NSLocalizedString("Dose due now", comment: "")
        case .snoozed:
            return NSLocalizedString("Snoozed dose", comment: "")
        default:
            return NSLocalizedString("Current dose", comment: "")
        }
    }


    private func tomorrowsFirstDoseText() -> String? {
        let cal = Calendar.current
        let tomorrow = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: Date()))
        guard let tomorrow else { return nil }
        let upcoming = store.medications
            .filter { $0.isAsNeeded != true && $0.remindersEnabled }
            .flatMap { med in
                med.timesOfDay.compactMap { comps -> (Medication, Date)? in
                    guard let hour = comps.hour,
                          let minute = comps.minute,
                          let date = cal.date(bySettingHour: hour, minute: minute, second: 0, of: tomorrow),
                          med.isDoseActive(on: date) else { return nil }
                    return (med, date)
                }
            }
            .sorted { $0.1 < $1.1 }
            .first

        guard let upcoming else { return nil }
        return "\(upcoming.0.name) • \(upcoming.1.formatted(date: .omitted, time: .shortened))"
    }

    private func skipDose(for item: MedSchedule) {
        let comps = Calendar.current.dateComponents([.hour, .minute], from: item.time)
        if Calendar.current.isDateInToday(item.time) {
            NotificationManager.shared.suppressToday(for: item.med.id, timeComponents: comps)
        }
        store.upsertIntake(
            medicationID: item.med.id,
            status: .skipped,
            scheduleTime: comps,
            at: item.time,
            scheduledDate: item.time
        )
        NotificationManager.shared.cancelDoseNotifications(for: item.med.id, timeComponents: comps, scheduledDate: item.time, now: item.time)
        store.syncNotifications()
        Haptics.impact(.light)
    }

    private func snoozeDose(for item: MedSchedule) {
        let comps = Calendar.current.dateComponents([.hour, .minute], from: item.time)
        let count = NotificationManager.shared.snoozeCount(for: item.med.id, scheduleTime: comps)
        let result = MedicationRules.nextSnooze(for: item.med.id, currentSnoozeCount: count)

        switch result {
        case .snooze(let minutes):
            NotificationManager.shared.incrementSnoozeCount(for: item.med.id, scheduleTime: comps)
            NotificationManager.shared.scheduleSnooze(for: item.med, minutes: minutes, scheduleTime: comps, scheduledDate: item.time)
            if Calendar.current.isDateInToday(item.time) {
                NotificationManager.shared.suppressToday(for: item.med.id, timeComponents: comps)
            }
            store.upsertIntake(
                medicationID: item.med.id,
                status: .snoozed,
                scheduleTime: comps,
                at: item.time,
                scheduledDate: item.time
            )
            NotificationManager.shared.updateBadge(store: store)
            Haptics.impact(.light)
        case .exhausted:
            skipDose(for: item)
        }
    }

    @ViewBuilder
    private func focusHeroCard(
        schedules: [MedSchedule],
        statusCache: [String: TodayMedStatus],
        takenCount: Int,
        totalCount: Int
    ) -> some View {
        let nextActionableItem = schedules.first { item in
            canLogDose(for: item, status: statusCache[item.id] ?? .none)
        }

        if let item = nextActionableItem {
            let status = statusCache[item.id] ?? .none
            TintedCard(tint: heroTint(for: status)) {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(alignment: .top, spacing: 10) {
                        ZStack {
                            Circle()
                                .fill(heroTint(for: status).opacity(0.14))
                                .frame(width: 44, height: 44)
                            Image(systemName: heroSymbol(for: status))
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundStyle(heroTint(for: status))
                        }

                        VStack(alignment: .leading, spacing: 6) {
                            Text(heroEyebrow(for: status))
                                .appFont(.caption)
                                .foregroundStyle(.secondary)
                            Text(item.med.name)
                                .appFont(.title)
                                .fontWeight(.bold)
                            Text("\(item.med.dose) · \(item.time, style: .time)")
                                .appFont(.subheadline)
                                .foregroundStyle(.secondary)
                            Text(heroSupportText(for: item, status: status))
                                .appFont(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        statusBadge(for: item, status: status)
                    }

                    InsetPanel(tint: heroTint(for: status)) {
                        Text(todayProgressText(taken: takenCount, total: totalCount))
                            .appFont(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Button {
                        beginTakeFlow(for: item)
                    } label: {
                        Label(NSLocalizedString("Take Now", comment: ""), systemImage: "checkmark.circle.fill")
                            .frame(maxWidth: .infinity)
                            .appFont(.headline)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.green)
                    .controlSize(.large)
                    .accessibilityLabel(String(format: NSLocalizedString("Take %@ %@ now", comment: "Take medication accessibility"), item.med.name, item.med.dose))
                }
            }
        } else if let upcoming = schedules.first(where: { !(statusCache[$0.id] ?? .none).isFinal }) {
            Card {
                VStack(alignment: .leading, spacing: 14) {
                    Text(NSLocalizedString("Up Next", comment: ""))
                        .appFont(.caption)
                        .foregroundStyle(.secondary)
                    Text(upcoming.med.name)
                        .appFont(.title)
                        .fontWeight(.bold)
                    Text("\(upcoming.med.dose) · \(upcoming.time, style: .time)")
                        .appFont(.subheadline)
                        .foregroundStyle(.secondary)
                    Text(NSLocalizedString("Nothing needs action yet. Your next scheduled dose is lined up.", comment: ""))
                        .appFont(.caption)
                        .foregroundStyle(.secondary)
                    InsetPanel {
                        Text(todayProgressText(taken: takenCount, total: totalCount))
                            .appFont(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        } else {
            TintedCard(tint: .green) {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(alignment: .center, spacing: 14) {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.system(size: 34, weight: .semibold))
                            .foregroundStyle(.green)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(NSLocalizedString("All caught up", comment: ""))
                                .appFont(.title)
                                .fontWeight(.bold)
                            Text(NSLocalizedString("There are no scheduled doses waiting for you right now.", comment: ""))
                                .appFont(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    InsetPanel(tint: .green) {
                        Text(NSLocalizedString("Today is clear for now. PRN medications stay below as optional logs only.", comment: ""))
                            .appFont(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private func heroSymbol(for status: TodayMedStatus) -> String {
        switch status {
        case .overdue:
            return "exclamationmark.circle.fill"
        case .dueSoon:
            return "clock.badge.checkmark.fill"
        case .snoozed:
            return "zzz"
        default:
            return "checkmark.circle.fill"
        }
    }

    private func reminderRepairCard() -> some View {
        let issueText: String = {
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
        }()

        let actionTitle: String = {
            if notificationStatus == .denied {
                return NSLocalizedString("Open Settings", comment: "")
            }
            if !untimedScheduledMeds.isEmpty {
                return NSLocalizedString("Set Time", comment: "")
            }
            return NSLocalizedString("Turn On", comment: "")
        }()

        return TintedCard(tint: .orange) {
            HStack(alignment: .center, spacing: 12) {
                Image(systemName: "bell.badge.fill")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(.orange)
                    .frame(width: 44, height: 44)
                    .background(
                        Circle()
                            .fill(Color.orange.opacity(0.12))
                    )

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
                    handleReminderRepair()
                }
                .buttonStyle(.borderedProminent)
                .tint(.orange)
                .controlSize(.small)
            }
        }
    }

    private func sevenDayRhythmCard(
        scheduledMedicationCount: Int,
        setupIssueCount: Int,
        checkInDays: Int
    ) -> some View {
        let hasSetupIssues = setupIssueCount > 0
        let tint: Color = hasSetupIssues ? .orange : (checkInDays >= 7 ? .green : .blue)
        let title = hasSetupIssues
            ? NSLocalizedString("Finish Reminder Setup", comment: "")
            : NSLocalizedString("7-Day Rhythm", comment: "")
        let message: String = {
            if hasSetupIssues {
                return String(format: NSLocalizedString("%lld scheduled medications need reminder times or reminders turned on before a 7-day trial is reliable.", comment: ""), setupIssueCount)
            }
            if scheduledMedicationCount == 0 {
                return NSLocalizedString("No fixed medications are scheduled. Log as-needed doses only when you actually take them.", comment: "")
            }
            if checkInDays == 0 {
                return NSLocalizedString("Start today: respond to each due dose, then come back tomorrow.", comment: "")
            }
            if checkInDays >= 7 {
                return NSLocalizedString("You have checked in across the last 7 days. Keep the same rhythm.", comment: "")
            }
            return String(format: NSLocalizedString("%lld of 7 days checked in. Keep logging each due dose for one week.", comment: ""), checkInDays)
        }()

        return Card {
            HStack(alignment: .center, spacing: 12) {
                Image(systemName: hasSetupIssues ? "bell.badge.fill" : "calendar.badge.checkmark")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(tint)
                    .frame(width: 42, height: 42)
                    .background(
                        Circle()
                            .fill(tint.opacity(0.10))
                    )

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .appFont(.headline)
                    Text(message)
                        .appFont(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 8)

                if !hasSetupIssues, scheduledMedicationCount > 0 {
                    AppBadge(text: "\(min(checkInDays, 7))/7", tint: tint)
                }
            }
        }
    }

    private func groupedScheduleCard(
        title: String,
        subtitle: String,
        items: [MedSchedule],
        statusCache: [String: TodayMedStatus]
    ) -> some View {
        let tint = attentionTint(for: items, statusCache: statusCache)

        return Group {
            if let tint {
                TintedCard(tint: tint) {
                    groupedScheduleCardContent(
                        title: title,
                        subtitle: subtitle,
                        items: items,
                        statusCache: statusCache,
                        emphasized: true,
                        accentTint: tint
                    )
                }
            } else {
                Card {
                    groupedScheduleCardContent(
                        title: title,
                        subtitle: subtitle,
                        items: items,
                        statusCache: statusCache,
                        emphasized: false,
                        accentTint: nil
                    )
                }
            }
        }
    }

    private func groupedScheduleCardContent(
        title: String,
        subtitle: String,
        items: [MedSchedule],
        statusCache: [String: TodayMedStatus],
        emphasized: Bool,
        accentTint: Color?
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 10) {
                Text(title)
                    .appFont(.headline)
                    .fontWeight(emphasized ? .bold : .semibold)
                Spacer()
                let count = items.count
                AppBadge(
                    text: count == 1
                        ? NSLocalizedString("1 item", comment: "")
                        : String(format: NSLocalizedString("%lld items", comment: ""), count),
                    tint: accentTint ?? .secondary
                )
            }

            Text(subtitle)
                .appFont(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            VStack(spacing: 10) {
                ForEach(Array(items.enumerated()), id: \.element.id) { _, item in
                    medRow(item: item, status: statusCache[item.id] ?? .none, emphasizeUrgency: emphasized)
                }
            }
        }
    }

    private func prnCard(medications: [Medication]) -> some View {
        let visibleMeds = Array(medications.prefix(2))
        let hiddenCount = max(medications.count - visibleMeds.count, 0)
        return Card {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline) {
                    Text(NSLocalizedString("As Needed", comment: ""))
                        .appFont(.headline)
                    Spacer()
                    AppBadge(text: NSLocalizedString("Optional", comment: ""), tint: .secondary)
                }
                Text(NSLocalizedString("Log PRN medication only when you actually take it.", comment: ""))
                    .appFont(.caption)
                    .foregroundStyle(.secondary)

                VStack(spacing: 10) {
                    ForEach(Array(visibleMeds.enumerated()), id: \.element.id) { _, med in
                        InsetPanel {
                            prnMedRow(med: med)
                        }
                    }
                }

                if hiddenCount > 0 {
                    Text(String(format: NSLocalizedString("%lld more as-needed medications saved.", comment: ""), hiddenCount))
                        .appFont(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func latestTodayLogMap(now: Date = Date()) -> [ScheduleLookupKey: IntakeLog] {
        let cal = Calendar.current
        let start = cal.startOfDay(for: now)
        let end = cal.date(byAdding: .day, value: 1, to: start)!
        let todaysLogs = store.intakeLogs
            .filter { $0.date >= start && $0.date < end }
            .sorted { $0.date > $1.date }
        var result: [ScheduleLookupKey: IntakeLog] = [:]
        for log in todaysLogs {
            let key = ScheduleLookupKey(medicationID: log.medicationID, scheduleKey: log.scheduleKey)
            if result[key] == nil {
                result[key] = log
            }
        }
        return result
    }

    private func status(for med: Medication, at time: Date, lookup: [ScheduleLookupKey: IntakeLog]) -> TodayMedStatus {
        let cal = Calendar.current
        let comps = cal.dateComponents([.hour, .minute], from: time)
        let key = String(format: "%02d:%02d", comps.hour ?? 0, comps.minute ?? 0)
        let directKey = ScheduleLookupKey(medicationID: med.id, scheduleKey: key)
        let allowNil = med.timesOfDay.count <= 1
        let fallbackKey = allowNil ? ScheduleLookupKey(medicationID: med.id, scheduleKey: nil) : nil
        let log = lookup[directKey] ?? (fallbackKey.flatMap { lookup[$0] })
        guard let entry = log else { return .none }
        switch entry.status {
        case .taken:
            return .taken(entry.date)
        case .skipped:
            return .skipped(entry.date)
        case .snoozed:
            return .snoozed(entry.date)
        }
    }

    private func heroTint(for status: TodayMedStatus) -> Color {
        switch status {
        case .overdue:
            return .red
        case .dueSoon:
            return .orange
        case .snoozed:
            return .blue
        default:
            return .green
        }
    }

    private func heroEyebrow(for status: TodayMedStatus) -> String {
        switch status {
        case .overdue:
            return NSLocalizedString("Overdue Dose", comment: "")
        case .dueSoon:
            return NSLocalizedString("Due Right Now", comment: "")
        case .snoozed:
            return NSLocalizedString("Snoozed Dose", comment: "")
        default:
            return NSLocalizedString("Next Dose", comment: "")
        }
    }

    private func heroSupportText(for item: MedSchedule, status: TodayMedStatus) -> String {
        switch status {
        case .overdue:
            return NSLocalizedString("Past your grace window. Handle this first.", comment: "")
        case .dueSoon:
            return NSLocalizedString("Current dose. Clear this before the rest.", comment: "")
        case .snoozed:
            return NSLocalizedString("Snoozed earlier. Back at the top.", comment: "")
        default:
            return NSLocalizedString("Next scheduled medication today.", comment: "")
        }
    }

    private func attentionTint(for items: [MedSchedule], statusCache: [String: TodayMedStatus]) -> Color? {
        let statuses = items.map { statusCache[$0.id] ?? .none }
        if statuses.contains(where: {
            if case .overdue = $0 { return true }
            return false
        }) {
            return .red
        }
        if statuses.contains(where: {
            if case .dueSoon = $0 { return true }
            if case .snoozed = $0 { return true }
            return false
        }) {
            return .orange
        }
        return nil
    }

    @ViewBuilder
    private func statusBadge(for item: MedSchedule, status: TodayMedStatus) -> some View {
        let tint = statusBadgeTint(for: status)
        if let label = statusBadgeLabel(for: item, status: status) {
            AppBadge(text: label, tint: tint, icon: statusBadgeIcon(for: status))
        }
    }

    private func statusBadgeLabel(for item: MedSchedule, status: TodayMedStatus) -> String? {
        switch status {
        case .overdue:
            return actionStatusLabel(for: status)
        case .dueSoon:
            return actionStatusLabel(for: status)
        case .snoozed:
            return actionStatusLabel(for: status)
        case .none:
            return item.time.formatted(date: .omitted, time: .shortened)
        case .taken, .skipped:
            return nil
        }
    }

    private func actionStatusLabel(for status: TodayMedStatus) -> String? {
        switch status {
        case .overdue:
            return NSLocalizedString("Overdue", comment: "")
        case .dueSoon:
            return NSLocalizedString("Due now", comment: "")
        case .snoozed:
            return NSLocalizedString("Snoozed", comment: "")
        default:
            return nil
        }
    }

    private func statusBadgeTint(for status: TodayMedStatus) -> Color {
        switch status {
        case .overdue:
            return .red
        case .dueSoon:
            return .orange
        case .snoozed:
            return .blue
        default:
            return .secondary
        }
    }

    private func statusBadgeIcon(for status: TodayMedStatus) -> String {
        switch status {
        case .overdue:
            return "exclamationmark.circle.fill"
        case .dueSoon:
            return "clock.fill"
        case .snoozed:
            return "zzz"
        case .none:
            return "clock"
        case .taken:
            return "checkmark.circle.fill"
        case .skipped:
            return "xmark.circle.fill"
        }
    }

    private func todayProgressText(taken: Int, total: Int) -> String {
        guard total > 0 else {
            return NSLocalizedString("No fixed doses scheduled today.", comment: "")
        }
        return String(format: NSLocalizedString("%lld of %lld fixed doses handled today.", comment: ""), taken, total)
    }

    private func beginTakeFlow(for item: MedSchedule) {
        let comps = Calendar.current.dateComponents([.hour, .minute], from: item.time)
        let dupCheck = MedicationRules.checkDuplicateTaken(
            medicationID: item.med.id,
            scheduleTime: comps,
            intakeLogs: store.intakeLogs
        )
        if case .blocked(let mins) = dupCheck {
            pendingNoteItem = item
            duplicateAlertMinutes = mins
            showDuplicateAlert = true
        } else {
            pendingNoteItem = item
            commitTaken(note: nil)
        }
    }

    // MARK: - Medication Row (Things-style: tap circle = take)
    @ViewBuilder
    private func medRow(item: MedSchedule, status: TodayMedStatus, emphasizeUrgency: Bool = false) -> some View {
        HStack(alignment: .center, spacing: 12) {
            // Tappable circle — primary action
            Button {
                if canLogDose(for: item, status: status) {
                    beginTakeFlow(for: item)
                }
            } label: {
                statusDot(for: status)
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
            .disabled(!canLogDose(for: item, status: status))

            // Content
            VStack(alignment: .leading, spacing: 2) {
                Text(item.med.name)
                    .appFont(.body)
                    .strikethrough(status.isFinal, color: .secondary)
                    .foregroundStyle(status.isFinal ? .secondary : .primary)
                Text("\(item.med.dose) · \(item.time, style: .time)")
                    .appFont(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 4)

            rowStatusAccessory(for: item, status: status)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, emphasizeUrgency ? 10 : 8)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(rowBackgroundTint(for: status, emphasized: emphasizeUrgency))
        )
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private func rowStatusAccessory(for item: MedSchedule, status: TodayMedStatus) -> some View {
        switch status {
        case .dueSoon, .overdue:
            compactStatusBadge(for: status)
        case .snoozed:
            VStack(alignment: .trailing, spacing: 8) {
                compactStatusBadge(for: status)
                Button {
                    beginTakeFlow(for: item)
                } label: {
                    Text(NSLocalizedString("Take", comment: ""))
                        .appFont(.caption)
                        .fontWeight(.semibold)
                }
                .buttonStyle(.bordered)
                .tint(.green)
                .controlSize(.mini)
            }
        default:
            EmptyView()
        }
    }

    private func compactStatusBadge(for status: TodayMedStatus) -> some View {
        let tint = statusBadgeTint(for: status)
        let label = actionStatusLabel(for: status) ?? ""

        return AppBadge(text: label, tint: tint, icon: statusBadgeIcon(for: status))
    }

    private func rowBackgroundTint(for status: TodayMedStatus, emphasized: Bool) -> Color {
        guard emphasized else {
            switch status {
            case .overdue:
                return Color.red.opacity(0.07)
            case .dueSoon:
                return Color.orange.opacity(0.06)
            case .snoozed:
                return Color.blue.opacity(0.05)
            default:
                return Color.primary.opacity(0.03)
            }
        }

        switch status {
        case .overdue:
            return Color.red.opacity(0.12)
        case .dueSoon:
            return Color.orange.opacity(0.11)
        case .snoozed:
            return Color.blue.opacity(0.10)
        default:
            return Color.white.opacity(0.45)
        }
    }

    private func prnMedRow(med: Medication) -> some View {
        let cal = Calendar.current
        let dayStart = cal.startOfDay(for: Date())
        let dayEnd = cal.date(byAdding: .day, value: 1, to: dayStart)!
        let todayCount = store.intakeLogs.filter {
            $0.medicationID == med.id && $0.date >= dayStart && $0.date < dayEnd && $0.status == .taken
        }.count

        return HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(med.name).appFont(.body)
                Text(med.dose).appFont(.caption).foregroundStyle(.secondary)
            }

            Spacer(minLength: 4)

            HStack(spacing: 10) {
                if todayCount > 0 {
                    Text(String(format: NSLocalizedString("Taken %lld×", comment: ""), todayCount))
                        .appFont(.caption)
                        .foregroundStyle(.green)
                }

                Button {
                    let now = Date()
                    let comps = cal.dateComponents([.hour, .minute], from: now)
                    store.recordTakenDose(
                        medicationID: med.id,
                        scheduleTime: comps,
                        scheduledDate: now,
                        scheduleKeyOverride: "prn_\(now.timeIntervalSince1970)"
                    )
                    Haptics.success()
                } label: {
                    Text(NSLocalizedString("Take Now", comment: ""))
                        .appFont(.caption)
                        .fontWeight(.semibold)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                }
                .buttonStyle(.borderedProminent)
                .tint(.blue)
                .controlSize(.small)
            }
        }
        .contentShape(Rectangle())
    }



    private func commitTaken(note: String?) {
        guard let item = pendingNoteItem else { return }
        let comps = Calendar.current.dateComponents([.hour, .minute], from: item.time)
        store.recordTakenDose(
            medicationID: item.med.id,
            scheduleTime: comps,
            scheduledDate: item.time,
            note: note
        )
        NotificationManager.shared.suppressToday(for: item.med.id, timeComponents: comps)
        NotificationManager.shared.cancelDoseNotifications(for: item.med.id, timeComponents: comps, scheduledDate: item.time, now: item.time)
        store.syncNotifications()
        Haptics.success()
        takenMedName = item.med.name
        withAnimation(.easeInOut(duration: 0.25)) { showTakenConfirmation = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.3) {
            withAnimation(.easeInOut(duration: 0.3)) { showTakenConfirmation = false }
        }
        pendingNoteItem = nil
    }

    private func handleReminderRepair() {
        if notificationStatus == .denied {
            if let url = URL(string: UIApplication.openSettingsURLString) {
                UIApplication.shared.open(url)
            }
            return
        }

        if let med = untimedScheduledMeds.first {
            reminderFixTarget = med
            return
        }

        if !disabledReminderMeds.isEmpty {
            Task {
                let granted = await NotificationManager.shared.ensureAuthorization()
                await MainActor.run {
                    guard granted else {
                        refreshNotificationStatus()
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
                    refreshNotificationStatus()
                    Haptics.success()
                }
            }
        }
    }

    private func refreshNotificationStatus() {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            DispatchQueue.main.async {
                notificationStatus = settings.authorizationStatus
            }
        }
    }

    @ViewBuilder
    private func statusDot(for status: TodayMedStatus) -> some View {
        switch status {
        case .taken:
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(.green)
        case .skipped:
            Image(systemName: "xmark.circle.fill")
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(.orange)
        case .snoozed:
            Image(systemName: "zzz")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(.blue)
                .frame(width: 24)
        case .overdue:
            Image(systemName: "exclamationmark.circle.fill")
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(.red)
        case .dueSoon:
            Image(systemName: "clock.fill")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(.orange)
                .frame(width: 24)
        case .none:
            Image(systemName: "circle")
                .font(.system(size: 24, weight: .regular))
                .foregroundStyle(.secondary.opacity(0.5))
        }
    }

    private func canLogDose(for item: MedSchedule, status: TodayMedStatus) -> Bool {
        guard !status.isFinal else { return false }
        switch status {
        case .dueSoon, .overdue, .snoozed:
            return true
        case .none, .taken, .skipped:
            return false
        }
    }

    private func runDailySafetyCheck() {
        let key = "lastSafetyCheckDate"
        let today = Calendar.current.startOfDay(for: Date())
        if let last = UserDefaults.standard.object(forKey: key) as? Date,
           Calendar.current.isDate(last, inSameDayAs: today) {
            return
        }

        let summary = MedicationRules.dailySafetyCheck(
            medications: store.medications,
            intakeLogs: store.intakeLogs,
            consecutiveMissedDaysProvider: { store.consecutiveMissedDays(for: $0) }
        )
        var alerts: [String] = []
        alerts.append(contentsOf: summary.missEscalations)
        alerts.append(contentsOf: summary.timingConflicts)
        alerts.append(contentsOf: summary.makeupAvailable)

        UserDefaults.standard.set(today, forKey: key)

        if !alerts.isEmpty {
            safetyAlerts = alerts
            showSafetyAlerts = true
        }
    }

    private func snoozeButtonTint(for item: MedSchedule) -> Color {
        let comps = Calendar.current.dateComponents([.hour, .minute], from: item.time)
        let count = NotificationManager.shared.snoozeCount(for: item.med.id, scheduleTime: comps)
        let result = MedicationRules.nextSnooze(for: item.med.id, currentSnoozeCount: count)
        if result.isExhausted { return .red }
        return count >= 1 ? .orange : Color(.secondaryLabel)
    }

}

#Preview {
    DashboardView().environmentObject(DataStore())
}
