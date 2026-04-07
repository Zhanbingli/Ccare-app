import SwiftUI
import PhotosUI
import UIKit
import UserNotifications
import Charts

struct MedicationsView: View {
    @EnvironmentObject var store: DataStore
    @State private var scrollProxy: ScrollViewProxy?
    @State private var showAdd = false
    @State private var editTarget: Medication? = nil
    @State private var showNotificationDeniedAlert = false
    @State private var deniedMedName: String? = nil
    @State private var notificationStatus: UNAuthorizationStatus = .notDetermined
    @State private var searchText: String = ""
    @State private var filter: MedFilter = .all
    @State private var scrollToMedicationID: UUID? = nil

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                List {
                    Section {
                        VStack(alignment: .leading, spacing: 12) {
                            summaryCard
                            filterChips
                        }
                    }
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)

                    if notificationStatus == .denied {
                        Section {
                            HStack(alignment: .top, spacing: 12) {
                                Image(systemName: "bell.slash.fill").foregroundStyle(.orange)
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(NSLocalizedString("Notifications Disabled", comment: "")).appFont(.subheadline)
                                    Text(NSLocalizedString("Turn notifications on in Settings to receive medication reminders.", comment: "")).appFont(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                        .listRowSeparator(.hidden)
                    }
                    if filteredMedications.isEmpty {
                        Text(NSLocalizedString("No medications added", comment: ""))
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(filteredMedications) { med in
                            medicationCard(for: med)
                                .listRowSeparator(.hidden)
                                .listRowBackground(Color.clear)
                                .id(med.id)
                        }
                    }
                }
                .listStyle(.plain)
                .listRowSeparator(.hidden)
                .listSectionSeparator(.hidden)
                .onAppear { scrollProxy = proxy }
                .onChange(of: store.medications.count) { _ in scrollProxy = proxy }
            }
            .navigationTitle("Medications")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showAdd = true } label: { Image(systemName: "plus") }
                }
            }
            .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always), prompt: NSLocalizedString("Search medications", comment: ""))
            .sheet(isPresented: $showAdd) {
                AddMedicationView { med in
                    store.addMedication(med)
                    if med.remindersEnabled {
                        NotificationManager.shared.schedule(for: med)
                        NotificationManager.shared.updateBadge(store: store)
                    }
                    refreshNotificationStatus()
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
                    refreshNotificationStatus()
                }, onDelete: {
                    if let idx = store.medications.firstIndex(where: { $0.id == med.id }) {
                        NotificationManager.shared.cancelAll(for: med)
                        removeMedImage(path: med.imagePath)
                        store.removeMedication(at: IndexSet(integer: idx))
                        NotificationManager.shared.updateBadge(store: store)
                        refreshNotificationStatus()
                    }
                })
            }
            .onAppear(perform: refreshNotificationStatus)
            .onChange(of: store.medications.count) { _ in refreshNotificationStatus() }
            .onChange(of: scrollToMedicationID) { target in
                if let id = target {
                    withAnimation {
                        scrollProxy?.scrollTo(id, anchor: .top)
                    }
                    scrollToMedicationID = nil
                }
            }
            .alert(isPresented: $showNotificationDeniedAlert) {
                let message = deniedMedName.map { String(format: NSLocalizedString("Enable notifications in Settings to get reminders for %@.", comment: ""), $0) } ?? NSLocalizedString("Enable notifications in Settings to get reminders.", comment: "")
                return Alert(
                    title: Text(NSLocalizedString("Notifications Disabled", comment: "")),
                    message: Text(message),
                    primaryButton: .default(Text(NSLocalizedString("Open Settings", comment: ""))) {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                    },
                    secondaryButton: .cancel()
                )
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
    @State private var times: [Date] = []
    @State private var remindersEnabled: Bool = true
    @State private var category: MedicationCategory = .unspecified
    @State private var customCategoryName: String = ""
    @State private var pickedItem: PhotosPickerItem? = nil
    @State private var pickedImage: UIImage? = nil
    @State private var showScheduleAlert = false
    @State private var trackSupply: Bool = false
    @State private var pillsRemaining: Int = 30
    @State private var pillsPerDose: Int = 1
    @State private var foodInstruction: FoodInstruction?
    @State private var isAsNeeded: Bool = false
    @State private var hasCourseEnd: Bool = false
    @State private var courseEndDate: Date = Calendar.current.date(byAdding: .day, value: 7, to: Date()) ?? Date()
    @State private var specialInstructions: String = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(NSLocalizedString("Medication Name", comment: ""), text: $name)
                        .appFont(.headline)
                    TextField(NSLocalizedString("Dose (e.g. 500mg)", comment: ""), text: $dose)
                        .appFont(.headline)
                } header: {
                    Text(NSLocalizedString("What are you taking?", comment: ""))
                }
                Section {
                    if times.isEmpty {
                        Text(NSLocalizedString("Tap Add Time to set when you take this", comment: ""))
                            .appFont(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(times.indices, id: \.self) { idx in
                            HStack {
                                DatePicker("Time \(idx+1)", selection: $times[idx], displayedComponents: .hourAndMinute)
                                Button(role: .destructive) {
                                    times.remove(at: idx)
                                } label: {
                                    Image(systemName: "minus.circle.fill")
                                        .font(.title3)
                                        .foregroundStyle(.red)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    Button { times.append(Date()) } label: {
                        Label(NSLocalizedString("Add Time", comment: ""), systemImage: "plus.circle")
                            .appFont(.subheadline)
                    }
                    Toggle(NSLocalizedString("Remind Me", comment: ""), isOn: $remindersEnabled)
                        .appFont(.subheadline)
                    if remindersEnabled && times.isEmpty {
                        Label(NSLocalizedString("Add at least one time for reminders", comment: ""), systemImage: "exclamationmark.triangle")
                            .appFont(.caption)
                            .foregroundStyle(.orange)
                    }
                } header: {
                    Text(NSLocalizedString("When do you take it?", comment: ""))
                }

                Section {
                    DisclosureGroup(NSLocalizedString("More Options", comment: "")) {
                        TextField(NSLocalizedString("Notes (optional)", comment: ""), text: $notes)

                        Toggle(NSLocalizedString("Track Supply", comment: ""), isOn: $trackSupply)
                        if trackSupply {
                            Stepper(value: $pillsRemaining, in: 0...999) {
                                Text(String(format: NSLocalizedString("Pills remaining: %lld", comment: ""), pillsRemaining))
                            }
                            Stepper(value: $pillsPerDose, in: 1...10) {
                                Text(String(format: NSLocalizedString("Pills per dose: %lld", comment: ""), pillsPerDose))
                            }
                        }

                        Picker(NSLocalizedString("Category", comment: ""), selection: $category) {
                            ForEach(MedicationCategory.allCases) { c in Text(c.displayName).tag(c) }
                        }
                        if category == .custom {
                            TextField(NSLocalizedString("Custom Category", comment: ""), text: $customCategoryName)
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
                                Text(NSLocalizedString("Choose Photo", comment: ""))
                            }
                            .onChange(of: pickedItem) { newItem in
                                Task { if let data = try? await newItem?.loadTransferable(type: Data.self), let ui = UIImage(data: data) { pickedImage = ui } }
                            }
                            if pickedImage != nil {
                                Button(role: .destructive) { pickedImage = nil } label: { Text(NSLocalizedString("Remove", comment: "")) }
                            }
                        }

                        Picker(NSLocalizedString("Food Instruction", comment: ""), selection: $foodInstruction) {
                            Text(NSLocalizedString("None", comment: "")).tag(FoodInstruction?.none)
                            ForEach(FoodInstruction.allCases) { f in
                                Text(f.displayName).tag(Optional(f))
                            }
                        }

                        Toggle(NSLocalizedString("As Needed (PRN)", comment: ""), isOn: $isAsNeeded)

                        Toggle(NSLocalizedString("Has Course End Date", comment: ""), isOn: $hasCourseEnd)
                        if hasCourseEnd {
                            DatePicker(NSLocalizedString("End Date", comment: ""), selection: $courseEndDate, displayedComponents: .date)
                        }

                        TextField(NSLocalizedString("Special Instructions", comment: ""), text: $specialInstructions)
                    }
                }
            }
            .navigationTitle(NSLocalizedString("Add Medication", comment: ""))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        if remindersEnabled && times.isEmpty {
                            showScheduleAlert = true
                            return
                        }
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
                            customCategoryName: category == .custom ? customCategoryName.trimmingCharacters(in: .whitespacesAndNewlines) : nil,
                            imagePath: imagePath,
                            pillsRemaining: trackSupply ? pillsRemaining : nil,
                            pillsPerDose: trackSupply ? pillsPerDose : nil,
                            foodInstruction: foodInstruction,
                            isAsNeeded: isAsNeeded ? true : nil,
                            courseEndDate: hasCourseEnd ? courseEndDate : nil,
                            specialInstructions: specialInstructions.isEmpty ? nil : specialInstructions
                        )
                        onSave(med)
                        Haptics.success()
                        dismiss()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .alert(NSLocalizedString("No Schedule Set", comment: ""), isPresented: $showScheduleAlert) {
                Button(NSLocalizedString("Add Time", comment: "")) { times.append(Date()) }
                Button(NSLocalizedString("Save Without Reminders", comment: "")) {
                    remindersEnabled = false
                    let comps = times.map { Calendar.current.dateComponents([.hour, .minute], from: $0) }
                    var imagePath: String? = nil
                    let newID = UUID()
                    if let img = pickedImage, let path = saveMedImage(image: img, id: newID) { imagePath = path }
                    let med = Medication(
                        id: newID,
                        name: name,
                        dose: dose,
                        notes: notes.isEmpty ? nil : notes,
                        timesOfDay: comps,
                        remindersEnabled: false,
                        category: category,
                        customCategoryName: category == .custom ? customCategoryName.trimmingCharacters(in: .whitespacesAndNewlines) : nil,
                        imagePath: imagePath,
                        pillsRemaining: trackSupply ? pillsRemaining : nil,
                        pillsPerDose: trackSupply ? pillsPerDose : nil,
                        foodInstruction: foodInstruction,
                        isAsNeeded: isAsNeeded ? true : nil,
                        courseEndDate: hasCourseEnd ? courseEndDate : nil,
                        specialInstructions: specialInstructions.isEmpty ? nil : specialInstructions
                    )
                    onSave(med)
                    Haptics.success()
                    dismiss()
                }
            } message: {
                Text(NSLocalizedString("Reminders are enabled but no times are set. Add a time or save without reminders.", comment: ""))
            }
        }
    }
}

