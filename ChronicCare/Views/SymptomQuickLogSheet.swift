import SwiftUI

/// Quick symptom logger — the patient-side data HIS doesn't capture.
/// Designed to be filled in under 15 seconds: preset chips + severity + optional note.
struct SymptomQuickLogSheet: View {
    @EnvironmentObject var store: DataStore
    @Environment(\.dismiss) private var dismiss

    /// When editing an existing entry; nil = creating a new one.
    var editing: SymptomEntry?

    @State private var selectedTags: Set<String> = []
    @State private var customTag: String = ""
    @State private var severity: SymptomSeverity = .mild
    @State private var note: String = ""
    @State private var date: Date = Date()
    @State private var relatedMedicationIDs: Set<UUID> = []
    @State private var showMedicationPicker = false

    private static let presetTags: [String] = [
        NSLocalizedString("Dizziness", comment: "Symptom: 头晕"),
        NSLocalizedString("Abdominal pain", comment: "Symptom: 腹痛"),
        NSLocalizedString("Insomnia", comment: "Symptom: 失眠"),
        NSLocalizedString("Rash", comment: "Symptom: 皮疹"),
        NSLocalizedString("Chest tightness", comment: "Symptom: 胸闷"),
        NSLocalizedString("Wheezing", comment: "Symptom: 喘息")
    ]

