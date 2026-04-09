import SwiftUI

// MARK: - Edit View

struct EmergencyInfoEditView: View {
    @EnvironmentObject var store: DataStore
    @State private var bloodType: String
    @State private var allergies: String
    @State private var conditions: String
    @State private var contacts: [EmergencyContact]
    @State private var showAddContact = false

    init() {
        _bloodType = State(initialValue: "")
        _allergies = State(initialValue: "")
        _conditions = State(initialValue: "")
        _contacts = State(initialValue: [])
    }

    var body: some View {
        Form {
            Section {
                Picker(NSLocalizedString("Blood Type", comment: ""), selection: $bloodType) {
                    Text(NSLocalizedString("Not set", comment: "")).tag("")
                    ForEach(["A+", "A-", "B+", "B-", "AB+", "AB-", "O+", "O-"], id: \.self) { t in
                        Text(t).tag(t)
                    }
                }
            } header: {
                Text(NSLocalizedString("Basic Info", comment: ""))
            }

            Section {
                TextField(NSLocalizedString("e.g., Penicillin, Peanuts", comment: ""), text: $allergies, axis: .vertical)
                    .lineLimit(2...4)
            } header: {
                Text(NSLocalizedString("Allergies", comment: ""))
            } footer: {
                Text(NSLocalizedString("Separate multiple items with commas", comment: ""))
            }

            Section {
                TextField(NSLocalizedString("e.g., Hypertension, Diabetes", comment: ""), text: $conditions, axis: .vertical)
                    .lineLimit(2...4)
            } header: {
                Text(NSLocalizedString("Medical Conditions", comment: ""))
            }

            Section {
                ForEach(contacts) { contact in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(contact.name).appFont(.subheadline)
                        HStack(spacing: 8) {
                            Text(contact.relationship)
                                .appFont(.caption)
                                .foregroundStyle(.secondary)
                            Text(contact.phone)
                                .appFont(.caption)
                                .foregroundStyle(.blue)
                        }
                    }
                }
                .onDelete { contacts.remove(atOffsets: $0) }

                Button {
                    showAddContact = true
                } label: {
                    Label(NSLocalizedString("Add Contact", comment: ""), systemImage: "plus.circle.fill")
                }
            } header: {
                Text(NSLocalizedString("Emergency Contacts", comment: ""))
            }
        }
        .navigationTitle(NSLocalizedString("Emergency Info", comment: ""))
        .onAppear { loadFromStore() }
        .onDisappear { saveToStore() }
        .sheet(isPresented: $showAddContact) {
            AddEmergencyContactSheet { contact in
                contacts.append(contact)
            }
        }
    }

    private func loadFromStore() {
        guard let info = store.emergencyInfo else { return }
        bloodType = info.bloodType ?? ""
        allergies = info.allergies ?? ""
        conditions = info.medicalConditions ?? ""
        contacts = info.emergencyContacts
    }

    private func saveToStore() {
        let info = EmergencyInfo(
            bloodType: bloodType.isEmpty ? nil : bloodType,
            allergies: allergies.isEmpty ? nil : allergies,
            medicalConditions: conditions.isEmpty ? nil : conditions,
            emergencyContacts: contacts
        )
        store.updateEmergencyInfo(info)
    }
}

private struct AddEmergencyContactSheet: View {
    var onSave: (EmergencyContact) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var phone = ""
    @State private var relationship = ""

