import SwiftUI

struct MedicationsView: View {
    @EnvironmentObject var store: DataStore
    @State private var showAdd = false
    @State private var editTarget: Medication? = nil

    var body: some View {
        NavigationStack {
            List {
                if store.medications.isEmpty {
                    Text("No medications added")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(store.medications) { med in
                        HStack {
                            VStack(alignment: .leading) {
                                Text(med.name).font(.headline)
                                Text(med.dose).font(.subheadline).foregroundStyle(.secondary)
                                if let h = med.timeOfDay.hour, let m = med.timeOfDay.minute {
                                    Text(String(format: "%02d:%02d", h, m))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            Toggle(isOn: Binding(
                                get: { med.remindersEnabled },
                                set: { newVal in
                                    var updated = med
                                    updated.remindersEnabled = newVal
                                    store.updateMedication(updated)
                                    if newVal { NotificationManager.shared.schedule(for: updated); Haptics.impact(.light) }
                                    else { NotificationManager.shared.cancelAll(for: updated); Haptics.impact(.light) }
                                })) {
                                Text("Remind")
                            }
                            .labelsHidden()
                        }
                        .contentShape(Rectangle())
                        .onTapGesture { editTarget = med }
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button {
                                store.logIntake(medicationID: med.id, status: .taken)
                                Haptics.success()
                            } label: {
                                Label("Taken", systemImage: "checkmark")
                            }.tint(.green)
                            Button {
                                store.logIntake(medicationID: med.id, status: .skipped)
                            } label: {
                                Label("Skip", systemImage: "xmark")
                            }.tint(.red)
                        }
                    }
                    .onDelete { idx in
                        let items = idx.map { store.medications[$0] }
                        items.forEach { NotificationManager.shared.cancelAll(for: $0) }
                        store.removeMedication(at: idx)
                    }
                }
            }
            .navigationTitle("Medications")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showAdd = true } label: { Image(systemName: "plus") }
                }
            }
            .sheet(isPresented: $showAdd) {
                AddMedicationView { med in
                    store.addMedication(med)
                    if med.remindersEnabled { NotificationManager.shared.schedule(for: med) }
                }
            }
            .sheet(item: $editTarget) { med in
                EditMedicationView(medication: med) { updated in
                    store.updateMedication(updated)
                    if updated.remindersEnabled { NotificationManager.shared.schedule(for: updated) }
                    else { NotificationManager.shared.cancelAll(for: updated) }
                }
            }
        }
    }
}

struct AddMedicationView: View {
    var onSave: (Medication) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var name: String = ""
    @State private var dose: String = ""
    @State private var notes: String = ""
    @State private var time: Date = Date()
    @State private var remindersEnabled: Bool = true

    var body: some View {
        NavigationStack {
            Form {
                Section("Basic") {
                    TextField("Name", text: $name)
                    TextField("Dose", text: $dose)
                    TextField("Notes (optional)", text: $notes)
                }
                Section("Schedule") {
                    DatePicker("Time", selection: $time, displayedComponents: .hourAndMinute)
                    Toggle("Enable Reminder", isOn: $remindersEnabled)
                }
            }
            .navigationTitle("Add Medication")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let comps = Calendar.current.dateComponents([.hour, .minute], from: time)
                        let med = Medication(
                            name: name,
                            dose: dose,
                            notes: notes.isEmpty ? nil : notes,
                            timeOfDay: comps,
                            remindersEnabled: remindersEnabled
                        )
                        onSave(med)
                        Haptics.success()
                        dismiss()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}

struct EditMedicationView: View {
    var medication: Medication
    var onSave: (Medication) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var name: String = ""
    @State private var dose: String = ""
    @State private var notes: String = ""
    @State private var time: Date = Date()
    @State private var remindersEnabled: Bool = true

    init(medication: Medication, onSave: @escaping (Medication) -> Void) {
        self.medication = medication
        self.onSave = onSave
        // State will be initialized in .onAppear to avoid SwiftUI init warnings
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Basic") {
                    TextField("Name", text: $name)
                    TextField("Dose", text: $dose)
                    TextField("Notes (optional)", text: $notes)
                }
                Section("Schedule") {
                    DatePicker("Time", selection: $time, displayedComponents: .hourAndMinute)
                    Toggle("Enable Reminder", isOn: $remindersEnabled)
                }
            }
            .navigationTitle("Edit Medication")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                name = medication.name
                dose = medication.dose
                notes = medication.notes ?? ""
                if let h = medication.timeOfDay.hour, let m = medication.timeOfDay.minute {
                    let cal = Calendar.current
                    time = cal.date(bySettingHour: h, minute: m, second: 0, of: Date()) ?? Date()
                }
                remindersEnabled = medication.remindersEnabled
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let comps = Calendar.current.dateComponents([.hour, .minute], from: time)
                        var updated = medication
                        updated.name = name
                        updated.dose = dose
                        updated.notes = notes.isEmpty ? nil : notes
                        updated.timeOfDay = comps
                        updated.remindersEnabled = remindersEnabled
                        onSave(updated)
                        Haptics.success()
                        dismiss()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}

#Preview {
    MedicationsView().environmentObject(DataStore())
}
