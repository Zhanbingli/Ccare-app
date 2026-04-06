import SwiftUI

struct CaregiversView: View {
    @EnvironmentObject var store: DataStore
    @State private var showAdd = false
    @State private var showShare = false
    @State private var shareText = ""

    var body: some View {
        List {
            if store.caregivers.isEmpty {
                Section {
                    VStack(spacing: 12) {
                        Image(systemName: "person.2.fill")
                            .font(.system(size: 40))
                            .foregroundStyle(.secondary)
                        Text(NSLocalizedString("No caregivers added", comment: ""))
                            .appFont(.headline)
                            .foregroundStyle(.secondary)
                        Text(NSLocalizedString("Add a family member or caregiver to share your medication status.", comment: ""))
                            .appFont(.caption)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 24)
                }
                .listRowBackground(Color.clear)
            } else {
                Section {
                    ForEach(store.caregivers) { cg in
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(cg.name).appFont(.body)
                                if let phone = cg.phone, !phone.isEmpty {
                                    Text(phone).appFont(.caption).foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            if cg.notifyOnMiss {
                                Image(systemName: "bell.fill")
                                    .font(.caption)
                                    .foregroundStyle(.orange)
                            }
                        }
                    }
                    .onDelete { store.removeCaregiver(at: $0) }
                } header: {
                    Text(NSLocalizedString("Caregivers", comment: ""))
                } footer: {
                    Text(NSLocalizedString("Bell icon means they'll be included in missed-dose reminders.", comment: ""))
                }

                Section {
                    Button {
                        shareText = buildCaregiverSummary()
                        showShare = true
                    } label: {
                        Label(NSLocalizedString("Share today's status", comment: ""), systemImage: "square.and.arrow.up")
                    }
                }
            }
        }
        .navigationTitle(NSLocalizedString("Caregivers", comment: ""))
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showAdd = true } label: { Image(systemName: "plus") }
            }
        }
        .sheet(isPresented: $showAdd) {
            AddCaregiverSheet { cg in
                store.addCaregiver(cg)
                Haptics.success()
            }
        }
        .sheet(isPresented: $showShare) {
            ShareSheet(activityItems: [shareText])
        }
    }

    private func buildCaregiverSummary() -> String {
        let cal = Calendar.current
        let now = Date()
        let dayStart = cal.startOfDay(for: now)
        let dayEnd = cal.date(byAdding: .day, value: 1, to: dayStart)!
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .long

        var lines: [String] = []
        lines.append(String(format: NSLocalizedString("Medication Update — %@", comment: ""), dateFormatter.string(from: now)))
        lines.append("")

        let meds = store.medications.filter { $0.remindersEnabled }
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
                } else {
                    statusStr = NSLocalizedString("Upcoming", comment: "")
                }
                lines.append("\(med.name) \(med.dose) (\(timeStr)) — \(statusStr)")
            }
        }
        lines.append("")
        lines.append(NSLocalizedString("Sent from Ccare", comment: ""))
        return lines.joined(separator: "\n")
    }
}

private struct AddCaregiverSheet: View {
    var onSave: (CaregiverContact) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var phone = ""
    @State private var notifyOnMiss = true

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(NSLocalizedString("Name", comment: ""), text: $name)
                    TextField(NSLocalizedString("Phone (optional)", comment: ""), text: $phone)
                        .keyboardType(.phonePad)
                } header: {
                    Text(NSLocalizedString("Caregiver Info", comment: ""))
                }

                Section {
                    Toggle(NSLocalizedString("Remind me to share on missed doses", comment: ""), isOn: $notifyOnMiss)
                } footer: {
                    Text(NSLocalizedString("When you miss medication for 2+ days, we'll remind you to share your status with this person.", comment: ""))
                }
            }
            .navigationTitle(NSLocalizedString("Add Caregiver", comment: ""))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(NSLocalizedString("Cancel", comment: "")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(NSLocalizedString("Save", comment: "")) {
                        onSave(CaregiverContact(name: name, phone: phone.isEmpty ? nil : phone, notifyOnMiss: notifyOnMiss))
                        dismiss()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }
}
