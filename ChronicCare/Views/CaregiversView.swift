import SwiftUI
import Contacts
import ContactsUI

struct CaregiversView: View {
    @EnvironmentObject var store: DataStore
    @State private var showAdd = false
    @State private var showAddOptions = false
    @State private var showContactPicker = false
    @State private var showContactPermissionAlert = false
    @State private var shareText: String = ""
    @State private var showShare = false
    @State private var draftName: String = ""
    @State private var draftPhone: String = ""

    private var caregiverAlertCount: Int {
        store.caregivers.filter(\.notifyOnMiss).count
    }

    private var enabledCaregivers: [CaregiverContact] {
        store.caregivers.filter(\.notifyOnMiss)
    }

    private var missedSupportItems: [(medication: Medication, missedDays: Int)] {
        store.medications.compactMap { medication in
            let missedDays = store.consecutiveMissedDays(for: medication.id)
            guard missedDays >= 2 else { return nil }
            return (medication, missedDays)
        }
    }

    private var hasActiveSupport: Bool {
        !missedSupportItems.isEmpty
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

            if !store.caregivers.isEmpty {
                Section {
                    supportOverviewRow
                } header: {
                    Text(NSLocalizedString("Support Readiness", comment: ""))
                }
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
                        action: { showAddOptions = true }
                    )
                }
                .listRowBackground(Color.clear)
            } else {
                Section {
                    ForEach(store.caregivers) { cg in
                        caregiverRow(cg)
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
                    Button { showAddOptions = true } label: { Image(systemName: "plus") }
                }
            }
        }
        .sheet(isPresented: $showAdd) {
            AddCaregiverSheet(initialName: draftName, initialPhone: draftPhone) { cg in
                store.addCaregiver(cg)
                Haptics.success()
                draftName = ""
                draftPhone = ""
            }
        }
        .sheet(isPresented: $showContactPicker) {
            ContactPickerSheet { contact in
                draftName = CNContactFormatter.string(from: contact, style: .fullName) ?? contact.givenName
                draftPhone = preferredPhoneNumber(from: contact) ?? ""
                showAdd = true
            }
        }
        .sheet(isPresented: $showShare) {
            ShareSheet(activityItems: [shareText])
        }
        .confirmationDialog(NSLocalizedString("Add Caregiver", comment: ""), isPresented: $showAddOptions, titleVisibility: .visible) {
            Button(NSLocalizedString("From Contacts", comment: "")) {
                startContactImport()
            }
            Button(NSLocalizedString("Enter Manually", comment: "")) {
                draftName = ""
                draftPhone = ""
                showAdd = true
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
            Text(NSLocalizedString("Allow Contacts access to choose a caregiver from your address book.", comment: ""))
        }
    }

    private var caregiverSummary: String {
        if store.caregivers.isEmpty {
            return NSLocalizedString("Add someone you trust so missed-dose support is easier to act on later.", comment: "")
        }
        if caregiverAlertCount == 0 {
            return String(format: NSLocalizedString("%lld caregivers saved, but none are set for missed-dose support.", comment: ""), store.caregivers.count)
        }
        if hasActiveSupport {
            return String(format: NSLocalizedString("%lld caregivers saved. %lld are ready to help with the current missed-dose support alert.", comment: ""), store.caregivers.count, caregiverAlertCount)
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

        if !enabledCaregivers.isEmpty {
            lines.append(NSLocalizedString("Configured caregivers:", comment: ""))
            for caregiver in enabledCaregivers {
                if let phone = caregiver.phone, !phone.isEmpty {
                    lines.append("• \(caregiver.name): \(phone)")
                } else {
                    lines.append("• \(caregiver.name)")
                }
            }
            lines.append("")
            lines.append(NSLocalizedString("Suggested next step:", comment: ""))
            lines.append(NSLocalizedString("Reach out to a caregiver and share this update if you still need support taking your medication.", comment: ""))
        }

        return lines.joined(separator: "\n")
    }

    private func caregiverRow(_ caregiver: CaregiverContact) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Circle()
                .fill(Color.blue.opacity(0.14))
                .frame(width: 36, height: 36)
                .overlay(
                    Image(systemName: "person.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.blue)
                )

            VStack(alignment: .leading, spacing: 4) {
                Text(caregiver.name)
                    .appFont(.subheadline)
                    .fontWeight(.semibold)
                if let phone = caregiver.phone, !phone.isEmpty {
                    Text(phone)
                        .appFont(.caption)
                        .foregroundStyle(.secondary)
                }
                Text(caregiver.notifyOnMiss
                     ? NSLocalizedString("Missed-dose support on", comment: "")
                     : NSLocalizedString("Missed-dose support off", comment: ""))
                    .appFont(.caption)
                    .foregroundStyle(caregiver.notifyOnMiss ? Color.orange : Color.secondary)
                if caregiver.notifyOnMiss {
                    Text(caregiverSupportLine(for: caregiver))
                        .appFont(.caption)
                        .foregroundStyle(hasActiveSupport ? Color.red : Color.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer()

            if caregiver.notifyOnMiss {
                Image(systemName: "bell.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
        .padding(.vertical, 2)
    }

    private var supportOverviewRow: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                Circle()
                    .fill((missedSupportItems.isEmpty ? Color.green : Color.orange).opacity(0.14))
                    .frame(width: 36, height: 36)
                    .overlay(
                        Image(systemName: missedSupportItems.isEmpty ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(missedSupportItems.isEmpty ? .green : .orange)
                    )

                VStack(alignment: .leading, spacing: 4) {
                    Text(missedSupportItems.isEmpty
                         ? NSLocalizedString("Support is ready", comment: "")
                         : NSLocalizedString("Support is active", comment: ""))
                        .appFont(.subheadline)
                        .fontWeight(.semibold)
                    Text(missedSupportItems.isEmpty
                         ? NSLocalizedString("No medication currently needs caregiver follow-up.", comment: "")
                         : activeSupportLine)
                        .appFont(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()
            }

            if hasActiveSupport {
                if enabledCaregivers.isEmpty {
                    Text(NSLocalizedString("No caregivers currently have missed-dose alerts enabled. Turn alerts on for at least one caregiver to make support useful.", comment: ""))
                        .appFont(.caption)
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Button {
                        shareText = buildSupportUpdate()
                        showShare = true
                    } label: {
                        Label(NSLocalizedString("Share Status Update", comment: ""), systemImage: "square.and.arrow.up")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.blue)
                    .controlSize(.small)
                }
            }
        }
        .padding(.vertical, 2)
    }

    private var activeSupportLine: String {
        guard !missedSupportItems.isEmpty else {
            return NSLocalizedString("No missed-dose support has been triggered yet.", comment: "")
        }
        if missedSupportItems.count == 1, let item = missedSupportItems.first {
            return String(format: NSLocalizedString("%@ has missed doses for %lld days. Caregivers with alerts enabled should be contacted.", comment: ""), item.medication.name, item.missedDays)
        }
        return String(format: NSLocalizedString("%lld medications now meet the missed-dose support threshold.", comment: ""), missedSupportItems.count)
    }

    private func caregiverSupportLine(for caregiver: CaregiverContact) -> String {
        guard caregiver.notifyOnMiss else {
            return NSLocalizedString("This caregiver will stay saved, but they will not be included in missed-dose support.", comment: "")
        }
        if hasActiveSupport {
            return NSLocalizedString("This caregiver should be included in the current support follow-up.", comment: "")
        }
        return NSLocalizedString("This caregiver will be included when support is triggered.", comment: "")
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
}

private struct AddCaregiverSheet: View {
    let initialName: String
    let initialPhone: String
    var onSave: (CaregiverContact) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var phone = ""
    @State private var notifyOnMiss = true

    init(initialName: String = "", initialPhone: String = "", onSave: @escaping (CaregiverContact) -> Void) {
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
                    TextField(NSLocalizedString("Phone (optional)", comment: ""), text: $phone)
                        .keyboardType(.phonePad)
                } header: {
                    Text(NSLocalizedString("Contact", comment: ""))
                } footer: {
                    Text(NSLocalizedString("Importing from Contacts fills name and phone. You can still edit them before saving.", comment: ""))
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

private struct ContactPickerSheet: UIViewControllerRepresentable {
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
