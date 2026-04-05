import SwiftUI

struct DashboardView: View {
    @EnvironmentObject var store: DataStore
    @State private var showAddMeasurement = false
    @State private var showMedManager = false
    @State private var showTrendsPeek = false
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
            ScrollView {
                let schedules = todaySchedules()
                let statusLookup = latestTodayLogMap()
                let statusCache = Dictionary(uniqueKeysWithValues: schedules.map { item in
                    (item.id, status(for: item.med, at: item.time, lookup: statusLookup))
                })
                let takenCount = statusCache.values.filter { if case .taken = $0 { return true } else { return false } }.count
                let totalCount = schedules.count
                let adherence = totalCount > 0 ? Double(takenCount) / Double(totalCount) : 0

                VStack(spacing: 24) {
                    heroSection(next: nextMedication(), adherence: adherence, taken: takenCount, total: totalCount)
                        .padding(.horizontal)

                    sectionHeader(NSLocalizedString("Today's Medications", comment: ""), systemImage: "pills.fill")
                    medsSection(items: schedules, statusCache: statusCache)

                    sectionHeader(NSLocalizedString("Health Data", comment: ""), systemImage: "heart.text.square.fill")
                    measurementsAndTrendsSection

                    // Insights at the bottom — useful but not the primary focus
                    let insights = MedicationInsightsEngine.generateInsights(
                        medications: store.medications,
                        intakeLogs: store.intakeLogs,
                        store: store
                    )
                    if !insights.isEmpty {
                        insightsSection(insights: insights)
                    }
                }
                .padding(.vertical, 24)
            }
            .navigationTitle("Dashboard")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        shareText = buildTodayStatusSummary()
                        showShareSheet = true
                    } label: {
                        Image(systemName: "square.and.arrow.up")
                            .font(.title3)
                    }
                    .accessibilityLabel(NSLocalizedString("Share today's status", comment: ""))
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button {
                            showAddMeasurement = true
                        } label: {
                            Label("Log Measurement", systemImage: "waveform.path.ecg")
                        }
                        Button {
                            showTrendsPeek = true
                        } label: {
                            Label("View Trends", systemImage: "chart.line.uptrend.xyaxis")
                        }
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.title3)
                    }
                }
            }
            .sheet(isPresented: $showAddMeasurement) {
                AddMeasurementView { m in
                    store.addMeasurement(m)
                    Haptics.success()
                }
                .presentationDetents([.medium, .large])
            }
            .sheet(isPresented: $showMedManager) {
                NavigationStack {
                    MedicationsView()
                        .environmentObject(store)
                        .navigationTitle(NSLocalizedString("Medications", comment: ""))
                        .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { showMedManager = false } } }
                }
            }
            .sheet(isPresented: $showTrendsPeek) {
                NavigationStack {
                    EnhancedTrendsView()
                        .environmentObject(store)
                        .navigationTitle(NSLocalizedString("Trends", comment: ""))
                        .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { showTrendsPeek = false } } }
                }
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

    private func nextMedication() -> (Medication, Date)? {
        let cal = Calendar.current
        let now = Date()
        var pairs: [(Medication, Date)] = []
        for med in store.medications where med.remindersEnabled {
            for t in med.timesOfDay {
                guard let h = t.hour, let m = t.minute else { continue }
                let today = cal.date(bySettingHour: h, minute: m, second: 0, of: now)!
                let date = today < now ? cal.date(byAdding: .day, value: 1, to: today)! : today
                pairs.append((med, date))
            }
        }
        return pairs.sorted(by: { $0.1 < $1.1 }).first
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

    private func recentMeasurements(limit: Int = 5) -> [Measurement] {
        Array(store.measurements.prefix(limit))
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

    @ViewBuilder
    private func heroSection(next: (Medication, Date)?, adherence: Double, taken: Int, total: Int) -> some View {
        TintedCard(tint: .indigo) {
            HStack(alignment: .top, spacing: 20) {
                VStack(alignment: .leading, spacing: 10) {
                    Text(NSLocalizedString("Today", comment: "")).appFont(.caption).foregroundStyle(.secondary)
                    if let (med, date) = next {
                        Text(med.name).appFont(.title).foregroundStyle(.primary)
                        Text(date, style: .time).appFont(.subheadline).foregroundStyle(.secondary)
                        Text(med.dose).appFont(.caption).foregroundStyle(.secondary)
                    } else {
                        Text(NSLocalizedString("No scheduled medications", comment: "")).appFont(.subheadline).foregroundStyle(.secondary)
                    }
                    if total > 0 {
                        Text(String(format: NSLocalizedString("Taken %lld/%lld", comment: ""), taken, total))
                            .appFont(.footnote)
                            .foregroundStyle(.primary)
                    }
                }
                Spacer(minLength: 12)
                NavigationLink {
                    AdherenceCalendarView()
                } label: {
                    VStack(spacing: 10) {
                        ProgressRing(value: adherence)
                            .frame(width: 54, height: 54)
                        Text(String(format: "%d%%", Int(adherence * 100)))
                            .appFont(.caption)
                            .foregroundStyle(.white.opacity(0.95))
                        Text(String(localized: "Adherence"))
                            .appFont(.footnote)
                            .foregroundStyle(.white.opacity(0.8))
                    }
                }
            }
        }
        .shadow(color: Color.indigo.opacity(0.12), radius: 10, x: 0, y: 6)
    }


    @ViewBuilder
    private func medsSection(items: [MedSchedule], statusCache: [String: TodayMedStatus]) -> some View {
        Card {
            if items.isEmpty {
                EmptyStateView(systemImage: "bell.slash", title: "No scheduled medications")
            } else {
                VStack(alignment: .leading, spacing: 16) {
                    ForEach(items) { item in
                        let statusBase = statusCache[item.id] ?? .none
                        let status: TodayMedStatus = {
                            switch statusBase {
                            case .none:
                                let now = Date()
                                let graceMin = Double(graceMinutes)
                                if now > item.time.addingTimeInterval(graceMin * 60) {
                                    return .overdue
                                } else if now > item.time {
                                    return .dueSoon
                                } else { return statusBase }
                            case .snoozed:
                                return statusBase
                            default:
                                return statusBase
                            }
                        }()
                        VStack(alignment: .leading, spacing: 10) {
                            // Top row: icon + name + time + status badge
                            HStack(alignment: .center, spacing: 10) {
                                statusDot(for: status)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.med.name).appFont(.headline)
                                    HStack(spacing: 6) {
                                        Text(item.med.dose).appFont(.caption).foregroundStyle(.secondary)
                                        Text("  ")
                                        Text(item.time, style: .time).appFont(.caption).foregroundStyle(.secondary)
                                    }
                                }
                                Spacer(minLength: 4)
                                statusLabel(for: status)
                            }
                            // Action buttons row (full width, only for actionable states)
                            medsActionButtons(for: item, status: status)
                        }
                        .padding(.vertical, 6)
                        if item.id != items.last?.id { Divider() }
                    }
                }
            }
        }
        .padding(.horizontal)
    }

    private var measurementsAndTrendsSection: some View {
        VStack(spacing: 12) {
            Card {
                if store.measurements.isEmpty {
                    EmptyStateView(systemImage: "heart.text.square", title: "No measurements yet", subtitle: "Add your first measurement", actionTitle: "Add") {
                        showAddMeasurement = true
                    }
                } else {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text(NSLocalizedString("Recent Measurements", comment: "")).appFont(.headline)
                            Spacer()
                            Button { showTrendsPeek = true } label: {
                                HStack(spacing: 4) {
                                    Text("View Trends").appFont(.caption)
                                    Image(systemName: "chart.line.uptrend.xyaxis")
                                }
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }
                        Divider()
                        ForEach(recentMeasurements(limit: 4)) { m in
                            HStack(spacing: 10) {
                                Circle().fill(m.cardTint).frame(width: 8, height: 8)
                                Text(m.type.rawValue).appFont(.subheadline)
                                Spacer()
                                if m.type == .bloodPressure, let dia = m.diastolic {
                                    Text("\(Int(m.value))/\(Int(dia)) \(m.type.unit)")
                                        .appFont(.label)
                                        .foregroundStyle(m.valueForeground)
                                } else if m.type == .bloodGlucose {
                                    let v = UnitPreferences.mgdlToPreferred(m.value)
                                    let unit = UnitPreferences.glucoseUnit.rawValue
                                    let formatted = UnitPreferences.glucoseUnit == .mgdL ? String(format: "%.0f", v) : String(format: "%.1f", v)
                                    Text("\(formatted) \(unit)")
                                        .appFont(.label)
                                        .foregroundStyle(m.valueForeground)
                                } else {
                                    Text("\(String(format: "%.1f", m.value)) \(m.type.unit)")
                                        .appFont(.label)
                                        .foregroundStyle(m.valueForeground)
                                }
                            }
                            .foregroundStyle(.primary)
                            .padding(.vertical, 4)
                            if m.id != recentMeasurements(limit: 4).last?.id {
                                Divider()
                            }
                        }
                    }
                    .id(store.measurements.count)
                    .animation(.easeInOut(duration: 0.2), value: store.measurements.count)
                }
            }
        }
        .padding(.horizontal)
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
            HStack(spacing: 10) {
                Button {
                    pendingNoteItem = item
                    intakeNote = ""
                    showNoteInput = true
                } label: {
                    Label(NSLocalizedString("Taken", comment: ""), systemImage: "checkmark.circle.fill")
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
                    Label(NSLocalizedString("Later", comment: ""), systemImage: "zzz")
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
                    Label(NSLocalizedString("Skip", comment: ""), systemImage: "xmark.circle")
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)
            }
        }
    }

    @ViewBuilder
    private func insightsSection(insights: [MedicationInsight]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader(NSLocalizedString("Smart Insights", comment: ""), systemImage: "lightbulb.fill")

            ForEach(insights.prefix(3)) { insight in
                Card {
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: iconForInsight(insight.type))
                            .font(.system(size: 20))
                            .foregroundStyle(colorForInsight(insight.type))

                        VStack(alignment: .leading, spacing: 8) {
                            Text(insight.message)
                                .font(.system(size: 14, weight: .regular))
                                .foregroundStyle(.primary)
                                .fixedSize(horizontal: false, vertical: true)

                            if let actionTitle = insight.actionTitle {
                                Button(actionTitle) {
                                    if let action = insight.action {
                                        action()
                                    }
                                }
                                .font(.system(size: 13, weight: .medium))
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                            }
                        }
                    }
                    .padding(12)
                }
            }
        }
        .padding(.horizontal)
    }

    private func iconForInsight(_ type: MedicationInsight.InsightType) -> String {
        switch type {
        case .skippedFrequently:
            return "exclamationmark.triangle.fill"
        case .timeAdjustmentSuggestion:
            return "clock.arrow.circlepath"
        case .adherenceImprovement:
            return "chart.line.uptrend.xyaxis"
        case .effectivenessLow:
            return "waveform.path.ecg"
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
        case .effectivenessLow:
            return .red
        case .reminderNotWorking:
            return .gray
        }
    }

}

#Preview {
    DashboardView().environmentObject(DataStore())
}

private struct ProgressRing: View {
    var value: Double
    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.white.opacity(0.2), style: StrokeStyle(lineWidth: 6, lineCap: .round))
            Circle()
                .trim(from: 0, to: CGFloat(min(max(value, 0), 1)))
                .stroke(
                    AngularGradient(
                        colors: [.white, .white.opacity(0.6)],
                        center: .center
                    ),
                    style: StrokeStyle(lineWidth: 6, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
            Circle()
                .fill(Color.white.opacity(0.15))
                .frame(width: 32, height: 32)
        }
        .contentShape(Circle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(String(localized: "Adherence")))
        .accessibilityValue(Text("\(Int(value * 100))%"))
    }
}
