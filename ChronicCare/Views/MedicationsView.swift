import SwiftUI
import PhotosUI
import UIKit

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
                        HStack(spacing: 12) {
                            if let path = med.imagePath, let ui = loadMedImage(path: path) {
                                Image(uiImage: ui)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 44, height: 44)
                                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                            }
                            VStack(alignment: .leading) {
                                Text(med.name).font(.headline)
                                Text(med.dose).font(.subheadline).foregroundStyle(.secondary)
                                if !med.timesOfDay.isEmpty {
                                    let times = med.timesOfDay.compactMap { comps -> String? in
                                        guard let h = comps.hour, let m = comps.minute else { return nil }
                                        return String(format: "%02d:%02d", h, m)
                                    }.joined(separator: ", ")
                                    Text(times)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                if let latest = latestTodayAction(for: med) {
                                    switch latest.0 {
                                    case .taken:
                                        (Text(NSLocalizedString("Taken ", comment: "")) + Text(latest.1, style: .relative))
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    case .skipped:
                                        (Text(NSLocalizedString("Skipped ", comment: "")) + Text(latest.1, style: .relative))
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    case .snoozed:
                                        (Text(NSLocalizedString("Snoozed ", comment: "")) + Text(latest.1, style: .relative))
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                if let cat = med.category, cat != .unspecified {
                                    let eff = store.effectiveness(for: med)
                                    HStack(spacing: 6) {
                                        Text(cat.displayName).font(.caption2).foregroundStyle(.secondary)
                                        Text(effectLabel(for: eff)).font(.caption2)
                                            .foregroundStyle(effectColor(for: eff))
                                        if eff.confidence > 0 {
                                            Text(String(format: NSLocalizedString("Confidence: %d%%", comment: ""), eff.confidence))
                                                .font(.caption2)
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                }
                            }
                            Spacer()
                            Toggle(isOn: Binding(
                                get: { med.remindersEnabled },
                                set: { newVal in
                                    var updated = med
                                    updated.remindersEnabled = newVal
                                    store.updateMedication(updated)
                                    if newVal {
                                        NotificationManager.shared.schedule(for: updated)
                                        NotificationManager.shared.updateBadge(store: store)
                                        Haptics.impact(.light)
                                    } else {
                                        NotificationManager.shared.cancelAll(for: updated)
                                        NotificationManager.shared.updateBadge(store: store)
                                        Haptics.impact(.light)
                                    }
                                })) {
                                Text("Remind")
                            }
                            .labelsHidden()
                        }
                        .contentShape(Rectangle())
                        .onTapGesture { editTarget = med }
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button {
                                store.upsertIntake(medicationID: med.id, status: .skipped, scheduleTime: nil)
                                NotificationManager.shared.updateBadge(store: store)
                                Haptics.impact(.light)
                            } label: {
                                Label("Skip", systemImage: "xmark")
                            }.tint(.red)
                        }
                    }
                    .onDelete { idx in
                        let items = idx.map { store.medications[$0] }
                        items.forEach {
                            NotificationManager.shared.cancelAll(for: $0)
                            removeMedImage(path: $0.imagePath)
                        }
                        store.removeMedication(at: idx)
                    }
                }
            }
            .navigationTitle("Medications")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { EditButton() }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showAdd = true } label: { Image(systemName: "plus") }
                }
            }
            .sheet(isPresented: $showAdd) {
                AddMedicationView { med in
                    store.addMedication(med)
                    if med.remindersEnabled {
                        NotificationManager.shared.schedule(for: med)
                        NotificationManager.shared.updateBadge(store: store)
                    }
                }
            }
            .sheet(item: $editTarget) { med in
                EditMedicationView(medication: med, onSave: { updated in
                    store.updateMedication(updated)
                    if updated.remindersEnabled {
                        NotificationManager.shared.schedule(for: updated)
                        NotificationManager.shared.updateBadge(store: store)
                    } else {
                        NotificationManager.shared.cancelAll(for: updated)
                        NotificationManager.shared.updateBadge(store: store)
                    }
                }, onDelete: {
                    if let idx = store.medications.firstIndex(where: { $0.id == med.id }) {
                        NotificationManager.shared.cancelAll(for: med)
                        removeMedImage(path: med.imagePath)
                        store.removeMedication(at: IndexSet(integer: idx))
                        NotificationManager.shared.updateBadge(store: store)
                    }
                })
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
    @State private var times: [Date] = [Date()]
    @State private var remindersEnabled: Bool = true
    @State private var category: MedicationCategory = .unspecified
    @State private var pickedItem: PhotosPickerItem? = nil
    @State private var pickedImage: UIImage? = nil

    var body: some View {
        NavigationStack {
            Form {
                Section("Basic") {
                    TextField("Name", text: $name)
                    TextField("Dose", text: $dose)
                    TextField("Notes (optional)", text: $notes)
                    Picker("Category", selection: $category) {
                        ForEach(MedicationCategory.allCases) { c in Text(c.displayName).tag(c) }
                    }
                    HStack {
                        if let img = pickedImage {
                            Image(uiImage: img)
                                .resizable()
                                .scaledToFill()
                                .frame(width: 56, height: 56)
                                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        } else {
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .strokeBorder(.secondary.opacity(0.3))
                                .frame(width: 56, height: 56)
                                .overlay(Image(systemName: "photo").foregroundStyle(.secondary))
                        }
                        PhotosPicker(selection: $pickedItem, matching: .images) {
                            Text("Choose Photo")
                        }
                        .onChange(of: pickedItem) { newItem in
                            Task { if let data = try? await newItem?.loadTransferable(type: Data.self), let ui = UIImage(data: data) { pickedImage = ui } }
                        }
                        if pickedImage != nil {
                            Button(role: .destructive) { pickedImage = nil } label: { Text("Remove") }
                        }
                    }
                }
                Section("Schedule") {
                    ForEach(times.indices, id: \.self) { idx in
                        DatePicker("Time \(idx+1)", selection: $times[idx], displayedComponents: .hourAndMinute)
                    }
                    .onDelete { idx in times.remove(atOffsets: idx) }
                    Button { times.append(Date()) } label: { Label("Add Time", systemImage: "plus.circle") }
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
                        let comps = times.map { Calendar.current.dateComponents([.hour, .minute], from: $0) }
                        // Prepare image path
                        var imagePath: String? = nil
                        let newID = UUID()
                        if let img = pickedImage, let path = saveMedImage(image: img, id: newID) { imagePath = path }
                        let med = Medication(
                            id: newID,
                            name: name,
                            dose: dose,
                            notes: notes.isEmpty ? nil : notes,
                            timesOfDay: comps,
                            remindersEnabled: remindersEnabled,
                            category: category,
                            imagePath: imagePath
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
    var onDelete: (() -> Void)? = nil
    @Environment(\.dismiss) private var dismiss

    @State private var name: String = ""
    @State private var dose: String = ""
    @State private var notes: String = ""
    @State private var times: [Date] = []
    @State private var remindersEnabled: Bool = true
    @State private var category: MedicationCategory = .unspecified
    @State private var pickedItem: PhotosPickerItem? = nil
    @State private var pickedImage: UIImage? = nil
    @State private var removePhoto: Bool = false

    init(medication: Medication, onSave: @escaping (Medication) -> Void, onDelete: (() -> Void)? = nil) {
        self.medication = medication
        self.onSave = onSave
        self.onDelete = onDelete
        // State will be initialized in .onAppear to avoid SwiftUI init warnings
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Basic") {
                    TextField("Name", text: $name)
                    TextField("Dose", text: $dose)
                    TextField("Notes (optional)", text: $notes)
                    Picker("Category", selection: $category) {
                        ForEach(MedicationCategory.allCases) { c in Text(c.displayName).tag(c) }
                    }
                    HStack {
                        if let img = pickedImage ?? loadMedImage(path: medication.imagePath) {
                            Image(uiImage: img)
                                .resizable()
                                .scaledToFill()
                                .frame(width: 56, height: 56)
                                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        } else {
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .strokeBorder(.secondary.opacity(0.3))
                                .frame(width: 56, height: 56)
                                .overlay(Image(systemName: "photo").foregroundStyle(.secondary))
                        }
                        PhotosPicker(selection: $pickedItem, matching: .images) { Text("Choose Photo") }
                            .onChange(of: pickedItem) { newItem in
                                Task { if let data = try? await newItem?.loadTransferable(type: Data.self), let ui = UIImage(data: data) { pickedImage = ui; removePhoto = false } }
                            }
                        if pickedImage != nil || medication.imagePath != nil {
                            Button(role: .destructive) { pickedImage = nil; removePhoto = true } label: { Text("Remove") }
                        }
                    }
                }
                Section("Schedule") {
                    ForEach(times.indices, id: \.self) { idx in
                        DatePicker("Time \(idx+1)", selection: $times[idx], displayedComponents: .hourAndMinute)
                    }
                    .onDelete { idx in times.remove(atOffsets: idx) }
                    Button { times.append(Date()) } label: { Label("Add Time", systemImage: "plus.circle") }
                    Toggle("Enable Reminder", isOn: $remindersEnabled)
                }
            }
            .navigationTitle("Edit Medication")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                name = medication.name
                dose = medication.dose
                notes = medication.notes ?? ""
                let cal = Calendar.current
                times = medication.timesOfDay.compactMap { comps in
                    guard let h = comps.hour, let m = comps.minute else { return nil }
                    return cal.date(bySettingHour: h, minute: m, second: 0, of: Date()) ?? Date()
                }
                if times.isEmpty { times = [Date()] }
                remindersEnabled = medication.remindersEnabled
                category = medication.category ?? .unspecified
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let comps = times.map { Calendar.current.dateComponents([.hour, .minute], from: $0) }
                        var updated = medication
                        updated.name = name
                        updated.dose = dose
                        updated.notes = notes.isEmpty ? nil : notes
                        updated.timesOfDay = comps
                        updated.remindersEnabled = remindersEnabled
                        updated.category = category
                        if removePhoto {
                            removeMedImage(path: updated.imagePath)
                            updated.imagePath = nil
                        } else if let img = pickedImage {
                            updated.imagePath = saveMedImage(image: img, id: updated.id)
                        }
                        onSave(updated)
                        Haptics.success()
                        dismiss()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .safeAreaInset(edge: .bottom) {
                if onDelete != nil {
                    Button(role: .destructive) {
                        onDelete?()
                        dismiss()
                    } label: {
                        Label("Delete Medication", systemImage: "trash")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                    .padding()
                }
            }
        }
    }
}

private func effectLabel(for result: MedicationEffectResult) -> String {
    switch result.verdict {
    case .likelyEffective: return NSLocalizedString("Likely effective", comment: "")
    case .unclear: return NSLocalizedString("Unclear", comment: "")
    case .likelyIneffective: return NSLocalizedString("Likely ineffective", comment: "")
    case .notApplicable: return NSLocalizedString("N/A", comment: "")
    }
}

private func effectColor(for result: MedicationEffectResult) -> Color {
    switch result.verdict {
    case .likelyEffective: return .green
    case .unclear: return .secondary
    case .likelyIneffective: return .red
    case .notApplicable: return .secondary
    }
}

#Preview {
    MedicationsView().environmentObject(DataStore())
}

// MARK: - Image helpers
private extension MedicationsView {
    func latestTodayAction(for med: Medication) -> (IntakeStatus, Date)? {
        let cal = Calendar.current
        let start = cal.startOfDay(for: Date())
        let end = cal.date(byAdding: .day, value: 1, to: start)!
        let logs = store.intakeLogs
            .filter { $0.medicationID == med.id && $0.date >= start && $0.date < end }
            .sorted { $0.date > $1.date }
        guard let last = logs.first else { return nil }
        return (last.status, last.date)
    }
}

private func medImagesDir() -> URL {
    let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
    let dir = docs.appendingPathComponent("med_images", conformingTo: .directory)
    if !FileManager.default.fileExists(atPath: dir.path) {
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }
    // Exclude directory from iCloud backups
    try? (dir as NSURL).setResourceValue(true, forKey: .isExcludedFromBackupKey)
    return dir
}

private func saveMedImage(image: UIImage, id: UUID) -> String? {
    let url = medImagesDir().appendingPathComponent("\(id.uuidString).jpg")
    guard let data = image.jpegData(compressionQuality: 0.9) else { return nil }
    do {
        try data.write(to: url, options: [.atomic, .completeFileProtection])
        try? (url as NSURL).setResourceValue(true, forKey: .isExcludedFromBackupKey)
        return "med_images/\(id.uuidString).jpg"
    } catch { return nil }
}

private func loadMedImage(path: String?) -> UIImage? {
    guard let path = path else { return nil }
    let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
    let url = docs.appendingPathComponent(path)
    return UIImage(contentsOfFile: url.path)
}

private func removeMedImage(path: String?) {
    guard let path = path else { return }
    let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
    let url = docs.appendingPathComponent(path)
    try? FileManager.default.removeItem(at: url)
}
