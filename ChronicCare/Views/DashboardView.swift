import SwiftUI

struct DashboardView: View {
    @EnvironmentObject var store: DataStore
    @State private var showAddMeasurement = false

    private struct MedSchedule: Identifiable {
        let id: UUID
        let med: Medication
        let time: Date
    }

    private enum TodayMedStatus {
        case none
        case taken(Date)
        case skipped(Date)
        case snoozed(Date)
    }

    private func nextMedication() -> (Medication, Date)? {
        let cal = Calendar.current
        let now = Date()
        return store.medications
            .compactMap { med -> (Medication, Date)? in
                guard let h = med.timeOfDay.hour, let m = med.timeOfDay.minute else { return nil }
                let today = cal.date(bySettingHour: h, minute: m, second: 0, of: now)!
                let date = today < now ? cal.date(byAdding: .day, value: 1, to: today)! : today
                return (med, date)
            }
            .sorted(by: { $0.1 < $1.1 })
            .first
    }

    private func todaySchedules() -> [MedSchedule] {
        let cal = Calendar.current
        let now = Date()
        return store.medications
            .filter { $0.remindersEnabled }
            .compactMap { med -> MedSchedule? in
                guard let h = med.timeOfDay.hour, let m = med.timeOfDay.minute else { return nil }
                let date = cal.date(bySettingHour: h, minute: m, second: 0, of: now)!
                return MedSchedule(id: med.id, med: med, time: date)
            }
            .sorted { $0.time < $1.time }
    }

    private func todayStatus(_ medID: UUID) -> TodayMedStatus {
        let cal = Calendar.current
        let start = cal.startOfDay(for: Date())
        let logs = store.intakeLogs
            .filter { $0.medicationID == medID && $0.date >= start }
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
                                if case .taken = todayStatus($0.id) { return true }
                                return false
                            }.count
                            let totalCount = items.count
                            let adherence = totalCount > 0 ? Int(Double(takenCount) / Double(totalCount) * 100) : 0
                            HStack {
                                Label("Taken \(takenCount)/\(totalCount)", systemImage: "checkmark")
                                Spacer()
                                Text("Adherence \(adherence)%").font(.subheadline).foregroundStyle(.secondary)
                            }
                            .padding(.bottom, 4)

                            VStack(alignment: .leading, spacing: 10) {
                                ForEach(items) { item in
                                    let status = todayStatus(item.id)
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
                                        default:
                                            HStack(spacing: 8) {
                                                Button {
                                                    store.logIntake(medicationID: item.id, status: .taken)
                                                    Haptics.success()
                                                } label: {
                                                    Label(NSLocalizedString("Taken", comment: ""), systemImage: "checkmark.circle.fill")
                                                }
                                                .buttonStyle(.borderedProminent)
                                                .tint(.green)
                                                .controlSize(.small)

                                                Menu {
                                                    Button {
                                                        store.logIntake(medicationID: item.id, status: .snoozed)
                                                        NotificationManager.shared.scheduleSnooze(for: item.med, minutes: 10)
                                                        Haptics.impact(.light)
                                                    } label: {
                                                        Label(NSLocalizedString("Snooze 10m", comment: ""), systemImage: "zzz")
                                                    }
                                                    Button(role: .destructive) {
                                                        store.logIntake(medicationID: item.id, status: .skipped)
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
            }
            .padding(.horizontal)
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
