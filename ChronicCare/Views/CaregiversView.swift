import SwiftUI
import Contacts
import ContactsUI
import MessageUI

struct CaregiversView: View {
    @EnvironmentObject var store: DataStore
    @State private var showAdd = false
    @State private var showAddOptions = false
    @State private var showContactPicker = false
    @State private var showContactPermissionAlert = false
    @State private var shareText: String = ""
    @State private var showShare = false
    @State private var messageDraft: CaregiverMessageDraft?
    @State private var draftName: String = ""
    @State private var draftPhone: String = ""
    @State private var caregiverPendingRemoval: CaregiverContact?

    private var caregiverAlertCount: Int {
        store.caregivers.filter(\.notifyOnMiss).count
    }

    private var enabledCaregivers: [CaregiverContact] {
        store.caregivers.filter(\.notifyOnMiss)
    }

    private var textableCaregivers: [CaregiverContact] {
        enabledCaregivers.filter { sanitizedPhone($0.phone) != nil }
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

    private var removalConfirmationBinding: Binding<Bool> {
        Binding(
            get: { caregiverPendingRemoval != nil },
            set: { if !$0 { caregiverPendingRemoval = nil } }
        )
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: EditorialSpacing.xl) {
                header
                currentNeedSection

                if store.caregivers.isEmpty {
                    emptyPeopleSection
                } else {
                    peopleSection
                }

                privacyNote
            }
            .padding(.horizontal, EditorialSpacing.lg)
            .padding(.vertical, EditorialSpacing.lg)
        }
        .background(AppColor.background)
        .navigationTitle(NSLocalizedString("Caregivers", comment: ""))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showAddOptions = true } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel(NSLocalizedString("Add Caregiver", comment: ""))
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
        .sheet(item: $messageDraft) { draft in
            MessageComposeSheet(
                recipients: draft.recipients,
                body: draft.body
            )
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
        .confirmationDialog(NSLocalizedString("Remove Caregiver?", comment: "Caregiver removal confirmation title"), isPresented: removalConfirmationBinding, titleVisibility: .visible) {
            Button(NSLocalizedString("Remove", comment: ""), role: .destructive) {
                if let caregiverPendingRemoval {
                    removeCaregiver(caregiverPendingRemoval)
                }
                caregiverPendingRemoval = nil
            }
            Button(NSLocalizedString("Cancel", comment: ""), role: .cancel) {
                caregiverPendingRemoval = nil
            }
        } message: {
            Text(NSLocalizedString("This only removes the saved caregiver contact. Medication records stay unchanged.", comment: "Caregiver removal confirmation message"))
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

    private var header: some View {
        VStack(alignment: .leading, spacing: EditorialSpacing.sm) {
            Text(NSLocalizedString("Caregiver support", comment: "Caregiver page heading"))
                .appFont(.displayTitle)
                .fontWeight(.bold)
                .foregroundStyle(AppColor.textPrimary)
            Text(caregiverSummary)
                .appFont(.body)
                .foregroundStyle(AppColor.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: EditorialSpacing.md) {
                statusMetric(
                    value: "\(store.caregivers.count)",
                    label: NSLocalizedString("Saved", comment: "Caregiver metric")
                )
                metricDivider
                statusMetric(
                    value: "\(caregiverAlertCount)",
                    label: NSLocalizedString("Support on", comment: "Caregiver metric")
                )
                metricDivider
                statusMetric(
                    value: "\(missedSupportItems.count)",
                    label: NSLocalizedString("Need help", comment: "Caregiver metric")
                )
            }
            .padding(.top, EditorialSpacing.xs)
        }
    }

    private var metricDivider: some View {
        Rectangle()
            .fill(AppColor.divider)
            .frame(width: 1, height: 34)
    }

    private var currentNeedSection: some View {
        EditorialSection(
            NSLocalizedString("Current Need", comment: "Caregiver section"),
            trailing: supportStateLabel
        ) {
            VStack(alignment: .leading, spacing: EditorialSpacing.md) {
                statusRow

                if hasActiveSupport {
                    VStack(spacing: EditorialSpacing.xs) {
                        ForEach(missedSupportItems, id: \.medication.id) { item in
                            medicationNeedRow(item)
                        }
                    }

                    if enabledCaregivers.isEmpty {
                        quietWarning(
                            NSLocalizedString("Turn on missed-dose support for at least one caregiver before sending a reminder.", comment: "Caregiver support warning")
                        )
                    } else if textableCaregivers.isEmpty {
                        quietWarning(
                            NSLocalizedString("Add a phone number to text a caregiver directly.", comment: "Caregiver support warning")
                        )
                    } else {
                        EditorialButton(
                            NSLocalizedString("Notify Caregiver", comment: "Caregiver notify action"),
                            systemImage: "message",
                            kind: .primary
                        ) {
                            notifyEnabledCaregivers()
                        }
                    }
                }
            }
        }
    }

    private var emptyPeopleSection: some View {
        EditorialSection(NSLocalizedString("People", comment: "Caregiver section")) {
            VStack(alignment: .leading, spacing: EditorialSpacing.lg) {
                HStack(alignment: .top, spacing: EditorialSpacing.md) {
                    Image(systemName: "person.2")
                        .font(.system(size: 18, weight: .regular))
                        .foregroundStyle(AppColor.primary)
                        .frame(width: 32, height: 32)

                    VStack(alignment: .leading, spacing: EditorialSpacing.xs) {
                        Text(NSLocalizedString("No caregivers added", comment: ""))
                            .appFont(.headline)
                            .foregroundStyle(AppColor.textPrimary)
                        Text(NSLocalizedString("Add one trusted person for routine missed-dose support.", comment: "Caregiver empty state"))
                            .appFont(.body)
                            .foregroundStyle(AppColor.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                HStack(spacing: EditorialSpacing.md) {
                    EditorialButton(
                        NSLocalizedString("From Contacts", comment: ""),
                        systemImage: "person.crop.circle.badge.plus",
                        kind: .secondary
                    ) {
                        startContactImport()
                    }

                    EditorialButton(
                        NSLocalizedString("Enter Manually", comment: ""),
                        systemImage: "square.and.pencil",
                        kind: .secondary
                    ) {
                        draftName = ""
                        draftPhone = ""
                        showAdd = true
                    }
                }
            }
        }
    }

    private var peopleSection: some View {
        EditorialSection(
            NSLocalizedString("People", comment: "Caregiver section"),
            trailing: String(format: NSLocalizedString("%lld saved", comment: "Caregiver section count"), Int64(store.caregivers.count))
        ) {
            VStack(spacing: EditorialSpacing.md) {
                ForEach(Array(store.caregivers.enumerated()), id: \.element.id) { index, caregiver in
                    caregiverRow(caregiver)
                    if index < store.caregivers.count - 1 {
                        AppDivider()
                    }
                }
            }
        }
    }

    private var privacyNote: some View {
        Text(NSLocalizedString("The app prepares the caregiver reminder and opens Messages. You review and send it.", comment: "Caregiver privacy note"))
            .appFont(.caption)
            .foregroundStyle(AppColor.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var statusRow: some View {
        HStack(alignment: .top, spacing: EditorialSpacing.md) {
            Image(systemName: supportStatusIcon)
                .font(.system(size: 16, weight: .regular))
                .foregroundStyle(supportStatusTint)
                .frame(width: 30, height: 30)

            VStack(alignment: .leading, spacing: EditorialSpacing.xs) {
                Text(supportStatusTitle)
                    .appFont(.headline)
                    .foregroundStyle(AppColor.textPrimary)
                Text(supportStatusDetail)
                    .appFont(.body)
                    .foregroundStyle(AppColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: EditorialSpacing.sm)
        }
    }

    private var supportStateLabel: String {
        if hasActiveSupport { return NSLocalizedString("Action needed", comment: "Caregiver support state") }
        if caregiverAlertCount > 0 { return NSLocalizedString("Ready", comment: "Caregiver support state") }
        return NSLocalizedString("Setup needed", comment: "Caregiver support state")
    }

    private var supportStatusIcon: String {
        if hasActiveSupport { return enabledCaregivers.isEmpty ? "exclamationmark.circle" : "person.2.fill" }
        return caregiverAlertCount > 0 ? "checkmark.circle" : "bell.slash"
    }

    private var supportStatusTint: Color {
        if hasActiveSupport || caregiverAlertCount == 0 { return AppColor.warning }
        return AppColor.primary
    }

    private var supportStatusTitle: String {
        if hasActiveSupport { return NSLocalizedString("Caregiver follow-up is needed", comment: "Caregiver support status") }
        if caregiverAlertCount > 0 { return NSLocalizedString("Caregiver support is ready", comment: "Caregiver support status") }
        return NSLocalizedString("Caregivers saved, support off", comment: "Caregiver support status")
    }

    private var supportStatusDetail: String {
        if hasActiveSupport {
            if missedSupportItems.count == 1, let item = missedSupportItems.first {
                return String(format: NSLocalizedString("%@ has been missed for %lld days.", comment: "Caregiver active support detail"), item.medication.name, Int64(item.missedDays))
            }
            return String(format: NSLocalizedString("%lld medications meet the missed-dose support threshold.", comment: "Caregiver active support detail"), Int64(missedSupportItems.count))
        }
        if caregiverAlertCount > 0 {
            return String(format: NSLocalizedString("%lld caregiver(s) will be included when missed-dose support is triggered.", comment: "Caregiver ready detail"), Int64(caregiverAlertCount))
        }
        return NSLocalizedString("Turn on support for a saved caregiver to make this useful when doses are missed.", comment: "Caregiver setup detail")
    }

    private var caregiverSummary: String {
        if store.caregivers.isEmpty {
            return NSLocalizedString("Choose who can help when medication routines slip.", comment: "Caregiver page summary")
        }
        if hasActiveSupport {
            return NSLocalizedString("Send a clear missed-dose reminder to the people who should help.", comment: "Caregiver page summary")
        }
        if caregiverAlertCount == 0 {
            return NSLocalizedString("Contacts are saved. Turn support on for the people who should help with missed doses.", comment: "Caregiver page summary")
        }
        return String(format: NSLocalizedString("%lld of %lld caregivers are set for missed-dose support.", comment: "Caregiver page summary"), Int64(caregiverAlertCount), Int64(store.caregivers.count))
    }

    private func statusMetric(value: String, label: String) -> some View {
        VStack(alignment: .leading, spacing: EditorialSpacing.xxs) {
            Text(value)
                .appFontNumeric(.headline)
                .foregroundStyle(AppColor.textPrimary)
            Text(label)
                .appFont(.caption)
                .foregroundStyle(AppColor.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func medicationNeedRow(_ item: (medication: Medication, missedDays: Int)) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: EditorialSpacing.sm) {
            Text(item.medication.name)
                .appFont(.body)
                .foregroundStyle(AppColor.textPrimary)
            Spacer(minLength: EditorialSpacing.md)
            Text(String(format: NSLocalizedString("%lld days missed", comment: "Caregiver missed dose count"), Int64(item.missedDays)))
                .appFontNumeric(.caption)
                .foregroundStyle(AppColor.warning)
        }
        .padding(.vertical, EditorialSpacing.xs)
    }

    private func caregiverRow(_ caregiver: CaregiverContact) -> some View {
        VStack(alignment: .leading, spacing: EditorialSpacing.md) {
            HStack(alignment: .center, spacing: EditorialSpacing.md) {
                Image(systemName: "person")
                    .font(.system(size: 15, weight: .regular))
                    .foregroundStyle(AppColor.primary)
                    .frame(width: 34, height: 34)
                    .background(
                        RoundedRectangle(cornerRadius: EditorialSpacing.sm, style: .continuous)
                            .fill(AppColor.surface)
                            .overlay(
                                RoundedRectangle(cornerRadius: EditorialSpacing.sm, style: .continuous)
                                    .stroke(AppColor.divider, lineWidth: 1)
                            )
                    )

                VStack(alignment: .leading, spacing: EditorialSpacing.xs) {
                    Text(caregiver.name)
                        .appFont(.headline)
                        .foregroundStyle(AppColor.textPrimary)
                    if let phone = caregiver.phone, !phone.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text(phone)
                            .appFontNumeric(.caption)
                            .foregroundStyle(AppColor.textSecondary)
                    }
                }

                Spacer(minLength: EditorialSpacing.sm)

                if let phone = caregiver.phone, !phone.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Button {
                        call(phone)
                    } label: {
                        Image(systemName: "phone")
                            .font(.system(size: 15, weight: .regular))
                            .foregroundStyle(AppColor.primary)
                            .frame(width: 34, height: 34)
                    }
                    .accessibilityLabel(String(format: NSLocalizedString("Call %@", comment: "Caregiver call accessibility"), caregiver.name))
                }

                Button(role: .destructive) {
                    caregiverPendingRemoval = caregiver
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 15, weight: .regular))
                        .foregroundStyle(AppColor.textTertiary)
                        .frame(width: 34, height: 34)
                }
                .accessibilityLabel(String(format: NSLocalizedString("Remove %@", comment: "Caregiver remove accessibility"), caregiver.name))
            }

            Toggle(isOn: notifyBinding(for: caregiver)) {
                Text(NSLocalizedString("Missed-dose support", comment: "Caregiver row toggle"))
                    .appFont(.body)
                    .foregroundStyle(AppColor.textPrimary)
            }
            .tint(AppColor.primary)

            if hasActiveSupport && caregiver.notifyOnMiss {
                if let phone = sanitizedPhone(caregiver.phone) {
                    Button {
                        notifyCaregiver(caregiver, phone: phone)
                    } label: {
                        Label(NSLocalizedString("Notify", comment: "Caregiver row notify action"), systemImage: "message")
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(AppColor.primary)
                } else {
                    quietWarning(NSLocalizedString("Add a phone number to send this person a reminder.", comment: "Caregiver current support note"))
                }
            }
        }
        .padding(.vertical, EditorialSpacing.xs)
    }

    private func quietWarning(_ text: String) -> some View {
        HStack(alignment: .top, spacing: EditorialSpacing.sm) {
            Image(systemName: "exclamationmark.circle")
                .font(.system(size: 13, weight: .regular))
                .foregroundStyle(AppColor.warning)
                .padding(.top, 1)
            Text(text)
                .appFont(.caption)
                .foregroundStyle(AppColor.warning)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func notifyBinding(for caregiver: CaregiverContact) -> Binding<Bool> {
        Binding(
            get: {
                store.caregivers.first(where: { $0.id == caregiver.id })?.notifyOnMiss ?? caregiver.notifyOnMiss
            },
            set: { newValue in
                var updated = caregiver
                updated.notifyOnMiss = newValue
                store.updateCaregiver(updated)
            }
        )
    }

    private func buildSupportUpdate() -> String {
        var lines: [String] = []
        lines.append(NSLocalizedString("Medication support needed", comment: "Caregiver message title"))
        lines.append("")

        if !missedSupportItems.isEmpty {
            lines.append(NSLocalizedString("Missed doses:", comment: "Caregiver message section"))
            for item in missedSupportItems {
                lines.append("• " + String(
                    format: NSLocalizedString("%@ - %lld days missed", comment: "Caregiver message missed dose row"),
                    item.medication.name,
                    Int64(item.missedDays)
                ))
            }
            lines.append("")
        }

        lines.append(NSLocalizedString("Could you check in today and help confirm the medication routine?", comment: "Caregiver message ask"))
        lines.append("")
        lines.append(NSLocalizedString("This is a support reminder, not a medical emergency alert.", comment: "Caregiver message safety note"))

        return lines.joined(separator: "\n")
    }

    private func notifyEnabledCaregivers() {
        let body = buildSupportUpdate()
        let recipients = textableCaregivers.compactMap { sanitizedPhone($0.phone) }
        if !recipients.isEmpty, MFMessageComposeViewController.canSendText() {
            messageDraft = CaregiverMessageDraft(recipients: recipients, body: body)
        } else {
            shareText = body
            showShare = true
        }
    }

    private func notifyCaregiver(_ caregiver: CaregiverContact, phone: String) {
        let body = buildSupportUpdate()
        if MFMessageComposeViewController.canSendText() {
            messageDraft = CaregiverMessageDraft(recipients: [phone], body: body)
        } else {
            shareText = "\(caregiver.name)\n\(body)"
            showShare = true
        }
    }

    private func removeCaregiver(_ caregiver: CaregiverContact) {
        guard let index = store.caregivers.firstIndex(where: { $0.id == caregiver.id }) else { return }
        store.removeCaregiver(at: IndexSet(integer: index))
        Haptics.notification(.warning)
    }

    private func call(_ phone: String) {
        let digits = phone.filter { $0.isNumber || $0 == "+" }
        guard !digits.isEmpty, let url = URL(string: "tel://\(digits)") else { return }
        UIApplication.shared.open(url)
    }

    private func sanitizedPhone(_ phone: String?) -> String? {
        guard let phone else { return nil }
        let digits = phone.filter { $0.isNumber || $0 == "+" }
        return digits.isEmpty ? nil : digits
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
                    Toggle(NSLocalizedString("Include in missed-dose reminders", comment: "Caregiver add toggle"), isOn: $notifyOnMiss)
                } footer: {
                    Text(NSLocalizedString("When medication is missed for 2+ days, the app will prompt you to text this person.", comment: "Caregiver add toggle footer"))
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

private struct CaregiverMessageDraft: Identifiable {
    let id = UUID()
    let recipients: [String]
    let body: String
}

private struct MessageComposeSheet: UIViewControllerRepresentable {
    let recipients: [String]
    let body: String
    @Environment(\.dismiss) private var dismiss

    func makeCoordinator() -> Coordinator {
        Coordinator(dismiss: dismiss)
    }

    func makeUIViewController(context: Context) -> MFMessageComposeViewController {
        let controller = MFMessageComposeViewController()
        controller.messageComposeDelegate = context.coordinator
        controller.recipients = recipients
        controller.body = body
        return controller
    }

    func updateUIViewController(_ uiViewController: MFMessageComposeViewController, context: Context) {}

    final class Coordinator: NSObject, MFMessageComposeViewControllerDelegate {
        private let dismiss: DismissAction

        init(dismiss: DismissAction) {
            self.dismiss = dismiss
        }

        func messageComposeViewController(
            _ controller: MFMessageComposeViewController,
            didFinishWith result: MessageComposeResult
        ) {
            dismiss()
        }
    }
}
