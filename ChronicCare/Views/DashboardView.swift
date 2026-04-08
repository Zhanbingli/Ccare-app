import SwiftUI

struct DashboardView: View {
    @EnvironmentObject var store: DataStore
    @State private var showAddMeasurement = false
    @State private var showTakenConfirmation = false
    @State private var takenMedName: String = ""
    @State private var showNoteInput = false
    @State private var pendingNoteItem: MedSchedule?
    @State private var intakeNote: String = ""
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

            List {
                // MARK: - Today summary row
                Section {
                    todaySummaryRow(adherence: adherence, taken: takenCount, total: totalCount)
                }
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 4, trailing: 16))

                // MARK: - Next Dose Hero Card
                if !schedules.isEmpty {
                    Section {
                        nextDoseCard(schedules: schedules, statusCache: statusCache, takenCount: takenCount, totalCount: totalCount)
                    }
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                }

                // MARK: - Medication checklist
                if schedules.isEmpty {
                    Section {
                        HStack {
                            Spacer()
                            VStack(spacing: 8) {
                                Image(systemName: "pill.fill")
                                    .font(.system(size: 28))
                                    .foregroundStyle(.secondary)
                                Text(NSLocalizedString("No scheduled medications", comment: ""))
                                    .appFont(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                        }
                        .padding(.vertical, 20)
                    }
                    .listRowSeparator(.hidden)
                } else {
                    Section {
                        ForEach(schedules) { item in
                            medRow(item: item, status: statusCache[item.id] ?? .none)
                        }
                    }
                    .listRowSeparator(.visible)
                    .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                }

                // MARK: - As-Needed (PRN) Medications
                let prnMeds = store.medications.filter { $0.isAsNeeded == true }
                if !prnMeds.isEmpty {
                    Section {
                        ForEach(prnMeds) { med in
                            prnMedRow(med: med)
                        }
                    } header: {
                        Text(NSLocalizedString("As Needed", comment: ""))
                    }
                    .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                }

            }
            .listStyle(.insetGrouped)
            .refreshable {
                let meds = store.medications.filter { $0.remindersEnabled }
                let now = Date()
                NotificationManager.shared.cleanOrphanedRequests(validMedicationIDs: Set(meds.map { $0.id }))
                meds.forEach { NotificationManager.shared.schedule(for: $0, intakeLogs: store.intakeLogs, now: now) }
                NotificationManager.shared.checkRefillReminders(medications: store.medications)
                store.objectWillChange.send()
            }
            .navigationTitle(NSLocalizedString("Today", comment: ""))
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showAddMeasurement = true } label: {
                        Image(systemName: "waveform.path.ecg")
                    }
                }
            }
            .onReceive(refreshTimer) { _ in tick.toggle() }
            .sheet(isPresented: $showAddMeasurement) {
                AddMeasurementView { m in
                    store.addMeasurement(m)
                    Haptics.success()
                }
                .presentationDetents([.medium, .large])
            }
            .alert(NSLocalizedString("Add a Note?", comment: ""), isPresented: $showNoteInput) {
                TextField(NSLocalizedString("e.g., felt dizzy, took with food", comment: ""), text: $intakeNote)
                Button(NSLocalizedString("Save with Note", comment: "")) {
                    commitTaken(note: intakeNote.isEmpty ? nil : intakeNote)
                }
                Button(NSLocalizedString("No Note", comment: ""), role: .cancel) {
                    commitTaken(note: nil)
                }
            } message: {
                Text(NSLocalizedString("Optional: add context like side effects or timing.", comment: ""))
            }
            // Rule 1: Duplicate taken confirmation
            .alert(NSLocalizedString("Already Taken", comment: ""), isPresented: $showDuplicateAlert) {
                Button(NSLocalizedString("Take Again", comment: ""), role: .destructive) {
                    intakeNote = ""
                    showNoteInput = true
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

    // MARK: - Today Summary
    private func todaySummaryRow(adherence: Double, taken: Int, total: Int) -> some View {
        HStack(spacing: 16) {
            // Circular progress
            ZStack {
                Circle()
                    .stroke(Color.primary.opacity(0.08), lineWidth: 5)
                Circle()
                    .trim(from: 0, to: CGFloat(min(max(adherence, 0), 1)))
                    .stroke(adherence >= 1.0 ? Color.green : Color.accentColor, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.easeInOut(duration: 0.4), value: adherence)
                Text(String(format: "%d%%", Int(adherence * 100)))
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(adherence >= 1.0 ? .green : .primary)
            }
            .frame(width: 48, height: 48)

            VStack(alignment: .leading, spacing: 2) {
                if adherence >= 1.0 {
                    Text(NSLocalizedString("All done today!", comment: ""))
                        .appFont(.headline)
                        .foregroundStyle(.green)
                } else {
                    Text(String(format: NSLocalizedString("%lld of %lld taken", comment: ""), taken, total))
                        .appFont(.headline)
                }
                if total - taken > 0 {
                    Text(String(format: NSLocalizedString("%lld remaining", comment: ""), total - taken))
                        .appFont(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
        }
    }

    // MARK: - Medication Row (Things-style: tap circle = take)
    @ViewBuilder
    private func medRow(item: MedSchedule, status: TodayMedStatus) -> some View {
        HStack(alignment: .center, spacing: 12) {
            // Tappable circle — primary action
            Button {
                if canLogDose(for: item, status: status) {
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
                        intakeNote = ""
                        showNoteInput = true
                    }
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

            // Minimal right indicator — only for non-default states
            switch status {
            case .dueSoon:
                Text(NSLocalizedString("Due now", comment: ""))
                    .appFont(.caption).fontWeight(.medium).foregroundStyle(.orange)
            case .overdue:
                Text(NSLocalizedString("Overdue", comment: ""))
                    .appFont(.caption).fontWeight(.medium).foregroundStyle(.red)
            case .snoozed:
                Button {
                    let comps = Calendar.current.dateComponents([.hour, .minute], from: item.time)
                    pendingNoteItem = item
                    intakeNote = ""
                    showNoteInput = true
                } label: {
                    Text(NSLocalizedString("Take", comment: ""))
                        .appFont(.caption).fontWeight(.medium)
                }
                .buttonStyle(.bordered)
                .tint(.green)
                .controlSize(.mini)
            default:
                EmptyView()
            }
        }
        .contentShape(Rectangle())
    }

    private func prnMedRow(med: Medication) -> some View {
        let cal = Calendar.current
        let dayStart = cal.startOfDay(for: Date())
        let dayEnd = cal.date(byAdding: .day, value: 1, to: dayStart)!
        let todayCount = store.intakeLogs.filter {
            $0.medicationID == med.id && $0.date >= dayStart && $0.date < dayEnd && $0.status == .taken
        }.count

        return HStack(alignment: .center, spacing: 12) {
            // Tappable circle — tap to log
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
                Image(systemName: "plus.circle")
                    .font(.system(size: 24, weight: .regular))
                    .foregroundStyle(.blue)
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 2) {
                Text(med.name).appFont(.body)
                Text(med.dose).appFont(.caption).foregroundStyle(.secondary)
            }

            Spacer(minLength: 4)

            if todayCount > 0 {
                Text(String(format: NSLocalizedString("Taken %lld×", comment: ""), todayCount))
                    .appFont(.caption).foregroundStyle(.green)
            }
        }
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private func nextDoseCard(schedules: [MedSchedule], statusCache: [String: TodayMedStatus], takenCount: Int = 0, totalCount: Int = 0) -> some View {
        // Find first actionable dose (upcoming or due now)
        let nextActionableItem = schedules.first { item in
            let s = statusCache[item.id] ?? .none
            return canLogDose(for: item, status: s)
        }

        if let item = nextActionableItem {
            let isDue: Bool = {
                if case .dueSoon = statusCache[item.id] ?? .none { return true }
                if case .overdue = statusCache[item.id] ?? .none { return true }
                return false
            }()
            VStack(spacing: 12) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(NSLocalizedString("Next Dose", comment: ""))
                            .appFont(.caption)
                            .foregroundStyle(.secondary)
                        Text(item.med.name)
                            .appFont(.headline)
                        HStack(spacing: 4) {
                            Text(item.med.dose).appFont(.subheadline).foregroundStyle(.secondary)
                            Text("·").foregroundStyle(.tertiary)
                            Text(item.time, style: .time).appFont(.subheadline).foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    if isDue {
                        Text(NSLocalizedString("Due now", comment: ""))
                            .appFont(.caption)
                            .fontWeight(.medium)
                            .foregroundStyle(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Capsule().fill(.orange))
                    }
                }
                Button {
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
                        intakeNote = ""
                        showNoteInput = true
                    }
                } label: {
                    Label(NSLocalizedString("Take Now", comment: ""), systemImage: "checkmark.circle.fill")
                        .frame(maxWidth: .infinity)
                        .appFont(.headline)
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)
                .controlSize(.large)
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color(.secondarySystemGroupedBackground))
            )
        } else if let upcoming = schedules.first(where: { !isFinalStatus(statusCache[$0.id] ?? .none) }) {
            VStack(spacing: 8) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(NSLocalizedString("Next Dose", comment: ""))
                            .appFont(.caption)
                            .foregroundStyle(.secondary)
                        Text(upcoming.med.name)
                            .appFont(.headline)
                        HStack(spacing: 4) {
                            Text(upcoming.med.dose).appFont(.subheadline).foregroundStyle(.secondary)
                            Text("·").foregroundStyle(.tertiary)
                            Text(upcoming.time, style: .time).appFont(.subheadline).foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                }
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color(.secondarySystemGroupedBackground))
            )
        } else if takenCount == totalCount && totalCount > 0 {
            // All caught up
            HStack(spacing: 10) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 28))
                    .foregroundStyle(.green)
                VStack(alignment: .leading, spacing: 2) {
                    Text(NSLocalizedString("All caught up!", comment: ""))
                        .appFont(.headline)
                        .foregroundStyle(.green)
                    Text(NSLocalizedString("No upcoming doses", comment: ""))
                        .appFont(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.green.opacity(0.08))
            )
        }
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
        NotificationManager.shared.schedule(for: item.med, intakeLogs: store.intakeLogs)
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
