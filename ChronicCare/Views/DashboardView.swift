import SwiftUI

struct DashboardView: View {
    @EnvironmentObject var store: DataStore
    @State private var showAddMeasurement = false
    @State private var showTakenConfirmation = false
    @State private var takenMedName: String = ""
    @State private var showShareSheet = false
    @State private var shareText: String = ""
    @State private var showNoteInput = false
    @State private var pendingNoteItem: MedSchedule?
    @State private var intakeNote: String = ""
    @AppStorage("units.glucose") private var glucoseUnitRaw: String = GlucoseUnit.mgdL.rawValue
    @AppStorage("prefs.graceMinutes") private var graceMinutes: Int = 30

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
        NavigationStack {
            let schedules = todaySchedules()
            let statusLookup = latestTodayLogMap()
            let statusCache = Dictionary(uniqueKeysWithValues: schedules.map { item in
                (item.id, status(for: item.med, at: item.time, lookup: statusLookup))
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
                            let s = statusCache[item.id] ?? .none
                            let resolvedStatus: TodayMedStatus = {
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
                            medRow(item: item, status: resolvedStatus)
                        }
                    }
                    .listRowSeparator(.visible)
                    .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                }

                // MARK: - Measurement
                Section {
                    if let latest = store.measurements.first {
                        latestMeasurementRow(latest)
                    }

                    Button {
                        showAddMeasurement = true
                    } label: {
                        Label(NSLocalizedString("Log Measurement", comment: ""), systemImage: "plus.circle.fill")
                            .appFont(.subheadline)
                    }
                } header: {
                    Text(NSLocalizedString("Measurements", comment: ""))
                }
                .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))

                // MARK: - Links
                Section {
                    if totalCount > 0 {
                        NavigationLink {
                            AdherenceCalendarView()
                        } label: {
                            Label(NSLocalizedString("Adherence Calendar", comment: ""), systemImage: "calendar")
                                .appFont(.subheadline)
                        }
                    }

                    NavigationLink {
                        EnhancedTrendsView()
                            .environmentObject(store)
                    } label: {
                        Label(NSLocalizedString("View Trends", comment: ""), systemImage: "chart.line.uptrend.xyaxis")
                            .appFont(.subheadline)
                    }

                    Button {
                        shareText = buildTodayStatusSummary()
                        showShareSheet = true
                    } label: {
                        Label(NSLocalizedString("Share today's status", comment: ""), systemImage: "square.and.arrow.up")
                            .appFont(.subheadline)
                    }
                }
                .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))

                // MARK: - Insights (only when noteworthy)
                let insights = MedicationInsightsEngine.generateInsights(
                    medications: store.medications,
                    intakeLogs: store.intakeLogs,
                    store: store
                )
                if !insights.isEmpty {
                    Section {
                        ForEach(insights.prefix(2)) { insight in
                            HStack(alignment: .top, spacing: 10) {
                                Image(systemName: iconForInsight(insight.type))
                                    .font(.system(size: 16))
                                    .foregroundStyle(colorForInsight(insight.type))
                                    .frame(width: 22)
                                Text(insight.message)
                                    .appFont(.caption)
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    } header: {
                        Text(NSLocalizedString("Smart Insights", comment: ""))
                    }
                    .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                }
            }
            .listStyle(.insetGrouped)
            .refreshable {
                let meds = store.medications.filter { $0.remindersEnabled }
                let now = Date()
                NotificationManager.shared.cleanOrphanedRequests(validMedicationIDs: Set(meds.map { $0.id }))
                meds.forEach { NotificationManager.shared.schedule(for: $0, now: now) }
                NotificationManager.shared.checkRefillReminders(medications: store.medications)
                store.objectWillChange.send()
            }
            .navigationTitle(NSLocalizedString("Today", comment: ""))
            .sheet(isPresented: $showAddMeasurement) {
                AddMeasurementView { m in
                    store.addMeasurement(m)
                    Haptics.success()
                }
                .presentationDetents([.medium, .large])
            }
            .sheet(isPresented: $showShareSheet) {
                ShareSheet(activityItems: [shareText])
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
            .overlay {
                if showTakenConfirmation {
                    TakenConfirmationOverlay(medicationName: takenMedName)
                        .transition(.opacity)
                        .zIndex(100)
                }
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
                .font(.system(size: 22, weight: .semibold, design: .rounded))
                .foregroundStyle(.primary)
            Text(NSLocalizedString("Taken!", comment: ""))
                .font(.system(size: 28, weight: .bold, design: .rounded))
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
    func buildTodayStatusSummary() -> String {
        let cal = Calendar.current
        let now = Date()
        let dayStart = cal.startOfDay(for: now)
        let dayEnd = cal.date(byAdding: .day, value: 1, to: dayStart)!
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .long
        dateFormatter.timeStyle = .none

        var lines: [String] = []
        lines.append(String(format: NSLocalizedString("Medication Update — %@", comment: ""), dateFormatter.string(from: now)))
        lines.append("")

        let meds = store.medications.filter { $0.remindersEnabled }
        if meds.isEmpty {
            lines.append(NSLocalizedString("No medications scheduled today.", comment: ""))
        } else {
            let timeFormatter = DateFormatter()
            timeFormatter.timeStyle = .short
            for med in meds {
                for t in med.timesOfDay {
                    guard let h = t.hour, let m = t.minute else { continue }
                    let timeStr = cal.date(bySettingHour: h, minute: m, second: 0, of: now)
                        .map { timeFormatter.string(from: $0) } ?? "\(h):\(m)"
                    let key = String(format: "%02d:%02d", h, m)
                    let log = store.intakeLogs.first { l in
                        l.medicationID == med.id && l.date >= dayStart && l.date < dayEnd && l.scheduleKey == key
                    }
                    let statusStr: String
                    if let log = log {
                        switch log.status {
                        case .taken: statusStr = NSLocalizedString("Taken", comment: "")
                        case .skipped: statusStr = NSLocalizedString("Skipped", comment: "")
                        case .snoozed: statusStr = NSLocalizedString("Snoozed", comment: "")
                        }
                    } else if now > (cal.date(bySettingHour: h, minute: m, second: 0, of: now) ?? now) {
                        statusStr = NSLocalizedString("Missed", comment: "")
                    } else {
                        statusStr = NSLocalizedString("Upcoming", comment: "")
                    }
                    lines.append("\(med.name) \(med.dose) (\(timeStr)) — \(statusStr)")
                }
                if let remaining = med.pillsRemaining {
                    if med.isLowSupply {
                        lines.append(String(format: NSLocalizedString("  ⚠ %lld pills left — refill needed", comment: ""), remaining))
                    }
                }
            }
        }

        lines.append("")
        lines.append(NSLocalizedString("Sent from Ccare", comment: ""))
        return lines.joined(separator: "\n")
    }

    private func todaySchedules() -> [MedSchedule] {
        let cal = Calendar.current
        let now = Date()
        var items: [MedSchedule] = []
        for med in store.medications where med.remindersEnabled {
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
        HStack(spacing: 12) {
            // Progress bar
            VStack(alignment: .leading, spacing: 4) {
                Text(String(format: NSLocalizedString("Taken %lld/%lld", comment: ""), taken, total))
                    .appFont(.subheadline)
                    .foregroundStyle(.primary)
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Color.primary.opacity(0.08))
                            .frame(height: 6)
                        Capsule()
                            .fill(adherence >= 1.0 ? Color.green : Color.accentColor)
                            .frame(width: geo.size.width * CGFloat(min(max(adherence, 0), 1)), height: 6)
                            .animation(.easeInOut(duration: 0.3), value: adherence)
                    }
                }
                .frame(height: 6)
            }

            Text(String(format: "%d%%", Int(adherence * 100)))
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(adherence >= 1.0 ? .green : .primary)
        }
    }

    // MARK: - Medication Row
    @ViewBuilder
    private func medRow(item: MedSchedule, status: TodayMedStatus) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 10) {
                statusDot(for: status)
                    .frame(width: 22)

                VStack(alignment: .leading, spacing: 1) {
                    Text(item.med.name)
                        .appFont(.body)
                        .strikethrough(isFinalStatus(status), color: .secondary)
                        .foregroundStyle(isFinalStatus(status) ? .secondary : .primary)
                    HStack(spacing: 4) {
                        Text(item.med.dose).appFont(.caption).foregroundStyle(.secondary)
                        Text("·").foregroundStyle(.tertiary)
                        Text(item.time, style: .time).appFont(.caption).foregroundStyle(.secondary)
                    }
                }

                Spacer(minLength: 4)
                statusLabel(for: status)
            }

            // Compact action buttons (only for actionable states)
            medsActionButtons(for: item, status: status)
        }
    }

    private func isFinalStatus(_ status: TodayMedStatus) -> Bool {
        switch status {
        case .taken, .skipped: return true
        default: return false
        }
    }

    // MARK: - Latest Measurement Row
    @ViewBuilder
    private func latestMeasurementRow(_ m: Measurement) -> some View {
        HStack(spacing: 10) {
            Circle().fill(m.type.tint).frame(width: 8, height: 8)
            Text(m.type.rawValue)
                .appFont(.subheadline)
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

            Text(m.date, style: .relative)
                .appFont(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func commitTaken(note: String?) {
        guard let item = pendingNoteItem else { return }
        let comps = Calendar.current.dateComponents([.hour, .minute], from: item.time)
        store.upsertIntake(medicationID: item.med.id, status: .taken, scheduleTime: comps, note: note)
        store.decrementPills(for: item.med.id)
        NotificationManager.shared.suppressToday(for: item.med.id, timeComponents: comps)
        NotificationManager.shared.cancelTodayInstance(for: item.med.id, timeComponents: comps)
        NotificationManager.shared.schedule(for: item.med)
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
                .foregroundStyle(.secondary)
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

    @ViewBuilder
    private func statusLabel(for status: TodayMedStatus) -> some View {
        switch status {
        case .taken(let when):
            (Text(NSLocalizedString("Taken ", comment: "")) + Text(when, style: .relative))
                .appFont(.caption)
                .foregroundStyle(.green)
        case .skipped(let when):
            (Text(NSLocalizedString("Skipped ", comment: "")) + Text(when, style: .relative))
                .appFont(.caption)
                .foregroundStyle(.secondary)
        case .snoozed(let when):
            (Text(NSLocalizedString("Snoozed ", comment: "")) + Text(when, style: .relative))
                .appFont(.caption)
                .foregroundStyle(.blue)
        case .dueSoon:
            Text(NSLocalizedString("Due now", comment: ""))
                .appFont(.caption)
                .fontWeight(.medium)
                .foregroundStyle(.orange)
        case .overdue:
            Text(NSLocalizedString("Overdue", comment: ""))
                .appFont(.caption)
                .fontWeight(.medium)
                .foregroundStyle(.red)
        case .none:
            EmptyView()
        }
    }

    @ViewBuilder
    private func medsActionButtons(for item: MedSchedule, status: TodayMedStatus) -> some View {
        switch status {
        case .taken, .skipped:
            EmptyView()
        default:
            HStack(spacing: 8) {
                Button {
                    pendingNoteItem = item
                    intakeNote = ""
                    showNoteInput = true
                } label: {
                    Label(NSLocalizedString("Taken", comment: ""), systemImage: "checkmark")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)
                .controlSize(.regular)

                Button {
                    let comps = Calendar.current.dateComponents([.hour, .minute], from: item.time)
                    store.upsertIntake(medicationID: item.med.id, status: .snoozed, scheduleTime: comps)
                    NotificationManager.shared.scheduleSnooze(for: item.med, minutes: 10, scheduleTime: comps)
                    NotificationManager.shared.updateBadge(store: store)
                    Haptics.impact(.light)
                } label: {
                    Text(NSLocalizedString("Later", comment: ""))
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)

                Button(role: .destructive) {
                    let comps = Calendar.current.dateComponents([.hour, .minute], from: item.time)
                    store.upsertIntake(medicationID: item.med.id, status: .skipped, scheduleTime: comps)
                    NotificationManager.shared.suppressToday(for: item.med.id, timeComponents: comps)
                    NotificationManager.shared.cancelTodayInstance(for: item.med.id, timeComponents: comps)
                    NotificationManager.shared.schedule(for: item.med)
                    NotificationManager.shared.updateBadge(store: store)
                    Haptics.impact(.light)
                } label: {
                    Text(NSLocalizedString("Skip", comment: ""))
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)
            }
        }
    }


    private func iconForInsight(_ type: MedicationInsight.InsightType) -> String {
        switch type {
        case .skippedFrequently:
            return "exclamationmark.triangle.fill"
        case .timeAdjustmentSuggestion:
            return "clock.arrow.circlepath"
        case .adherenceImprovement:
            return "chart.line.uptrend.xyaxis"
        case .reminderNotWorking:
            return "bell.slash.fill"
        }
    }

    private func colorForInsight(_ type: MedicationInsight.InsightType) -> Color {
        switch type {
        case .skippedFrequently:
            return .orange
        case .timeAdjustmentSuggestion:
            return .blue
        case .adherenceImprovement:
            return .purple
        case .reminderNotWorking:
            return .gray
        }
    }

}

#Preview {
    DashboardView().environmentObject(DataStore())
}
