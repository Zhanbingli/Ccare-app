import SwiftUI

struct CaregiversView: View {
    @EnvironmentObject var store: DataStore
    @State private var showAdd = false
    @State private var shareText: String = ""
    @State private var showShare = false

    private var caregiverAlertCount: Int {
        store.caregivers.filter(\.notifyOnMiss).count
    }

    private var missedSupportItems: [(medication: Medication, missedDays: Int)] {
        store.medications.compactMap { medication in
            let missedDays = store.consecutiveMissedDays(for: medication.id)
            guard missedDays >= 2 else { return nil }
            return (medication, missedDays)
        }
    }

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text(NSLocalizedString("Support Network", comment: ""))
                        .appFont(.headline)
                    Text(caregiverSummary)
                        .appFont(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            }

            Section {
                if missedSupportItems.isEmpty {
                    Text(NSLocalizedString("No medications currently meet the missed-dose support threshold.", comment: ""))
                        .appFont(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(missedSupportItems, id: \.medication.id) { item in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(item.medication.name)
                                .appFont(.subheadline)
                            Text(String(format: NSLocalizedString("Missed for %lld days. Share reminders should now be active for caregivers with alerts enabled.", comment: ""), item.missedDays))
                                .appFont(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(.vertical, 2)
                    }
                    Button(NSLocalizedString("Prepare Status Update", comment: "")) {
                        shareText = buildSupportUpdate()
                        showShare = true
                    }
                }
            } header: {
                Text(NSLocalizedString("Current Support Status", comment: ""))
            }

            if store.caregivers.isEmpty {
                Section {
                    EmptyStateView(
                        systemImage: "person.2.fill",
                        title: NSLocalizedString("No caregivers added", comment: ""),
                        subtitle: NSLocalizedString("Add a family member or caregiver to share your medication status.", comment: ""),
                        actionTitle: NSLocalizedString("Add Caregiver", comment: ""),
                        action: { showAdd = true }
                    )
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
            }
        }
        .navigationTitle(NSLocalizedString("Caregivers", comment: ""))
        .toolbar {
            if !store.caregivers.isEmpty {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showAdd = true } label: { Image(systemName: "plus") }
                }
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

    private var caregiverSummary: String {
        if store.caregivers.isEmpty {
            return NSLocalizedString("Add someone you trust so missed-dose support is easier to act on later.", comment: "")
        }
        if caregiverAlertCount == 0 {
            return String(format: NSLocalizedString("%lld caregivers saved, but none are set for missed-dose support.", comment: ""), store.caregivers.count)
        }
        return String(format: NSLocalizedString("%lld caregivers saved. %lld will be included when missed-dose support is triggered.", comment: ""), store.caregivers.count, caregiverAlertCount)
    }

    private func buildSupportUpdate() -> String {
        var lines: [String] = []
        lines.append(NSLocalizedString("Medication Support Update", comment: ""))
        lines.append("")

        if !missedSupportItems.isEmpty {
            lines.append(NSLocalizedString("Attention needed for:", comment: ""))
            for item in missedSupportItems {
                lines.append("• \(item.medication.name) - \(item.missedDays) days missed")
            }
            lines.append("")
        }

        let enabledCaregivers = store.caregivers.filter(\.notifyOnMiss)
        if !enabledCaregivers.isEmpty {
            lines.append(NSLocalizedString("Configured caregivers:", comment: ""))
            for caregiver in enabledCaregivers {
                lines.append("• \(caregiver.name)")
            }
        }

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