    private var canSave: Bool {
        !selectedTags.isEmpty || !customTag.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    FlowLayout(spacing: 8) {
                        ForEach(Self.presetTags, id: \.self) { tag in
                            tagChip(tag, isSelected: selectedTags.contains(tag)) {
                                toggleTag(tag)
                            }
                        }
                    }
                    HStack {
                        TextField(NSLocalizedString("Other (type here)", comment: "Custom symptom input"), text: $customTag)
                        if !customTag.trimmingCharacters(in: .whitespaces).isEmpty {
                            Button {
                                let trimmed = customTag.trimmingCharacters(in: .whitespaces)
                                if !trimmed.isEmpty { selectedTags.insert(trimmed) }
                                customTag = ""
                            } label: {
                                Image(systemName: "plus.circle.fill")
                                    .foregroundStyle(AppColor.primary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    if !selectedTags.isEmpty {
                        FlowLayout(spacing: 6) {
                            ForEach(Array(selectedTags), id: \.self) { tag in
                                selectedChip(tag)
                            }
                        }
                    }
                } header: {
                    Text(NSLocalizedString("Symptoms", comment: "Symptom sheet section header"))
                } footer: {
                    Text(NSLocalizedString("Tap to pick one or more. Your doctor will see this during your next visit.", comment: ""))
                }

                Section(NSLocalizedString("Severity", comment: "")) {
                    Picker(NSLocalizedString("Severity", comment: ""), selection: $severity) {
                        ForEach(SymptomSeverity.allCases) { level in
                            Text(level.displayName).tag(level)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                Section(NSLocalizedString("When", comment: "Time of symptom")) {
                    DatePicker(NSLocalizedString("Occurred", comment: ""), selection: $date, in: ...Date(), displayedComponents: [.date, .hourAndMinute])
                }

                Section {
                    TextField(NSLocalizedString("e.g., after lunch, lasted 30 minutes", comment: "Symptom note placeholder"), text: $note, axis: .vertical)
                        .lineLimit(2...5)
                } header: {
                    Text(NSLocalizedString("Notes (optional)", comment: ""))
                }

                Section {
                    Button {
                        showMedicationPicker = true
                    } label: {
                        HStack {
                            Text(NSLocalizedString("Suspected medication", comment: ""))
                            Spacer()
                            Text(relatedMedicationSummary)
                                .foregroundStyle(AppColor.textSecondary)
                                .lineLimit(1)
                        }
                    }
                } footer: {
                    Text(NSLocalizedString("If you think a medication might have caused this, link it here. Optional.", comment: ""))
                }
            }
            .scrollContentBackground(.hidden)
            .background(AppColor.background)
            .navigationTitle(editing == nil
                             ? NSLocalizedString("Log Symptom", comment: "")
                             : NSLocalizedString("Edit Symptom", comment: ""))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(NSLocalizedString("Cancel", comment: "")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(NSLocalizedString("Save", comment: "")) { save() }
                        .disabled(!canSave)
                }
            }
            .onAppear {
                if let editing {
                    selectedTags = Set(editing.tags)
                    severity = editing.severity
                    note = editing.note ?? ""
                    date = editing.date
                    relatedMedicationIDs = Set(editing.relatedMedicationIDs ?? [])
                }
            }
            .sheet(isPresented: $showMedicationPicker) {
                medicationPickerSheet
            }
        }
    }

    private var relatedMedicationSummary: String {
        if relatedMedicationIDs.isEmpty {
            return NSLocalizedString("None", comment: "")
        }
        let names = store.medications
            .filter { relatedMedicationIDs.contains($0.id) }
            .map(\.name)
        return names.joined(separator: ", ")
    }

    private func toggleTag(_ tag: String) {
        if selectedTags.contains(tag) {
            selectedTags.remove(tag)
        } else {
            selectedTags.insert(tag)
        }
    }

    private func tagChip(_ text: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(text)
                .appFont(.subheadline)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(
                    RoundedRectangle(cornerRadius: EditorialSpacing.sm, style: .continuous)
                        .fill(AppColor.surface)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: EditorialSpacing.sm, style: .continuous)
                        .stroke(isSelected ? AppColor.primary : AppColor.divider, lineWidth: 1)
                )
                .foregroundStyle(isSelected ? AppColor.primary : AppColor.textPrimary)
        }
        .buttonStyle(.plain)
    }

    private func selectedChip(_ tag: String) -> some View {
        HStack(spacing: 4) {
            Text(tag).appFont(.caption)
            Button {
                selectedTags.remove(tag)
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(AppColor.textSecondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: EditorialSpacing.sm, style: .continuous)
                .fill(AppColor.surface)
                .overlay(
                    RoundedRectangle(cornerRadius: EditorialSpacing.sm, style: .continuous)
                        .stroke(AppColor.divider, lineWidth: 1)
                )
        )
    }

    @ViewBuilder
    private var medicationPickerSheet: some View {
        NavigationStack {
            List {
                if store.medications.isEmpty {
                    Text(NSLocalizedString("No medications to choose from.", comment: ""))
                        .foregroundStyle(AppColor.textSecondary)
                } else {
                    ForEach(store.medications) { med in
                        medicationPickerRow(med)
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(AppColor.background)
            .navigationTitle(NSLocalizedString("Suspected medication", comment: ""))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(NSLocalizedString("Done", comment: "")) { showMedicationPicker = false }
                }
            }
        }
    }

    @ViewBuilder
    private func medicationPickerRow(_ med: Medication) -> some View {
        let isSelected = relatedMedicationIDs.contains(med.id)
        Button {
            if isSelected {
                relatedMedicationIDs.remove(med.id)
            } else {
                relatedMedicationIDs.insert(med.id)
            }
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(med.name).foregroundStyle(AppColor.textPrimary)
                    if !med.dose.isEmpty {
                        Text(med.dose)
                            .appFont(.caption)
                            .foregroundStyle(AppColor.textSecondary)
                    }
                }
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark").foregroundStyle(AppColor.primary)
                }
            }
        }
    }

    private func save() {
        let trimmedCustom = customTag.trimmingCharacters(in: .whitespaces)
        var tags = Array(selectedTags)
        if !trimmedCustom.isEmpty && !tags.contains(trimmedCustom) {
            tags.append(trimmedCustom)
        }
        guard !tags.isEmpty else { return }
        let trimmedNote = note.trimmingCharacters(in: .whitespacesAndNewlines)
        let ids = relatedMedicationIDs.isEmpty ? nil : Array(relatedMedicationIDs)
        let entry = SymptomEntry(
            id: editing?.id ?? UUID(),
            date: date,
            tags: tags,
            severity: severity,
            note: trimmedNote.isEmpty ? nil : trimmedNote,
            relatedMedicationIDs: ids
        )
        if editing != nil {
            store.updateSymptomEntry(entry)
        } else {
            store.addSymptomEntry(entry)
        }
        dismiss()
    }
}
