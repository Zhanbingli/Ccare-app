import SwiftUI
import Contacts
import ContactsUI
import UIKit

// MARK: - Edit View

struct EmergencyInfoEditView: View {
    @EnvironmentObject var store: DataStore
    @State private var bloodType: String
    @State private var allergies: String
    @State private var conditions: String
    @State private var contacts: [EmergencyContact]
    @State private var showAddContact = false
    @State private var showAddContactOptions = false
    @State private var showContactPicker = false
    @State private var showContactPermissionAlert = false
    @State private var draftContactName = ""
    @State private var draftContactPhone = ""

    init() {
        _bloodType = State(initialValue: "")
        _allergies = State(initialValue: "")
        _conditions = State(initialValue: "")
        _contacts = State(initialValue: [])
    }

    var body: some View {
        Form {
            // Contacts first: the single most-used thing during a real emergency.
            Section {
                if contacts.isEmpty {
                    Text(NSLocalizedString("No emergency contact added yet.", comment: ""))
                        .appFont(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(contacts) { contact in
                        emergencyContactEditorRow(contact)
                    }
                    .onDelete { contacts.remove(atOffsets: $0) }
                }

                Button {
                    showAddContactOptions = true
                } label: {
                    Label(NSLocalizedString("Add Contact", comment: ""), systemImage: "plus.circle.fill")
                }
            } header: {
                Text(NSLocalizedString("Emergency Contacts", comment: ""))
            } footer: {
                Text(NSLocalizedString("Use emergency contacts for urgent or hospital situations. This is different from caregiver support.", comment: ""))
            }

            Section {
                TextField(NSLocalizedString("e.g., Penicillin, Peanuts", comment: ""), text: $allergies, axis: .vertical)
                    .lineLimit(2...4)
            } header: {
                Text(NSLocalizedString("Allergies", comment: ""))
            } footer: {
                Text(allergies.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                     ? NSLocalizedString("No allergies added yet. Separate multiple items with commas.", comment: "")
                     : NSLocalizedString("Separate multiple items with commas", comment: ""))
            }

            Section {
                TextField(NSLocalizedString("e.g., Hypertension, Diabetes", comment: ""), text: $conditions, axis: .vertical)
                    .lineLimit(2...4)
            } header: {
                Text(NSLocalizedString("Medical Conditions", comment: ""))
            } footer: {
                Text(conditions.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                     ? NSLocalizedString("No medical conditions added yet.", comment: "")
                     : NSLocalizedString("List ongoing diagnoses that matter during appointments or emergencies.", comment: ""))
            }

            Section {
                Picker(NSLocalizedString("Blood Type", comment: ""), selection: $bloodType) {
                    Text(NSLocalizedString("Not set", comment: "")).tag("")
                    ForEach(["A+", "A-", "B+", "B-", "AB+", "AB-", "O+", "O-"], id: \.self) { t in
                        Text(t).tag(t)
                    }
                }
            } header: {
                Text(NSLocalizedString("Blood Type", comment: ""))
            } footer: {
                Text(NSLocalizedString("Helpful in emergencies, but lower priority than allergies and contacts.", comment: ""))
            }
        }
        .navigationTitle(NSLocalizedString("Emergency Info", comment: ""))
        .onAppear { loadFromStore() }
        .onDisappear { saveToStore() }
        .sheet(isPresented: $showAddContact) {
            AddEmergencyContactSheet(initialName: draftContactName, initialPhone: draftContactPhone) { contact in
                contacts.append(contact)
                draftContactName = ""
                draftContactPhone = ""
            }
        }
        .sheet(isPresented: $showContactPicker) {
            EmergencyContactPickerSheet { contact in
                draftContactName = CNContactFormatter.string(from: contact, style: .fullName) ?? contact.givenName
                draftContactPhone = preferredPhoneNumber(from: contact) ?? ""
                showAddContact = true
            }
        }
        .confirmationDialog(NSLocalizedString("Add Contact", comment: ""), isPresented: $showAddContactOptions, titleVisibility: .visible) {
            Button(NSLocalizedString("From Contacts", comment: "")) {
                startContactImport()
            }
            Button(NSLocalizedString("Enter Manually", comment: "")) {
                draftContactName = ""
                draftContactPhone = ""
                showAddContact = true
            }
            Button(NSLocalizedString("Cancel", comment: ""), role: .cancel) { }
        }
        .alert(NSLocalizedString("Contacts Access Needed", comment: ""), isPresented: $showContactPermissionAlert) {
            Button(NSLocalizedString("Open Settings", comment: "")) {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            Button(NSLocalizedString("Cancel", comment: ""), role: .cancel) { }
        } message: {
            Text(NSLocalizedString("Allow Contacts access to choose an emergency contact from your address book.", comment: ""))
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

    private func startContactImport() {
        let store = CNContactStore()
        switch CNContactStore.authorizationStatus(for: .contacts) {
        case .authorized:
            showContactPicker = true
        case .limited:
            showContactPicker = true
        case .notDetermined:
            store.requestAccess(for: .contacts) { granted, _ in
                DispatchQueue.main.async {
                    if granted {
                        showContactPicker = true
                    } else {
                        showContactPermissionAlert = true
                    }
                }
            }
        case .denied, .restricted:
            showContactPermissionAlert = true
        @unknown default:
            showContactPermissionAlert = true
        }
    }

    private func preferredPhoneNumber(from contact: CNContact) -> String? {
        if let mobile = contact.phoneNumbers.first(where: {
            let label = CNLabeledValue<NSString>.localizedString(forLabel: $0.label ?? "")
            return label.localizedCaseInsensitiveContains("mobile") || label.localizedCaseInsensitiveContains("iPhone")
        }) {
            return mobile.value.stringValue
        }
        return contact.phoneNumbers.first?.value.stringValue
    }

    private func emergencyContactEditorRow(_ contact: EmergencyContact) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Circle()
                .fill(Color.red.opacity(0.14))
                .frame(width: 36, height: 36)
                .overlay(
                    Image(systemName: "phone.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.red)
                )

            VStack(alignment: .leading, spacing: 4) {
                Text(contact.name)
                    .appFont(.subheadline)
                    .fontWeight(.semibold)
                Text(contact.relationship)
                    .appFont(.caption)
                    .foregroundStyle(.secondary)
                contactPhoneLink(contact)
            }

            Spacer()
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private func contactPhoneLink(_ contact: EmergencyContact) -> some View {
        let sanitized = contact.phone.filter { $0.isNumber || $0 == "+" }
        if let encoded = sanitized.addingPercentEncoding(withAllowedCharacters: .urlHostAllowed),
           let callURL = URL(string: "tel:\(encoded)") {
            Link(destination: callURL) {
                Text(contact.phone)
                    .appFont(.caption)
                    .foregroundStyle(.blue)
            }
            .accessibilityLabel(String(format: NSLocalizedString("Call %@, %@", comment: "Call emergency contact accessibility"), contact.name, contact.phone))
        } else {
            Text(contact.phone)
                .appFont(.caption)
                .foregroundStyle(.blue)
        }
    }
}

private struct AddEmergencyContactSheet: View {
    let initialName: String
    let initialPhone: String
    var onSave: (EmergencyContact) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var phone = ""
    @State private var relationship = ""

    init(initialName: String = "", initialPhone: String = "", onSave: @escaping (EmergencyContact) -> Void) {
        self.initialName = initialName
        self.initialPhone = initialPhone
        self.onSave = onSave
        _name = State(initialValue: initialName)
        _phone = State(initialValue: initialPhone)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(NSLocalizedString("Name", comment: ""), text: $name)
                    TextField(NSLocalizedString("Phone", comment: ""), text: $phone)
                        .keyboardType(.phonePad)
                    TextField(NSLocalizedString("Relationship", comment: ""), text: $relationship)
                } header: {
                    Text(NSLocalizedString("Contact", comment: ""))
                } footer: {
                    Text(NSLocalizedString("Importing from Contacts fills name and phone. Add the relationship before saving.", comment: ""))
                }
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

    private var hasShareableSummary: Bool {
        hasEmergencyDetails || !store.medications.isEmpty || !latestMeasurementsByType.isEmpty || !store.caregivers.isEmpty
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
                caregiverSupportCard
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
        TintedCard(tint: .red) {
            HStack(alignment: .center, spacing: AppSpacing.small) {
                Image(systemName: "person.text.rectangle.fill")
                    .font(.system(size: 24, weight: .semibold))
                    .frame(width: 46, height: 46)
                    .background(Circle().fill(Color.red.opacity(0.16)))
                    .foregroundStyle(.red)

                VStack(alignment: .leading, spacing: AppSpacing.xxSmall) {
                    Text(NSLocalizedString("Medical Summary", comment: ""))
                        .appFont(.title)
                        .fontWeight(.bold)
                        .foregroundStyle(.red)
                    Text(NSLocalizedString("Use this during appointments to answer common questions quickly.", comment: ""))
                        .appFont(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()
            }
        }
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
                    Text(NSLocalizedString("Use these people in urgent or emergency situations, such as going to the hospital or needing immediate help.", comment: ""))
                        .appFont(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    ForEach(contacts) { contact in
                        emergencyContactRow(contact)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var caregiverSupportCard: some View {
        if !store.caregivers.isEmpty {
            Card {
                VStack(alignment: .leading, spacing: 12) {
                    Label(NSLocalizedString("Caregiver Support", comment: ""), systemImage: "person.2.fill")
                        .appFont(.headline)
                    Text(NSLocalizedString("Caregivers are for routine support and missed-dose follow-up. They are separate from emergency contacts.", comment: ""))
                        .appFont(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    ForEach(store.caregivers) { caregiver in
                        caregiverSummaryRow(caregiver)
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
            Label(NSLocalizedString("Share Medical Summary", comment: ""), systemImage: "square.and.arrow.up")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .tint(.red)
        .disabled(!hasShareableSummary)
        .opacity(hasShareableSummary ? 1 : 0.6)
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
        InsetPanel(tint: tint) {
            VStack(alignment: .leading, spacing: AppSpacing.xxSmall) {
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
        }
    }

    private func infoCard(title: String, value: String, icon: String, tint: Color) -> some View {
        InsetPanel(tint: tint) {
            VStack(alignment: .leading, spacing: AppSpacing.xSmall) {
                Label(title, systemImage: icon)
                    .appFont(.caption)
                    .foregroundStyle(tint)
                Text(value)
                    .appFont(.body)
                    .fontWeight(.semibold)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
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
            if let encoded = sanitizedPhone.addingPercentEncoding(withAllowedCharacters: .urlHostAllowed),
               let callURL = URL(string: "tel:\(encoded)") {
                Link(destination: callURL) {
                    Label(contact.phone, systemImage: "phone.fill")
                        .appFont(.subheadline)
                }
                .accessibilityLabel(String(format: NSLocalizedString("Call %@, %@", comment: "Call emergency contact accessibility"), contact.name, contact.phone))
            } else {
                Label(contact.phone, systemImage: "phone.fill")
                    .appFont(.subheadline)
            }
        }
    }

    private func caregiverSummaryRow(_ caregiver: CaregiverContact) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(caregiver.name)
                    .appFont(.subheadline)
                    .fontWeight(.semibold)
                if let phone = caregiver.phone, !phone.isEmpty {
                    Text(phone)
                        .appFont(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Text(caregiver.notifyOnMiss
                 ? NSLocalizedString("Missed-dose alerts on", comment: "")
                 : NSLocalizedString("Saved", comment: ""))
                .appFont(.caption)
                .foregroundStyle(caregiver.notifyOnMiss ? .orange : .secondary)
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
        let caregivers = store.caregivers
        if !caregivers.isEmpty {
            lines.append("")
            lines.append("Caregiver Support:")
            for caregiver in caregivers {
                if let phone = caregiver.phone, !phone.isEmpty {
                    lines.append("  • \(caregiver.name): \(phone)")
                } else {
                    lines.append("  • \(caregiver.name)")
                }
            }
        }
        return lines.joined(separator: "\n")
    }
}

private struct EmergencyContactPickerSheet: UIViewControllerRepresentable {
    var onSelect: (CNContact) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeCoordinator() -> Coordinator {
        Coordinator(onSelect: onSelect, dismiss: dismiss)
    }

    func makeUIViewController(context: Context) -> CNContactPickerViewController {
        let picker = CNContactPickerViewController()
        picker.delegate = context.coordinator
        picker.displayedPropertyKeys = [CNContactGivenNameKey, CNContactFamilyNameKey, CNContactPhoneNumbersKey]
        return picker
    }

    func updateUIViewController(_ uiViewController: CNContactPickerViewController, context: Context) {}

    final class Coordinator: NSObject, CNContactPickerDelegate {
        private let onSelect: (CNContact) -> Void
        private let dismiss: DismissAction

        init(onSelect: @escaping (CNContact) -> Void, dismiss: DismissAction) {
            self.onSelect = onSelect
            self.dismiss = dismiss
        }

        func contactPicker(_ picker: CNContactPickerViewController, didSelect contact: CNContact) {
            onSelect(contact)
            dismiss()
        }

        func contactPickerDidCancel(_ picker: CNContactPickerViewController) {
            dismiss()
        }
    }
}
