import SwiftUI

struct DashboardView: View {
    @EnvironmentObject var store: DataStore
    @State private var showAddMeasurement = false
    @State private var showMedManager = false
    @State private var showTrendsPeek = false
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

                VStack(spacing: 20) {
                    heroSection(next: nextMedication(), adherence: adherence, taken: takenCount, total: totalCount)
                        .padding(.horizontal)

                    // Smart insights
                    let insights = MedicationInsightsEngine.generateInsights(
                        medications: store.medications,
                        intakeLogs: store.intakeLogs,
                        store: store
                    )
                    if !insights.isEmpty {
                        insightsSection(insights: insights)
                    }

                    sectionHeader(NSLocalizedString("Today's Medications", comment: ""), systemImage: "pills.fill")
                    medsSection(items: schedules, statusCache: statusCache)

                    sectionHeader(NSLocalizedString("Health Data", comment: ""), systemImage: "heart.text.square.fill")
                    measurementsAndTrendsSection
                }
                .padding(.vertical, 24)
            }
            .navigationTitle("Dashboard")
            .toolbar {
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
        }
    }
}

private extension DashboardView {
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
        .shadow(color: Color.indigo.opacity(0.12), radius: 10, x: 0, y: 6)
    }


    @ViewBuilder
    private func medsSection(items: [MedSchedule], statusCache: [String: TodayMedStatus]) -> some View {
        Card {
            if items.isEmpty {
                EmptyStateView(systemImage: "bell.slash", title: "No scheduled medications")
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(items) { item in
                        let statusBase = statusCache[item.id] ?? .none
                        let status: TodayMedStatus = {
                            switch statusBase {
                            case .none, .snoozed:
                                let graceMin = Double(graceMinutes)
                                if Date() > item.time.addingTimeInterval(graceMin * 60) {
                                    return .overdue
                                } else { return statusBase }
                            default:
                                return statusBase
                            }
                        }()
                        HStack(alignment: .center, spacing: 12) {
                            Image(systemName: "bell.badge.fill").foregroundStyle(.orange)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(item.med.name).appFont(.headline)
                                HStack(spacing: 8) {
                                    Text(item.med.dose).appFont(.subheadline).foregroundStyle(.secondary)
                                    Text(item.time, style: .time).appFont(.subheadline).foregroundStyle(.secondary)
                                }
                                switch status {
                                case .taken(let when):
                                    (Text(NSLocalizedString("Taken ", comment: "")) + Text(when, style: .relative))
                                        .appFont(.caption)
                                        .foregroundStyle(.secondary)
                                case .skipped(let when):
                                    (Text(NSLocalizedString("Skipped ", comment: "")) + Text(when, style: .relative))
                                        .appFont(.caption)
                                        .foregroundStyle(.secondary)
                                case .snoozed(let when):
                                    (Text(NSLocalizedString("Snoozed ", comment: "")) + Text(when, style: .relative))
                                        .appFont(.caption)
                                        .foregroundStyle(.secondary)
                                case .none:
                                    EmptyView()
                                case .overdue:
                                    Text(NSLocalizedString("Overdue", comment: ""))
                                        .appFont(.caption)
                                        .foregroundStyle(.red)
                                }
                            }
                            Spacer()
                            medsActionButtons(for: item, status: status)
                        }
                        .padding(.vertical, 2)
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

    @ViewBuilder
    private func medsActionButtons(for item: MedSchedule, status: TodayMedStatus) -> some View {
        switch status {
        case .taken:
            Label(NSLocalizedString("Logged", comment: ""), systemImage: "checkmark.circle")
                .foregroundStyle(.green)
                .appFont(.subheadline)
        case .skipped:
            Label(NSLocalizedString("Skipped", comment: ""), systemImage: "xmark.circle")
                .foregroundStyle(.secondary)
                .appFont(.subheadline)
        case .overdue:
            Label(NSLocalizedString("Overdue", comment: ""), systemImage: "exclamationmark.circle")
                .foregroundStyle(.red)
                .appFont(.subheadline)
        default:
            HStack(spacing: 10) {
                Button {
                    let comps = Calendar.current.dateComponents([.hour, .minute], from: item.time)
                    store.upsertIntake(medicationID: item.med.id, status: .taken, scheduleTime: comps)
                    NotificationManager.shared.suppressToday(for: item.med.id, timeComponents: comps)
                    NotificationManager.shared.cancelTodayInstance(for: item.med.id, timeComponents: comps)
                    NotificationManager.shared.schedule(for: item.med)
                    NotificationManager.shared.updateBadge(store: store)
                    Haptics.success()
                } label: {
                    Label(NSLocalizedString("Taken", comment: ""), systemImage: "checkmark.circle.fill")
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)
                .controlSize(.small)

                Menu {
                    Button {
                        let comps = Calendar.current.dateComponents([.hour, .minute], from: item.time)
                        store.upsertIntake(medicationID: item.med.id, status: .snoozed, scheduleTime: comps)
                        NotificationManager.shared.scheduleSnooze(for: item.med, minutes: 10, scheduleTime: comps)
                        NotificationManager.shared.updateBadge(store: store)
                        Haptics.impact(.light)
                    } label: {
                        Label(NSLocalizedString("Snooze 10m", comment: ""), systemImage: "zzz")
                    }
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
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .imageScale(.large)
                        .foregroundStyle(.secondary)
                }
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