struct EditMedicationView: View {
    @EnvironmentObject var store: DataStore
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
    @State private var customCategoryName: String = ""
    @State private var showScheduleAlert = false
    @State private var trackSupply: Bool = false
    @State private var pillsRemaining: Int = 30
    @State private var pillsPerDose: Int = 1
    @State private var foodInstruction: FoodInstruction?
    @State private var isAsNeeded: Bool = false
    @State private var hasCourseEnd: Bool = false
    @State private var courseEndDate: Date = Calendar.current.date(byAdding: .month, value: 1, to: Date()) ?? Date()
    @State private var specialInstructions: String = ""

    init(medication: Medication, onSave: @escaping (Medication) -> Void, onDelete: (() -> Void)? = nil) {
        self.medication = medication
        self.onSave = onSave
        self.onDelete = onDelete
        // State will be initialized in .onAppear to avoid SwiftUI init warnings
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(NSLocalizedString("Medication Name", comment: ""), text: $name)
                        .appFont(.headline)
                    TextField(NSLocalizedString("Dose (e.g. 500mg)", comment: ""), text: $dose)
                        .appFont(.headline)
                } header: {
                    Text(NSLocalizedString("What are you taking?", comment: ""))
                }

                // Adherence stats
                Section {
                    let hasLogs = store.intakeLogs.contains { $0.medicationID == medication.id }
                    if hasLogs {
                        let adh30 = store.adherencePercent(for: medication.id, days: 30)
                        let adh7 = store.adherencePercent(for: medication.id, days: 7)
                        let streak = store.currentStreak(for: medication.id)
                        HStack(spacing: 16) {
                            VStack(spacing: 2) {
                                Text(String(format: "%.0f%%", adh7 * 100))
                                    .appFont(.headline)
                                    .foregroundStyle(adh7 >= 0.8 ? .green : adh7 >= 0.5 ? .orange : .red)
                                Text(NSLocalizedString("7-day", comment: ""))
                                    .appFont(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity)
                            VStack(spacing: 2) {
                                Text(String(format: "%.0f%%", adh30 * 100))
                                    .appFont(.headline)
                                    .foregroundStyle(adh30 >= 0.8 ? .green : adh30 >= 0.5 ? .orange : .red)
                                Text(NSLocalizedString("30-day", comment: ""))
                                    .appFont(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity)
                            VStack(spacing: 2) {
                                Text("\(streak)")
                                    .appFont(.headline)
                                    .foregroundStyle(.blue)
                                Text(NSLocalizedString("day streak", comment: ""))
                                    .appFont(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity)
                        }
                        .padding(.vertical, 4)
                    } else {
                        HStack {
                            Image(systemName: "chart.bar")
                                .foregroundStyle(.secondary)
                            Text(NSLocalizedString("Log your first dose to see stats here.", comment: ""))
                                .appFont(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 4)
                    }
                } header: {
                    Text(NSLocalizedString("Adherence", comment: ""))
                }

                Section {
                    ForEach(times.indices, id: \.self) { idx in
                        HStack {
                            DatePicker("Time \(idx+1)", selection: $times[idx], displayedComponents: .hourAndMinute)
                            Button(role: .destructive) {
                                times.remove(at: idx)
                            } label: {
                                Image(systemName: "minus.circle.fill")
                                    .font(.title3)
                                    .foregroundStyle(.red)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    Button { times.append(Date()) } label: {
                        Label(NSLocalizedString("Add Time", comment: ""), systemImage: "plus.circle")
                            .appFont(.subheadline)
                    }
                    Toggle(NSLocalizedString("Remind Me", comment: ""), isOn: $remindersEnabled)
                        .appFont(.subheadline)
                    if remindersEnabled && times.isEmpty {
                        Label(NSLocalizedString("Add at least one time for reminders", comment: ""), systemImage: "exclamationmark.triangle")
                            .appFont(.caption)
                            .foregroundStyle(.orange)
                    }
                } header: {
                    Text(NSLocalizedString("When do you take it?", comment: ""))
                }

                Section {
                    DisclosureGroup(NSLocalizedString("More Options", comment: "")) {
                        TextField(NSLocalizedString("Notes (optional)", comment: ""), text: $notes)

                        Toggle(NSLocalizedString("Track Supply", comment: ""), isOn: $trackSupply)
                        if trackSupply {
                            Stepper(value: $pillsRemaining, in: 0...999) {
                                Text(String(format: NSLocalizedString("Pills remaining: %lld", comment: ""), pillsRemaining))
                            }
                            Stepper(value: $pillsPerDose, in: 1...10) {
                                Text(String(format: NSLocalizedString("Pills per dose: %lld", comment: ""), pillsPerDose))
                            }
                        }

                        Picker(NSLocalizedString("Category", comment: ""), selection: $category) {
                            ForEach(MedicationCategory.allCases) { c in Text(c.displayName).tag(c) }
                        }
                        if category == .custom {
                            TextField(NSLocalizedString("Custom Category", comment: ""), text: $customCategoryName)
                        }
                        HStack {
                            if let img = pickedImage {
                                Image(uiImage: img)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 56, height: 56)
                                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                            } else if !removePhoto, let existing = loadMedImage(path: medication.imagePath) {
                                Image(uiImage: existing)
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
                            PhotosPicker(selection: $pickedItem, matching: .images) { Text(NSLocalizedString("Choose Photo", comment: "")) }
                                .onChange(of: pickedItem) { newItem in
                                    Task { if let data = try? await newItem?.loadTransferable(type: Data.self), let ui = UIImage(data: data) { pickedImage = ui; removePhoto = false } }
                                }
                            if pickedImage != nil || (medication.imagePath != nil && !removePhoto) {
                                Button(role: .destructive) { pickedImage = nil; removePhoto = true } label: { Text(NSLocalizedString("Remove", comment: "")) }
                            }
                        }

                        Picker(NSLocalizedString("Food Instruction", comment: ""), selection: $foodInstruction) {
                            Text(NSLocalizedString("None", comment: "")).tag(FoodInstruction?.none)
                            ForEach(FoodInstruction.allCases) { fi in
                                Text(fi.displayName).tag(FoodInstruction?.some(fi))
                            }
                        }

                        Toggle(NSLocalizedString("As Needed (PRN)", comment: ""), isOn: $isAsNeeded)

                        Toggle(NSLocalizedString("Course End Date", comment: ""), isOn: $hasCourseEnd)
                        if hasCourseEnd {
                            DatePicker(NSLocalizedString("End Date", comment: ""), selection: $courseEndDate, displayedComponents: .date)
                        }

                        TextField(NSLocalizedString("Special Instructions (optional)", comment: ""), text: $specialInstructions, axis: .vertical)
                            .lineLimit(2...4)
                    }
                }

                Section {
                    NavigationLink {
                        AdherenceCalendarView(medicationID: medication.id)
                    } label: {
                        Label(NSLocalizedString("Adherence History", comment: ""), systemImage: "calendar")
                    }
                }

                // Correlation mini-chart for medications with known category
                if let cat = medication.category, !cat.correlatedMeasurementTypes.isEmpty {
                    let correlatedTypes = cat.correlatedMeasurementTypes
                    ForEach(correlatedTypes, id: \.self) { mType in
                        let data = store.measurements.filter { $0.type == mType }
                            .sorted { $0.date < $1.date }
                            .suffix(30)
                        if data.count >= 2 {
                            Section {
                                VStack(alignment: .leading, spacing: 8) {
                                    Label(String(format: NSLocalizedString("Related: %@", comment: ""), mType.rawValue), systemImage: "chart.xyaxis.line")
                                        .appFont(.subheadline)
                                        .foregroundStyle(.secondary)
                                    Chart(Array(data)) { m in
                                        LineMark(
                                            x: .value("Date", m.date),
                                            y: .value("Value", m.value)
                                        )
                                        .foregroundStyle(mType.tint)
                                        .interpolationMethod(.catmullRom)
                                        PointMark(
                                            x: .value("Date", m.date),
                                            y: .value("Value", m.value)
                                        )
                                        .foregroundStyle(mType.tint)
                                        .symbolSize(16)
                                    }
                                    .frame(height: 120)
                                    .chartXAxis(.hidden)
                                    .chartYAxis {
                                        AxisMarks(position: .leading, values: .automatic(desiredCount: 3))
                                    }
                                }
                                .padding(.vertical, 4)
                            } header: {
                                Text(NSLocalizedString("Related Health Data", comment: ""))
                            }
                        }
                    }
                }
            }
            .navigationTitle(NSLocalizedString("Edit Medication", comment: ""))
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
                customCategoryName = medication.customCategoryName ?? ""
                trackSupply = medication.pillsRemaining != nil
                pillsRemaining = medication.pillsRemaining ?? 30
                pillsPerDose = medication.pillsPerDose ?? 1
                foodInstruction = medication.foodInstruction
                isAsNeeded = medication.isAsNeeded ?? false
                hasCourseEnd = medication.courseEndDate != nil
                courseEndDate = medication.courseEndDate ?? Calendar.current.date(byAdding: .month, value: 1, to: Date()) ?? Date()
                specialInstructions = medication.specialInstructions ?? ""
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        if remindersEnabled && times.isEmpty {
                            showScheduleAlert = true
                            return
                        }
                        saveAndDismiss()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .alert(NSLocalizedString("No Schedule Set", comment: ""), isPresented: $showScheduleAlert) {
                Button(NSLocalizedString("Add Time", comment: "")) { times.append(Date()) }
                Button(NSLocalizedString("Save Without Reminders", comment: "")) {
                    remindersEnabled = false
                    saveAndDismiss()
                }
            } message: {
                Text(NSLocalizedString("Reminders are enabled but no times are set. Add a time or save without reminders.", comment: ""))
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

    private func saveAndDismiss() {
        let comps = times.map { Calendar.current.dateComponents([.hour, .minute], from: $0) }
        var updated = medication
        updated.name = name
        updated.dose = dose
        updated.notes = notes.isEmpty ? nil : notes
        updated.timesOfDay = comps
        updated.remindersEnabled = remindersEnabled
        updated.category = category
        updated.customCategoryName = category == .custom ? customCategoryName.trimmingCharacters(in: .whitespacesAndNewlines) : nil
        updated.pillsRemaining = trackSupply ? pillsRemaining : nil
        updated.pillsPerDose = trackSupply ? pillsPerDose : nil
        updated.foodInstruction = foodInstruction
        updated.isAsNeeded = isAsNeeded ? true : nil
        updated.courseEndDate = hasCourseEnd ? courseEndDate : nil
        updated.specialInstructions = specialInstructions.isEmpty ? nil : specialInstructions
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
}

#Preview {
    MedicationsView().environmentObject(DataStore())
}

// MARK: - Image helpers
private extension MedicationsView {
    enum MedFilter: String, CaseIterable, Identifiable {
        case all
        case remindersOn
        case remindersOff

        var id: String { rawValue }
        var displayName: LocalizedStringKey {
            switch self {
            case .all: return LocalizedStringKey("All")
            case .remindersOn: return LocalizedStringKey("Active")
            case .remindersOff: return LocalizedStringKey("Paused")
            }
        }
    }

    var filteredMedications: [Medication] {
        store.medications.filter { med in
            let matchesFilter: Bool = {
                switch filter {
                case .all: return true
                case .remindersOn: return med.remindersEnabled
                case .remindersOff: return !med.remindersEnabled
                }
            }()
            let matchesSearch: Bool
            if searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                matchesSearch = true
            } else {
                let query = searchText.lowercased()
                matchesSearch = med.name.lowercased().contains(query) || med.dose.lowercased().contains(query)
            }
            return matchesFilter && matchesSearch
        }
    }

    var summaryCard: some View {
        let total = store.medications.count
        let active = store.medications.filter { $0.remindersEnabled }.count
        let paused = max(total - active, 0)
        return HStack(spacing: 0) {
            summaryStat(value: "\(total)", label: NSLocalizedString("Medications", comment: ""))
            summaryDivider
            summaryStat(value: "\(active)", label: NSLocalizedString("Active", comment: ""), color: .green)
            summaryDivider
            summaryStat(value: "\(paused)", label: NSLocalizedString("Paused", comment: ""), color: paused > 0 ? .orange : .secondary)
        }
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(.secondarySystemBackground))
        )
    }

    private func summaryStat(value: String, label: String, color: Color = .primary) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .appFont(.headline)
                .foregroundStyle(color)
            Text(label)
                .appFont(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private var summaryDivider: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.08))
            .frame(width: 1, height: 32)
    }

    var filterChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(spacing: 10) {
                ForEach(MedFilter.allCases) { chipButton(for: $0) }
            }
            .padding(.horizontal, 4)
        }
        .accessibilityElement(children: .combine)
    }

