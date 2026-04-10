import SwiftUI

struct DashboardView: View {
    @EnvironmentObject var store: DataStore
    @State private var showAddMedication = false
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
    }

    var body: some View {
        let _ = tick // force re-render on timer
        NavigationStack {
            let schedules = todaySchedules()
            let statusLookup = latestTodayLogMap()
            // Resolve statuses upfront (including grace period)
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
            let totalCount = schedules.count
            let adherence = totalCount > 0 ? Double(takenCount) / Double(totalCount) : 0
            let actionableSchedules = schedules.filter { canLogDose(for: $0, status: statusCache[$0.id] ?? .none) }
            let currentActionID = actionableSchedules.first?.id
            let followUpActionable = actionableSchedules.filter { $0.id != currentActionID }
            let overdueQueue = followUpActionable.filter {
                if case .overdue = statusCache[$0.id] ?? .none { return true }
                return false
            }
            let readyQueue = followUpActionable.filter {
                switch statusCache[$0.id] ?? .none {
                case .dueSoon, .snoozed:
                    return true
                default:
                    return false
                }
            }
            let laterSchedules = schedules.filter {
                !isFinalStatus(statusCache[$0.id] ?? .none) &&
                !canLogDose(for: $0, status: statusCache[$0.id] ?? .none)
            }
            let prnMeds = store.medications.filter { $0.isAsNeeded == true }

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
                        focusHeroCard(
                            schedules: schedules,
                            statusCache: statusCache,
                            takenCount: takenCount,
                            totalCount: totalCount,
                            prnCount: prnMeds.count
                        )

                        sevenDayRhythmCard(
                            scheduledMedicationCount: store.medications.filter { $0.isAsNeeded != true }.count,
                            setupIssueCount: firstWeekSetupIssueCount,
                            checkInDays: sevenDayCheckInCount
                        )

                        if totalCount > 0 {
                            progressOverviewCard(
                                adherence: adherence,
                                taken: takenCount,
                                total: totalCount,
                                actionableCount: actionableSchedules.count,
                                overdueCount: overdueQueue.count + (actionableSchedules.contains {
                                    if case .overdue = statusCache[$0.id] ?? .none { return true }
                                    return false
                                } ? 1 : 0)
                            )
                        }

                        if !overdueQueue.isEmpty {
                            groupedScheduleCard(
                                title: NSLocalizedString("Still Overdue", comment: ""),
                                subtitle: NSLocalizedString("Clear these right after the current dose.", comment: ""),
                                items: overdueQueue,
                                statusCache: statusCache
                            )
                        }

                        if !readyQueue.isEmpty {
                            groupedScheduleCard(
                                title: NSLocalizedString("Up Next", comment: ""),
                                subtitle: NSLocalizedString("More doses are ready once you clear the current task.", comment: ""),
                                items: readyQueue,
                                statusCache: statusCache
                            )
                        }

                        if !laterSchedules.isEmpty {
                            groupedScheduleCard(
                                title: NSLocalizedString("Later Today", comment: ""),
                                subtitle: NSLocalizedString("Upcoming doses that are already on your schedule.", comment: ""),
                                items: laterSchedules,
                                statusCache: statusCache
                            )
                        }

                        if !prnMeds.isEmpty {
                            prnCard(medications: prnMeds)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 6)
                .padding(.bottom, 24)
            }
            .sheet(isPresented: $showAddMedication) {
                AddMedicationView { med in
                    store.addMedication(med)
                    NotificationManager.shared.syncAll(medications: store.medications, intakeLogs: store.intakeLogs)
                    NotificationManager.shared.updateBadge(store: store)
                }
            }
            .refreshable {
                let now = Date()
                NotificationManager.shared.syncAll(medications: store.medications, intakeLogs: store.intakeLogs, now: now)
                NotificationManager.shared.updateBadge(store: store)
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
    private var firstWeekSetupIssueCount: Int {
        store.medications.filter {
            $0.isAsNeeded != true && (!$0.remindersEnabled || $0.timesOfDay.isEmpty)
        }.count
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
                    let id = String(format: "%@_%02d:%02d", med.id.uuidString, h, m)
                    items.append(MedSchedule(id: id, med: med, time: date))
                }
            }
        }
        return items.sorted { $0.time < $1.time }
    }

    @ViewBuilder
    private func focusHeroCard(
        schedules: [MedSchedule],
        statusCache: [String: TodayMedStatus],
        takenCount: Int,
        totalCount: Int,
        prnCount: Int
    ) -> some View {
        let nextActionableItem = schedules.first { item in
            canLogDose(for: item, status: statusCache[item.id] ?? .none)
        }

        if let item = nextActionableItem {
            let status = statusCache[item.id] ?? .none
            TintedCard(tint: heroTint(for: status)) {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(alignment: .top, spacing: 10) {
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

                    HStack(spacing: 12) {
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

                        summaryPill(
                            value: "\(takenCount)/\(max(totalCount, 1))",
                            label: NSLocalizedString("Done", comment: "")
                        )
                    }
                }
            }
        } else if let upcoming = schedules.first(where: { !isFinalStatus(statusCache[$0.id] ?? .none) }) {
            Card {
                VStack(alignment: .leading, spacing: 12) {
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
                }
            }
        } else if prnCount > 0 {
            Card {
                VStack(alignment: .leading, spacing: 12) {
                    Text(NSLocalizedString("No Scheduled Doses", comment: ""))
                        .appFont(.caption)
                        .foregroundStyle(.secondary)
                    Text(NSLocalizedString("Today is PRN only", comment: ""))
                        .appFont(.title)
                        .fontWeight(.bold)
                    Text(NSLocalizedString("You do not have fixed doses waiting right now. Log as-needed medications below only when you actually take them.", comment: ""))
                        .appFont(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        } else {
            TintedCard(tint: .green) {
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
            }
        }
    }

    private func progressOverviewCard(
        adherence: Double,
        taken: Int,
        total: Int,
        actionableCount: Int,
        overdueCount: Int
    ) -> some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                Text(NSLocalizedString("Today's Snapshot", comment: ""))
                    .appFont(.headline)
                HStack(spacing: 8) {
                    overviewMetric(
                        value: "\(Int(adherence * 100))%",
                        label: NSLocalizedString("Progress", comment: ""),
                        tint: .green
                    )
                    overviewMetric(
                        value: "\(max(total - taken, 0))",
                        label: NSLocalizedString("Remaining", comment: ""),
                        tint: actionableCount > 0 ? .orange : .secondary
                    )
                    overviewMetric(
                        value: "\(actionableCount)",
                        label: overdueCount > 0 ? NSLocalizedString("Overdue", comment: "") : NSLocalizedString("Actionable", comment: ""),
                        tint: overdueCount > 0 ? .red : actionableCount > 0 ? .orange : .secondary
                    )
                }
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
                    Text("\(min(checkInDays, 7))/7")
                        .appFont(.label)
                        .fontWeight(.semibold)
                        .monospacedDigit()
                        .foregroundStyle(tint)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(
                            Capsule(style: .continuous)
                                .fill(tint.opacity(0.10))
                        )
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
        return Card {
            groupedScheduleCardContent(
                title: title,
                subtitle: subtitle,
                items: items,
                statusCache: statusCache,
                emphasized: tint != nil,
                accentTint: tint
            )
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
        VStack(alignment: .leading, spacing: emphasized ? 12 : 14) {
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

            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                medRow(item: item, status: statusCache[item.id] ?? .none, emphasizeUrgency: emphasized)
                if index < items.count - 1 {
                    Divider().opacity(emphasized ? 0.55 : 1)
                }
            }
        }
    }

    private func prnCard(medications: [Medication]) -> some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                Text(NSLocalizedString("As Needed", comment: ""))
                    .appFont(.headline)

                ForEach(Array(medications.enumerated()), id: \.element.id) { index, med in
                    prnMedRow(med: med)
                    if index < medications.count - 1 {
                        Divider()
                    }
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

    private func overviewMetric(value: String, label: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(value)
                .font(.system(size: 24, weight: .bold, design: .rounded))
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

    private func summaryPill(value: String, label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .appFont(.headline)
                .fontWeight(.semibold)
            Text(label)
                .appFont(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(.ultraThinMaterial)
        )
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
                    .strikethrough(isFinalStatus(status), color: .secondary)
                    .foregroundStyle(isFinalStatus(status) ? .secondary : .primary)
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
                    store.upsertIntake(
                        medicationID: med.id,
                        status: .taken,
                        scheduleTime: comps,
                        scheduledDate: now,
                        scheduleKeyOverride: "prn_\(now.timeIntervalSince1970)"
                    )
                    store.decrementPills(for: med.id)
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

    private func isFinalStatus(_ status: TodayMedStatus) -> Bool {
        switch status {
        case .taken, .skipped: return true
        default: return false
        }
    }

    private func commitTaken(note: String?) {
        guard let item = pendingNoteItem else { return }
        let comps = Calendar.current.dateComponents([.hour, .minute], from: item.time)
        store.upsertIntake(
            medicationID: item.med.id,
            status: .taken,
            scheduleTime: comps,
            scheduledDate: item.time,
            note: note
        )
        store.decrementPills(for: item.med.id)
        NotificationManager.shared.suppressToday(for: item.med.id, timeComponents: comps)
        NotificationManager.shared.cancelDoseNotifications(for: item.med.id, timeComponents: comps)
        NotificationManager.shared.syncAll(medications: store.medications, intakeLogs: store.intakeLogs)
        NotificationManager.shared.updateBadge(store: store)
        Haptics.success()
        takenMedName = item.med.name
        withAnimation(.easeInOut(duration: 0.25)) { showTakenConfirmation = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.3) {
            withAnimation(.easeInOut(duration: 0.3)) { showTakenConfirmation = false }
        }
        pendingNoteItem = nil
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
        guard !isFinalStatus(status) else { return false }
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
