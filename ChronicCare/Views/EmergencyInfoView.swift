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
            VStack(spacing: 14) {
                summaryHeader
                emptyEmergencyState
                doctorVisitSnapshot
                currentMedicationsCard
                coreMedicalInfoCards
                recentMeasurementsCard
                emergencyContactsCard
                shareSummaryButton
            }
            .padding()
        }
        .navigationTitle(NSLocalizedString("Medical Summary", comment: ""))
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

    private var scheduledMedicationCount: Int {
        store.medications.filter { $0.isAsNeeded != true && !$0.timesOfDay.isEmpty }.count
    }

    private var summaryHeader: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: "person.text.rectangle.fill")
                .font(.system(size: 24, weight: .semibold))
                .frame(width: 46, height: 46)
                .background(Circle().fill(Color.red.opacity(0.16)))

            VStack(alignment: .leading, spacing: 4) {
                Text(NSLocalizedString("Medical Summary", comment: ""))
                    .appFont(.title)
                    .fontWeight(.bold)
                Text(NSLocalizedString("Use this during appointments to answer common questions quickly.", comment: ""))
                    .appFont(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()
        }
        .foregroundStyle(.red)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Color.red.opacity(0.08)))
    }

    @ViewBuilder
    private var emptyEmergencyState: some View {
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
    }

    private var latestMeasurementsByType: [Measurement] {
        MeasurementType.allCases.compactMap { type in
            store.measurements
                .filter { $0.type == type }
                .sorted { $0.date > $1.date }
                .first
        }
    }

    @ViewBuilder
    private var currentMedicationsCard: some View {
        if !store.medications.isEmpty {
            Card {
                VStack(alignment: .leading, spacing: 12) {
                    Label(NSLocalizedString("Current Medications", comment: ""), systemImage: "pill.fill")
                        .appFont(.headline)
                    ForEach(store.medications) { med in
                        medicationSummaryRow(med)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var coreMedicalInfoCards: some View {
        if let allergy = store.emergencyInfo?.allergies, !allergy.isEmpty {
            infoCard(title: NSLocalizedString("Allergies", comment: ""), value: allergy, icon: "exclamationmark.triangle.fill", tint: .red)
        }

        if let cond = store.emergencyInfo?.medicalConditions, !cond.isEmpty {
            infoCard(title: NSLocalizedString("Medical Conditions", comment: ""), value: cond, icon: "heart.text.square.fill", tint: .blue)
        }

        if let bt = store.emergencyInfo?.bloodType, !bt.isEmpty {
            infoCard(title: NSLocalizedString("Blood Type", comment: ""), value: bt, icon: "drop.fill", tint: .red)
        }
    }

    @ViewBuilder
    private var recentMeasurementsCard: some View {
        if !latestMeasurementsByType.isEmpty {
            Card {
                VStack(alignment: .leading, spacing: 12) {
                    Label(NSLocalizedString("Recent Measurements", comment: ""), systemImage: "waveform.path.ecg")
                        .appFont(.headline)
                    ForEach(latestMeasurementsByType) { measurement in
                        measurementSummaryRow(measurement)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var emergencyContactsCard: some View {
        let contacts = store.emergencyInfo?.emergencyContacts ?? []
        if !contacts.isEmpty {
            Card {
                VStack(alignment: .leading, spacing: 12) {
                    Label(NSLocalizedString("Emergency Contacts", comment: ""), systemImage: "phone.fill")
                        .appFont(.headline)
                    ForEach(contacts) { contact in
                        emergencyContactRow(contact)
                    }
                }
            }
        }
    }

    private var shareSummaryButton: some View {
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

    private var adherenceSummaryText: String {
        guard scheduledMedicationCount > 0 else {
            return NSLocalizedString("No scheduled medications", comment: "")
        }
        return String(format: "%.0f%%", store.adherencePercent(days: 7) * 100)
    }

    private var doctorVisitSnapshot: some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                Label(NSLocalizedString("Doctor Visit Snapshot", comment: ""), systemImage: "stethoscope")
                    .appFont(.headline)

                HStack(spacing: 10) {
                    snapshotMetric(
                        value: "\(store.medications.count)",
                        label: NSLocalizedString("medications", comment: ""),
                        tint: .blue
                    )
                    snapshotMetric(
                        value: allergiesSnapshotText,
                        label: NSLocalizedString("allergies", comment: ""),
                        tint: allergiesSnapshotText == NSLocalizedString("None", comment: "") ? .green : .red
                    )
                    snapshotMetric(
                        value: adherenceSummaryText,
                        label: NSLocalizedString("7-day adherence", comment: ""),
                        tint: scheduledMedicationCount > 0 ? .green : .secondary
                    )
                }
            }
        }
    }

    private var allergiesSnapshotText: String {
        if let allergies = store.emergencyInfo?.allergies, !allergies.isEmpty {
            return allergies
        }
        return NSLocalizedString("None", comment: "")
    }

    private func snapshotMetric(value: String, label: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(value)
                .appFont(.subheadline)
                .fontWeight(.semibold)
                .foregroundStyle(tint)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(label)
                .appFont(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, minHeight: 62, alignment: .topLeading)
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(tint.opacity(0.08))
        )
    }

    private func infoCard(title: String, value: String, icon: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: icon)
                .appFont(.caption)
                .foregroundStyle(tint)
            Text(value)
                .appFont(.body)
                .fontWeight(.semibold)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(tint.opacity(0.1)))
    }

    private func medicationSummaryRow(_ med: Medication) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(med.name)
                    .appFont(.subheadline)
                    .fontWeight(.semibold)
                if !med.timesOfDay.isEmpty {
                    Text(med.timesOfDay.map(timeText).joined(separator: ", "))
                        .appFont(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Text(med.dose)
                .appFont(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.trailing)
        }
    }

    private func measurementSummaryRow(_ measurement: Measurement) -> some View {
        HStack {
            Text(measurement.type.displayName)
                .appFont(.subheadline)
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(measurementValueText(measurement))
                    .appFont(.subheadline)
                    .fontWeight(.semibold)
                Text(measurement.date, format: .dateTime.month(.abbreviated).day())
                    .appFont(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func emergencyContactRow(_ contact: EmergencyContact) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(contact.name).appFont(.subheadline).fontWeight(.semibold)
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

    private func timeText(_ components: DateComponents) -> String {
        let hour = components.hour ?? 0
        let minute = components.minute ?? 0
        return String(format: "%02d:%02d", hour, minute)
    }

    private func measurementValueText(_ measurement: Measurement) -> String {
        if measurement.type == .bloodPressure, let diastolic = measurement.diastolic {
            return "\(Int(measurement.value))/\(Int(diastolic)) \(measurement.type.unit)"
        }
        if measurement.type == .bloodGlucose {
            let value = UnitPreferences.mgdlToPreferred(measurement.value)
            let formatted = UnitPreferences.glucoseUnit == .mgdL ? String(format: "%.0f", value) : String(format: "%.1f", value)
            return "\(formatted) \(UnitPreferences.glucoseUnit.rawValue)"
        }
        return "\(String(format: "%.1f", measurement.value)) \(measurement.type.unit)"
    }

    private func buildEmergencySummary() -> String {
        var lines: [String] = []
        lines.append("MEDICAL SUMMARY")
        lines.append("")
        lines.append("7-day adherence: \(adherenceSummaryText)")
        if !latestMeasurementsByType.isEmpty {
            lines.append("")
            lines.append("Recent Measurements:")
            for measurement in latestMeasurementsByType {
                lines.append("  • \(measurement.type.displayName): \(measurementValueText(measurement))")
            }
        }
        if let a = store.emergencyInfo?.allergies, !a.isEmpty {
            lines.append("")
            lines.append("Allergies: \(a)")
        }
        if let c = store.emergencyInfo?.medicalConditions, !c.isEmpty {
            lines.append("Conditions: \(c)")
        }
        if let bt = store.emergencyInfo?.bloodType, !bt.isEmpty {
            lines.append("Blood Type: \(bt)")
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