    private func chipButton(for option: MedFilter) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.18)) { filter = option }
        } label: {
            HStack(spacing: 6) {
                Text(option.displayName)
                countChip(for: option)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(
                Capsule().fill(filter == option ? Color.accentColor.opacity(0.2) : Color(.systemBackground))
            )
            .overlay(
                Capsule().stroke(filter == option ? Color.accentColor : Color.primary.opacity(0.1), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private func countText(for filter: MedFilter) -> Int {
        switch filter {
        case .all:
            return store.medications.count
        case .remindersOn:
            return store.medications.filter { $0.remindersEnabled }.count
        case .remindersOff:
            return store.medications.filter { !$0.remindersEnabled }.count
        }
    }

    private func countChip(for filter: MedFilter) -> some View {
        Text("\(countText(for: filter))")
            .appFont(.caption)
            .foregroundStyle(.primary.opacity(0.6))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Capsule().fill(Color.primary.opacity(0.08)))
    }

    @ViewBuilder
    private func medicationCard(for med: Medication) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            // Row 1: thumbnail + name/dose + status/toggle
            HStack(alignment: .center, spacing: 10) {
                medicationThumbnail(for: med)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(med.name)
                            .appFont(.headline)
                            .lineLimit(1)
                        if !med.remindersEnabled {
                            Text(NSLocalizedString("Paused", comment: ""))
                                .appFont(.caption)
                                .foregroundStyle(.orange)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Capsule().fill(Color.orange.opacity(0.12)))
                        }
                        if med.isAsNeeded == true {
                            Text(NSLocalizedString("PRN", comment: ""))
                                .appFont(.caption)
                                .foregroundStyle(.blue)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Capsule().fill(Color.blue.opacity(0.12)))
                        }
                    }
                    // Dose + times inline
                    HStack(spacing: 4) {
                        Text(med.dose)
                            .appFont(.caption)
                            .foregroundStyle(.secondary)
                        if !med.timesOfDay.isEmpty {
                            Text("·").foregroundStyle(.secondary)
                            timesText(for: med)
                        }
                    }
                }
                Spacer(minLength: 4)
                reminderToggle(for: med)
            }

            // Row 2: supply + status + quick-take (all inline)
            HStack(spacing: 8) {
                if let remaining = med.pillsRemaining {
                    compactSupplyLabel(remaining: remaining, med: med)
                }
                if let (status, date) = latestTodayAction(for: med) {
                    inlineStatusLabel(status: status, date: date)
                }
                Spacer(minLength: 0)
                if med.remindersEnabled {
                    compactQuickTakeButton(for: med)
                }
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(.secondarySystemBackground))
        )
        .contentShape(Rectangle())
        .onTapGesture { editTarget = med }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private func compactSupplyLabel(remaining: Int, med: Medication) -> some View {
        let isLow = med.isLowSupply
        HStack(spacing: 4) {
            if isLow {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 13))
                    .foregroundStyle(.red)
            }
            if let days = med.daysOfSupplyRemaining, days > 0 {
                Text(String(format: NSLocalizedString("%lld pills · %lld d", comment: "pills and days short"), remaining, days))
                    .appFont(.caption)
                    .foregroundStyle(isLow ? .red : .secondary)
            } else {
                Text(String(format: NSLocalizedString("%lld pills", comment: ""), remaining))
                    .appFont(.caption)
                    .foregroundStyle(isLow ? .red : .secondary)
            }
        }
    }

    private func inlineStatusLabel(status: IntakeStatus, date: Date) -> some View {
        HStack(spacing: 5) {
            Image(systemName: latestStatusIcon(status))
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(statusTint(for: status))
            Text(statusPrefix(for: status))
                .appFont(.caption)
                .foregroundStyle(statusTint(for: status))
        }
    }

    @ViewBuilder
    private func compactQuickTakeButton(for med: Medication) -> some View {
        if let dose = nextUntakenDose(for: med) {
            Button {
                // Rule: duplicate taken guard
                let dupCheck = MedicationRules.checkDuplicateTaken(
                    medicationID: med.id,
                    scheduleTime: dose.comps,
                    intakeLogs: store.intakeLogs
                )
                if case .blocked = dupCheck {
                    Haptics.notification(.warning)
                    return
                }
                store.upsertIntake(medicationID: med.id, status: .taken, scheduleTime: dose.comps)
                store.decrementPills(for: med.id)
                NotificationManager.shared.suppressToday(for: med.id, timeComponents: dose.comps)
                NotificationManager.shared.cancelTodayInstance(for: med.id, timeComponents: dose.comps)
                NotificationManager.shared.schedule(for: med)
                NotificationManager.shared.updateBadge(store: store)
                Haptics.success()
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "checkmark")
                        .font(.system(size: 13, weight: .bold))
                    Text(dose.timeStr)
                        .appFont(.caption)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }
            .buttonStyle(.borderedProminent)
            .tint(.green)
            .controlSize(.small)
        }
    }

    private func nextUntakenDose(for med: Medication) -> (comps: DateComponents, timeStr: String)? {
        let cal = Calendar.current
        let now = Date()
        let dayStart = cal.startOfDay(for: now)
        guard let dayEnd = cal.date(byAdding: .day, value: 1, to: dayStart) else { return nil }
        let todayLogs = store.intakeLogs.filter { $0.medicationID == med.id && $0.date >= dayStart && $0.date < dayEnd }
        let sorted = med.timesOfDay.sorted { ($0.hour ?? 0) * 60 + ($0.minute ?? 0) < ($1.hour ?? 0) * 60 + ($1.minute ?? 0) }
        for comps in sorted {
            let key = String(format: "%02d:%02d", comps.hour ?? 0, comps.minute ?? 0)
            let taken = todayLogs.contains { $0.scheduleKey == key && $0.status == .taken }
            if !taken {
                let formatter = DateFormatter()
                formatter.timeStyle = .short
                let timeStr = cal.date(bySettingHour: comps.hour ?? 0, minute: comps.minute ?? 0, second: 0, of: now)
                    .map { formatter.string(from: $0) } ?? ""
                return (comps, timeStr)
            }
        }
        return nil
    }

    @ViewBuilder
    private func medicationThumbnail(for med: Medication) -> some View {
        if let path = med.imagePath, let ui = loadMedImage(path: path) {
            Image(uiImage: ui)
                .resizable()
                .scaledToFill()
                .frame(width: 40, height: 40)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        } else {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.accentColor.opacity(0.10))
                .frame(width: 40, height: 40)
                .overlay(
                    Image(systemName: "pills.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(Color.accentColor)
                )
        }
    }

    private func timesText(for med: Medication) -> some View {
        let formatter: DateFormatter = {
            let f = DateFormatter()
            f.timeStyle = .short
            return f
        }()
        let cal = Calendar.current
        let times = med.timesOfDay.compactMap { comps -> String? in
            guard let h = comps.hour, let m = comps.minute,
                  let date = cal.date(bySettingHour: h, minute: m, second: 0, of: Date()) else { return nil }
            return formatter.string(from: date)
        }
        return Text(times.joined(separator: ", "))
            .appFont(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(1)
    }

    private func reminderToggle(for med: Medication) -> some View {
        Toggle(isOn: Binding(
            get: { med.remindersEnabled },
            set: { newVal in
                Task {
                    if newVal {
                        let granted = await NotificationManager.shared.ensureAuthorization()
                        await MainActor.run {
                            guard granted else {
                                deniedMedName = med.name
                                showNotificationDeniedAlert = true
                                var reverted = med
                                reverted.remindersEnabled = false
                                store.updateMedication(reverted)
                                refreshNotificationStatus()
                                return
                            }
                            var updated = med
                            updated.remindersEnabled = true
                            store.updateMedication(updated)
                            NotificationManager.shared.schedule(for: updated)
                            NotificationManager.shared.updateBadge(store: store)
                            Haptics.impact(.light)
                            refreshNotificationStatus()
                        }
                    } else {
                        await MainActor.run {
                            var updated = med
                            updated.remindersEnabled = false
                            store.updateMedication(updated)
                            NotificationManager.shared.cancelAll(for: updated)
                            NotificationManager.shared.updateBadge(store: store)
                            Haptics.impact(.light)
                            refreshNotificationStatus()
                        }
                    }
                }
            }
        )) {
            Text(NSLocalizedString("Remind", comment: ""))
        }
        .labelsHidden()
    }


    private func latestStatusIcon(_ status: IntakeStatus) -> String {
        switch status {
        case .taken: return "checkmark.circle.fill"
        case .skipped: return "xmark.circle.fill"
        case .snoozed: return "zzz"
        }
    }

    private func statusTint(for status: IntakeStatus) -> Color {
        switch status {
        case .taken: return .green
        case .skipped: return .orange
        case .snoozed: return .blue
        }
    }

    private func statusPrefix(for status: IntakeStatus) -> LocalizedStringKey {
        switch status {
        case .taken: return "Taken"
        case .skipped: return "Skipped"
        case .snoozed: return "Snoozed"
        }
    }


    private func latestTodayAction(for med: Medication) -> (IntakeStatus, Date)? {
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

func loadMedImage(path: String?) -> UIImage? {
    guard let path = path else { return nil }
    let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
    let url = docs.appendingPathComponent(path)
    return UIImage(contentsOfFile: url.path)
}

func removeMedImage(path: String?) {
    guard let path = path else { return }
    let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
    let url = docs.appendingPathComponent(path)
    try? FileManager.default.removeItem(at: url)
}

private extension MedicationsView {
    func refreshNotificationStatus() {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            DispatchQueue.main.async {
                self.notificationStatus = settings.authorizationStatus
            }
        }
    }

    func delete(at offsets: IndexSet) {
        let ids = offsets.map { filteredMedications[$0].id }
        let items = store.medications.filter { ids.contains($0.id) }
        items.forEach {
            NotificationManager.shared.cancelAll(for: $0)
            removeMedImage(path: $0.imagePath)
        }
        let toRemove = IndexSet(store.medications.enumerated().compactMap { ids.contains($0.element.id) ? $0.offset : nil })
        store.removeMedication(at: toRemove)
        NotificationManager.shared.updateBadge(store: store)
    }
}
