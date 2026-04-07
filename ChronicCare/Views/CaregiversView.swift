import SwiftUI

struct CaregiversView: View {
    @EnvironmentObject var store: DataStore
    @State private var showAdd = false

    var body: some View {
        List {
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
