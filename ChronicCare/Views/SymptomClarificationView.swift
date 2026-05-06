import SwiftUI

struct SymptomClarificationView: View {
    @EnvironmentObject private var store: DataStore
    @Environment(\.dismiss) private var dismiss

    let symptom: SymptomEntry

    @State private var onsetDescription = ""
    @State private var relationToMedication: SymptomMedicationRelation = .unknown
    @State private var happenedAfterStanding = false
    @State private var nearbyMeasurementNote = ""
    @State private var selectedRedFlags: Set<SymptomRedFlagSign> = []
    @State private var followUpRelevanceNote = ""
    @State private var didPopulate = false

    private var canSave: Bool {
        clean(onsetDescription) != nil ||
            relationToMedication != .unknown ||
            happenedAfterStanding ||
            clean(nearbyMeasurementNote) != nil ||
            !selectedRedFlags.isEmpty ||
            clean(followUpRelevanceNote) != nil
    }

    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: EditorialSpacing.xs) {
                    Text(symptomTitle)
                        .appFont(.headline)
                        .foregroundStyle(AppColor.textPrimary)
                    Text("\(symptom.severity.displayName) · \(symptom.date.formatted(date: .abbreviated, time: .shortened))")
                        .appFont(.caption)
                        .foregroundStyle(AppColor.textSecondary)
                    if let note = clean(symptom.note) {
                        Text(note)
                            .appFont(.body)
                            .foregroundStyle(AppColor.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.vertical, EditorialSpacing.xxs)
            }

            Section(NSLocalizedString("Timing and context", comment: "Symptom clarification section")) {
                TextField(
                    NSLocalizedString("When did it start or what were you doing?", comment: "Symptom clarification placeholder"),
                    text: $onsetDescription,
                    axis: .vertical
                )
                .lineLimit(2...4)

                Picker(NSLocalizedString("Relation to medication", comment: "Symptom clarification field"), selection: $relationToMedication) {
                    ForEach(SymptomMedicationRelation.allCases) { relation in
                        Text(relation.displayName).tag(relation)
                    }
                }

                Toggle(NSLocalizedString("Happened after standing up", comment: "Symptom clarification field"), isOn: $happenedAfterStanding)
            }

            Section(NSLocalizedString("Nearby measurement", comment: "Symptom clarification section")) {
                TextField(
                    NSLocalizedString("e.g., BP 158/96 20 minutes later", comment: "Symptom clarification placeholder"),
                    text: $nearbyMeasurementNote,
                    axis: .vertical
                )
                .lineLimit(1...3)
            }

            Section {
                ForEach(SymptomRedFlagSign.allCases) { sign in
                    Toggle(sign.displayName, isOn: binding(for: sign))
                }
            } header: {
                Text(NSLocalizedString("Red-flag signs", comment: "Symptom clarification section"))
            } footer: {
                Text(NSLocalizedString("If chest pain, shortness of breath, one-sided weakness, fainting, confusion, or severe symptoms are happening now, seek urgent medical help.", comment: "Symptom clarification safety footer"))
            }

            Section(NSLocalizedString("For the next visit", comment: "Symptom clarification section")) {
                TextField(
                    NSLocalizedString("What should the doctor know about this symptom?", comment: "Symptom clarification placeholder"),
                    text: $followUpRelevanceNote,
                    axis: .vertical
                )
                .lineLimit(2...4)
            }
        }
        .scrollContentBackground(.hidden)
        .background(AppColor.background)
        .navigationTitle(NSLocalizedString("Clarify Symptom", comment: "Symptom clarification title"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button(NSLocalizedString("Save", comment: "")) {
                    save()
                }
                .disabled(!canSave)
            }
        }
        .onAppear {
            populateIfNeeded()
        }
    }

    private var symptomTitle: String {
        symptom.tags.isEmpty ? NSLocalizedString("Symptom", comment: "Symptom fallback") : symptom.tags.joined(separator: ", ")
    }

    private func binding(for sign: SymptomRedFlagSign) -> Binding<Bool> {
        Binding(
            get: { selectedRedFlags.contains(sign) },
            set: { isSelected in
                if isSelected {
                    selectedRedFlags.insert(sign)
                } else {
                    selectedRedFlags.remove(sign)
                }
            }
        )
    }

    private func populateIfNeeded() {
        guard !didPopulate else { return }
        if let clarification = store.clarification(for: symptom.id) {
            onsetDescription = clarification.onsetDescription ?? ""
            relationToMedication = clarification.relationToMedication
            happenedAfterStanding = clarification.happenedAfterStanding
            nearbyMeasurementNote = clarification.nearbyMeasurementNote ?? ""
            selectedRedFlags = Set(clarification.redFlagSigns)
            followUpRelevanceNote = clarification.followUpRelevanceNote ?? ""
        }
        didPopulate = true
    }

    private func save() {
        let existing = store.clarification(for: symptom.id)
        let now = Date()
        let clarification = SymptomClarification(
            id: existing?.id ?? UUID(),
            symptomEntryID: symptom.id,
            onsetDescription: clean(onsetDescription),
            relationToMedication: relationToMedication,
            happenedAfterStanding: happenedAfterStanding,
            nearbyMeasurementNote: clean(nearbyMeasurementNote),
            redFlagSigns: selectedRedFlags.sorted { $0.rawValue < $1.rawValue },
            followUpRelevanceNote: clean(followUpRelevanceNote),
            createdAt: existing?.createdAt ?? now,
            updatedAt: now
        )
        store.upsertSymptomClarification(clarification)
        store.refreshAgentInbox()
        Haptics.success()
        dismiss()
    }

    private func clean(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }
}

#Preview {
    NavigationStack {
        SymptomClarificationView(
            symptom: SymptomEntry(
                date: Date(),
                tags: ["Dizziness"],
                severity: .moderate,
                note: nil
            )
        )
        .environmentObject(DataStore())
    }
}
