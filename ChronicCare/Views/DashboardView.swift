import SwiftUI

struct DashboardView: View {
    @EnvironmentObject var store: DataStore
    @State private var showAddMeasurement = false
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

    private enum TodayMedStatus {
        case none
        case taken(Date)
        case skipped(Date)
        case snoozed(Date)
        case overdue
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

    private func todayStatus(for med: Medication, at time: Date) -> TodayMedStatus {
        let cal = Calendar.current
        let start = cal.startOfDay(for: Date())
        let comps = cal.dateComponents([.hour, .minute], from: time)
        let key = String(format: "%02d:%02d", comps.hour ?? 0, comps.minute ?? 0)
        let allowNilForSingleTime = med.timesOfDay.count <= 1
        let logs = store.intakeLogs
            .filter {
                $0.medicationID == med.id && $0.date >= start &&
                (($0.scheduleKey == key) || (allowNilForSingleTime && $0.scheduleKey == nil))
            }
            .sorted { $0.date > $1.date }
        guard let last = logs.first else { return .none }
        switch last.status {
        case .taken:  return .taken(last.date)
        case .skipped:return .skipped(last.date)
        case .snoozed:return .snoozed(last.date)
        }
    }

    private func recentMeasurements(limit: Int = 5) -> [Measurement] {
        Array(store.measurements.prefix(limit))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    sectionHeader("Today's Medications", systemImage: "pills.fill")
                    Card {
                        let items = todaySchedules()
                        if items.isEmpty {
                            EmptyStateView(systemImage: "bell.slash", title: "No scheduled medications")
                        } else {
                            // Summary
                            let takenCount = items.filter {
                                if case .taken = todayStatus(for: $0.med, at: $0.time) { return true }
                                return false
                            }.count
                            let totalCount = items.count
                            let adherence = totalCount > 0 ? Int(Double(takenCount) / Double(totalCount) * 100) : 0
                            HStack {
                                let takenText = String(format: NSLocalizedString("Taken %lld/%lld", comment: ""), takenCount, totalCount)
                                Label(takenText, systemImage: "checkmark")
                                Spacer()
                                let adhText = String(format: NSLocalizedString("Adherence %lld%%", comment: ""), adherence)
                                Text(adhText).font(.subheadline).foregroundStyle(.secondary)
                            }
                            .padding(.bottom, 4)

                            VStack(alignment: .leading, spacing: 10) {
                                ForEach(items) { item in
                                    let statusBase = todayStatus(for: item.med, at: item.time)
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
                                            Text(item.med.name).font(.headline)
                                            HStack(spacing: 8) {
                                                Text(item.med.dose).font(.subheadline).foregroundStyle(.secondary)
                                                Text(item.time, style: .time).font(.subheadline).foregroundStyle(.secondary)
                                            }
                                            // Status line
                                            switch status {
                                            case .taken(let when):
                                                (Text(NSLocalizedString("Taken ", comment: "")) + Text(when, style: .relative))
                                                    .font(.caption)
                                                    .foregroundStyle(.secondary)
                                            case .skipped(let when):
                                                (Text(NSLocalizedString("Skipped ", comment: "")) + Text(when, style: .relative))
                                                    .font(.caption)
                                                    .foregroundStyle(.secondary)
                                            case .snoozed(let when):
                                                (Text(NSLocalizedString("Snoozed ", comment: "")) + Text(when, style: .relative))
                                                    .font(.caption)
                                                    .foregroundStyle(.secondary)
                                            case .none:
                                                EmptyView()
                                            case .overdue:
                                                Text(NSLocalizedString("Overdue", comment: ""))
                                                    .font(.caption)
                                                    .foregroundStyle(.red)
                                            }
                                        }
                                        Spacer()
                                        switch status {
                                        case .taken:
                                            Label(NSLocalizedString("Logged", comment: ""), systemImage: "checkmark.circle")
                                                .foregroundStyle(.green)
                                                .font(.subheadline)
                                        case .skipped:
                                            Label(NSLocalizedString("Skipped", comment: ""), systemImage: "xmark.circle")
                                                .foregroundStyle(.secondary)
                                                .font(.subheadline)
                                        case .overdue:
                                            Label(NSLocalizedString("Overdue", comment: ""), systemImage: "exclamationmark.circle")
                                                .foregroundStyle(.red)
                                                .font(.subheadline)
                                        default:
                                            HStack(spacing: 8) {
                                                Button {
                                                    let comps = Calendar.current.dateComponents([.hour, .minute], from: item.time)
                                                    store.upsertIntake(medicationID: item.med.id, status: .taken, scheduleTime: comps)
                                                    NotificationManager.shared.suppressToday(for: item.med.id, timeComponents: comps)
                                                    NotificationManager.shared.cancelTodayInstance(for: item.med.id, timeComponents: comps)
                                                    NotificationManager.shared.scheduleNextInstance(for: item.med, timeComponents: comps)
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
                                                        NotificationManager.shared.scheduleSnooze(for: item.med, minutes: 10)
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
                                                        NotificationManager.shared.scheduleNextInstance(for: item.med, timeComponents: comps)
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
                                    .padding(.vertical, 2)
                                    if item.id != items.last?.id { Divider() }
                                }
                            }
                        }
                    }

                    sectionHeader("Recent Measurements", systemImage: "waveform.path.ecg")
                    Card {
                        if store.measurements.isEmpty {
                            EmptyStateView(systemImage: "heart.text.square", title: "No measurements yet", subtitle: "Add your first measurement", actionTitle: "Add") {
                                showAddMeasurement = true
                            }
                        } else {
                            VStack(alignment: .leading, spacing: 10) {
                                ForEach(recentMeasurements()) { m in
                                    HStack(spacing: 10) {
                                        Circle().fill(m.cardTint).frame(width: 8, height: 8)
                                        Text(m.type.rawValue).font(.subheadline)
                                        Spacer()
                                        if m.type == .bloodPressure, let dia = m.diastolic {
                                            Text("\(Int(m.value))/\(Int(dia)) \(m.type.unit)")
                                                .foregroundStyle(m.valueForeground)
                                        } else if m.type == .bloodGlucose {
                                            let v = UnitPreferences.mgdlToPreferred(m.value)
                                            let unit = UnitPreferences.glucoseUnit.rawValue
                                            let formatted = UnitPreferences.glucoseUnit == .mgdL ? String(format: "%.0f", v) : String(format: "%.1f", v)
                                            Text("\(formatted) \(unit)")
                                                .foregroundStyle(m.valueForeground)
                                        } else {
                                            Text("\(String(format: "%.1f", m.value)) \(m.type.unit)")
                                                .foregroundStyle(m.valueForeground)
                                        }
                                    }
                                    .foregroundStyle(.primary)
                                    .padding(.vertical, 4)
                                    Divider()
                                }
                            }
                            // Force row rebuild when logs change to avoid stale UI in some SwiftUI layouts
                            .id(store.intakeLogs.count)
                            .animation(.easeInOut(duration: 0.2), value: store.intakeLogs.count)
                        }
                    }
                }
                .padding(.vertical)
                .padding(.horizontal)
            }
            .navigationTitle("Dashboard")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showAddMeasurement = true } label: { Image(systemName: "plus") }
                }
            }
            .sheet(isPresented: $showAddMeasurement) {
                AddMeasurementView { m in
                    store.addMeasurement(m)
                    Haptics.success()
                }
                .presentationDetents([.medium, .large])
            }
        }
    }
}

#Preview {
    DashboardView().environmentObject(DataStore())
}