    var body: some View {
        NavigationStack {
            Form {
                TextField(NSLocalizedString("Name", comment: ""), text: $name)
                TextField(NSLocalizedString("Phone", comment: ""), text: $phone)
                    .keyboardType(.phonePad)
                TextField(NSLocalizedString("Relationship", comment: ""), text: $relationship)
            }
            .navigationTitle(NSLocalizedString("Add Contact", comment: ""))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(NSLocalizedString("Cancel", comment: "")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(NSLocalizedString("Save", comment: "")) {
                        onSave(EmergencyContact(name: name, phone: phone, relationship: relationship))
                        dismiss()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || phone.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }
}

// MARK: - Emergency Card (read-only, large font)

struct EmergencyCardView: View {
    @EnvironmentObject var store: DataStore
    @State private var showShare = false
    @State private var shareText = ""
    @State private var showEdit = false

    private var hasEmergencyDetails: Bool {
        let info = store.emergencyInfo
        return !(info?.bloodType?.isEmpty ?? true)
            || !(info?.allergies?.isEmpty ?? true)
            || !(info?.medicalConditions?.isEmpty ?? true)
            || !((info?.emergencyContacts ?? []).isEmpty)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Red banner
                HStack {
                    Image(systemName: "cross.case.fill")
                        .font(.system(size: 28))
                    Text(NSLocalizedString("Emergency Medical Info", comment: ""))
                        .appFont(.title)
                        .fontWeight(.bold)
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 20)
                .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(.red))

                if !hasEmergencyDetails && store.medications.isEmpty {
                    Card {
                        EmptyStateView(
                            systemImage: "cross.case.fill",
                            title: NSLocalizedString("Emergency information not set", comment: ""),
                            subtitle: NSLocalizedString("Add blood type, allergies, conditions, or emergency contacts so this card is useful when you need it.", comment: ""),
                            actionTitle: NSLocalizedString("Add Emergency Info", comment: ""),
                            action: { showEdit = true }
                        )
                    }
                }

                // Blood type
                if let bt = store.emergencyInfo?.bloodType, !bt.isEmpty {
                    infoCard(title: NSLocalizedString("Blood Type", comment: ""), value: bt, icon: "drop.fill", tint: .red)
                }

                // Allergies
                if let allergy = store.emergencyInfo?.allergies, !allergy.isEmpty {
                    infoCard(title: NSLocalizedString("Allergies", comment: ""), value: allergy, icon: "exclamationmark.triangle.fill", tint: .orange)
                }

                // Medical conditions
                if let cond = store.emergencyInfo?.medicalConditions, !cond.isEmpty {
                    infoCard(title: NSLocalizedString("Medical Conditions", comment: ""), value: cond, icon: "heart.text.square.fill", tint: .blue)
                }

                // Current medications
                if !store.medications.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Label(NSLocalizedString("Current Medications", comment: ""), systemImage: "pill.fill")
                            .appFont(.headline)
                        ForEach(store.medications) { med in
                            HStack {
                                Text(med.name).appFont(.body).fontWeight(.medium)
                                Spacer()
                                Text(med.dose).appFont(.body).foregroundStyle(.secondary)
                            }
                        }
                    }
                    .padding()
                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color(.secondarySystemBackground)))
                }

                // Emergency contacts
                let contacts = store.emergencyInfo?.emergencyContacts ?? []
                if !contacts.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Label(NSLocalizedString("Emergency Contacts", comment: ""), systemImage: "phone.fill")
                            .appFont(.headline)
                        ForEach(contacts) { contact in
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(contact.name).appFont(.body).fontWeight(.medium)
                                    Text(contact.relationship).appFont(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                let sanitizedPhone = contact.phone.filter { $0.isNumber || $0 == "+" }
                                if let callURL = URL(string: "tel:\(sanitizedPhone)") {
                                    Link(destination: callURL) {
                                        Label(contact.phone, systemImage: "phone.fill")
                                            .appFont(.subheadline)
                                    }
                                } else {
                                    Label(contact.phone, systemImage: "phone.fill")
                                        .appFont(.subheadline)
                                }
                            }
                        }
                    }
                    .padding()
                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color(.secondarySystemBackground)))
                }

                // Share button
                Button {
                    shareText = buildEmergencySummary()
                    showShare = true
                } label: {
                    Label(NSLocalizedString("Share Emergency Info", comment: ""), systemImage: "square.and.arrow.up")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .tint(.red)
            }
            .padding()
        }
        .navigationTitle(NSLocalizedString("Emergency Card", comment: ""))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(NSLocalizedString("Edit", comment: "")) {
                    showEdit = true
                }
            }
        }
        .sheet(isPresented: $showShare) {
            ShareSheet(activityItems: [shareText])
        }
        .sheet(isPresented: $showEdit) {
            NavigationStack {
                EmergencyInfoEditView()
                    .environmentObject(store)
            }
        }
    }

    private func infoCard(title: String, value: String, icon: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: icon)
                .appFont(.caption)
                .foregroundStyle(tint)
            Text(value)
                .appFont(.title)
                .fontWeight(.bold)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(tint.opacity(0.1)))
    }

    private func buildEmergencySummary() -> String {
        var lines: [String] = []
        lines.append("⚕️ EMERGENCY MEDICAL INFO")
        lines.append("")
        if let bt = store.emergencyInfo?.bloodType, !bt.isEmpty {
            lines.append("Blood Type: \(bt)")
        }
        if let a = store.emergencyInfo?.allergies, !a.isEmpty {
            lines.append("⚠️ Allergies: \(a)")
        }
        if let c = store.emergencyInfo?.medicalConditions, !c.isEmpty {
            lines.append("Conditions: \(c)")
        }
        if !store.medications.isEmpty {
            lines.append("")
            lines.append("Current Medications:")
            for med in store.medications {
                lines.append("  • \(med.name) \(med.dose)")
            }
        }
        let contacts = store.emergencyInfo?.emergencyContacts ?? []
        if !contacts.isEmpty {
            lines.append("")
            lines.append("Emergency Contacts:")
            for c in contacts {
                lines.append("  • \(c.name) (\(c.relationship)): \(c.phone)")
            }
        }
        return lines.joined(separator: "\n")
    }
}
