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
                    NotificationManager.shared.syncAll(medications: store.medications, intakeLogs: store.intakeLogs)
                    NotificationManager.shared.updateBadge(store: store)
                    refreshNotificationStatus()
                }
            }
            .sheet(item: $editTarget) { med in
                EditMedicationView(medication: med, onSave: { updated in
                    store.updateMedication(updated)
                    NotificationManager.shared.syncAll(medications: store.medications, intakeLogs: store.intakeLogs)
                    NotificationManager.shared.updateBadge(store: store)
                    refreshNotificationStatus()
                }, onDelete: {
                    if let idx = store.medications.firstIndex(where: { $0.id == med.id }) {
                        NotificationManager.shared.cancelAll(for: med)
                        removeMedImage(path: med.imagePath)
                        store.removeMedication(at: IndexSet(integer: idx))
                        NotificationManager.shared.syncAll(medications: store.medications, intakeLogs: store.intakeLogs)
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
    @State private var isOCRLoading = false
    @State private var ocrSuggestion: MedicationOCRSuggestion?
    @State private var ocrErrorMessage: String?
    @State private var showOCRError = false
    @State private var showOCRCamera = false
    @State private var showCameraUnavailableAlert = false
    @State private var schedulePreset: SchedulePreset = .custom
    @State private var showPRNConfirmation = false
    @State private var showAdditionalContext = false
    @State private var showOptionalDetails = false
    @FocusState private var focusedField: EntryField?

    private enum EntryField: Hashable {
        case name
        case dose
        case notes
        case specialInstructions
        case customCategory
    }

    private enum SchedulePreset: String, CaseIterable, Identifiable {
        case onceDaily
        case twiceDaily
        case morningEvening
        case custom

        var id: String { rawValue }

        var title: LocalizedStringKey {
            switch self {
            case .onceDaily: return "Once Daily"
            case .twiceDaily: return "Twice Daily"
            case .morningEvening: return "Morning + Evening"
            case .custom: return "Custom"
            }
        }

        var subtitle: LocalizedStringKey {
            switch self {
            case .onceDaily: return "1 reminder"
            case .twiceDaily: return "2 reminders"
            case .morningEvening: return "AM + PM"
            case .custom: return "Edit times manually"
            }
        }
    }

    private var refillThresholdDays: Int {
        UserDefaults.standard.object(forKey: "prefs.refillThresholdDays") as? Int ?? 7
    }

    private var courseReminderThresholdDays: Int {
        UserDefaults.standard.object(forKey: "prefs.courseEndThresholdDays") as? Int ?? 3
    }

    private var estimatedSupplyDays: Int? {
        guard trackSupply else { return nil }
        guard !isAsNeeded, !times.isEmpty else { return nil }
        let dosesPerDay = max(times.count, 1)
        let pillsPerDay = max(pillsPerDose * dosesPerDay, 1)
        return pillsRemaining / pillsPerDay
    }

    private var courseDaysRemaining: Int? {
        guard hasCourseEnd else { return nil }
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: Date())
        let end = calendar.startOfDay(for: courseEndDate)
        return calendar.dateComponents([.day], from: start, to: end).day
    }

    private var quickPillButtons: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(NSLocalizedString("Quick fill", comment: ""))
                .appFont(.caption)
                .foregroundStyle(.secondary)
            HStack(spacing: 8) {
                ForEach([30, 60, 90], id: \.self) { value in
                    quickSupplyButton(title: "\(value)") {
                        pillsRemaining = value
                    }
                }
            }
        }
    }

    private var quickCourseButtons: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(NSLocalizedString("Quick duration", comment: ""))
                .appFont(.caption)
                .foregroundStyle(.secondary)
            HStack(spacing: 8) {
                quickSupplyButton(title: NSLocalizedString("7 days", comment: "")) {
                    courseEndDate = Calendar.current.date(byAdding: .day, value: 7, to: Date()) ?? courseEndDate
                }
                quickSupplyButton(title: NSLocalizedString("14 days", comment: "")) {
                    courseEndDate = Calendar.current.date(byAdding: .day, value: 14, to: Date()) ?? courseEndDate
                }
                quickSupplyButton(title: NSLocalizedString("30 days", comment: "")) {
                    courseEndDate = Calendar.current.date(byAdding: .day, value: 30, to: Date()) ?? courseEndDate
                }
            }
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 16) {
                    Card {
                        VStack(alignment: .leading, spacing: 14) {
                            HStack(alignment: .center, spacing: 10) {
                                Text(NSLocalizedString("Medication", comment: ""))
                                    .appFont(.headline)
                                Spacer()
                                scanLabelButton
                            }

                            textInputCard(
                                title: NSLocalizedString("Medication Name", comment: ""),
                                placeholder: NSLocalizedString("Amlodipine", comment: ""),
                                text: $name,
                                field: .name
                            )

                            textInputCard(
                                title: NSLocalizedString("Dose", comment: ""),
                                placeholder: NSLocalizedString("5 mg", comment: ""),
                                text: $dose,
                                field: .dose
                            )

                            if isOCRLoading {
                                Text(NSLocalizedString("Reading label...", comment: ""))
                                    .appFont(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            Divider()

                            Text(NSLocalizedString("How do you take it?", comment: ""))
                                .appFont(.headline)

                            HStack(spacing: 10) {
                                intakeModeButton(
                                    title: NSLocalizedString("Scheduled", comment: ""),
                                    subtitle: NSLocalizedString("Daily reminders", comment: ""),
                                    isSelected: !isAsNeeded
                                ) {
                                    isAsNeeded = false
                                    if times.isEmpty {
                                        schedulePreset = .onceDaily
                                        applySchedulePreset(.onceDaily)
                                    }
                                    remindersEnabled = true
                                }

                                intakeModeButton(
                                    title: NSLocalizedString("As Needed", comment: ""),
                                    subtitle: NSLocalizedString("Log only when taken", comment: ""),
                                    isSelected: isAsNeeded
                                ) {
                                    requestSwitchToPRN()
                                }
                            }
                        }
                    }

                    if isAsNeeded {
                        Card {
                            VStack(alignment: .leading, spacing: 10) {
                                Text(NSLocalizedString("PRN Medication", comment: ""))
                                    .appFont(.headline)
                                Text(NSLocalizedString("As-needed medications skip fixed reminder times. You can log each dose from the Today screen whenever you take it.", comment: ""))
                                    .appFont(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    } else {
                        Card {
                            VStack(alignment: .leading, spacing: 14) {
                                Text(NSLocalizedString("Schedule", comment: ""))
                                    .appFont(.headline)

                                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                                    ForEach(SchedulePreset.allCases) { preset in
                                        schedulePresetButton(preset)
                                    }
                                }

                                if times.isEmpty {
                                    Text(NSLocalizedString("Choose a preset or add a custom time.", comment: ""))
                                        .appFont(.caption)
                                        .foregroundStyle(.secondary)
                                } else {
                                    ForEach(Array(times.indices), id: \.self) { idx in
                                        timeRow(for: idx)
                                    }
                                }

                                Button {
                                    schedulePreset = .custom
                                    times.append(defaultCustomTime(after: times.last))
                                } label: {
                                    secondaryActionLabel(NSLocalizedString("Add Time", comment: ""), systemImage: "plus.circle.fill")
                                }
                                .buttonStyle(.plain)

                                HStack(spacing: 10) {
                                    Text(NSLocalizedString("Remind Me", comment: ""))
                                        .appFont(.subheadline)
                                    Spacer()
                                    Toggle(NSLocalizedString("Remind Me", comment: ""), isOn: $remindersEnabled)
                                        .labelsHidden()
                                }

                                if remindersEnabled && times.isEmpty {
                                    Label(NSLocalizedString("Add at least one time for reminders", comment: ""), systemImage: "exclamationmark.triangle.fill")
                                        .appFont(.caption)
                                        .foregroundStyle(.orange)
                                }
                            }
                        }
                    }

                    Card {
                        DisclosureGroup(isExpanded: $showOptionalDetails) {
                            VStack(alignment: .leading, spacing: 16) {
                                Divider()

                                VStack(alignment: .leading, spacing: 14) {
                                    Text(NSLocalizedString("Instructions", comment: ""))
                                        .appFont(.headline)

                                    Picker(NSLocalizedString("Food Instruction", comment: ""), selection: $foodInstruction) {
                                        Text(NSLocalizedString("None", comment: "")).tag(FoodInstruction?.none)
                                        ForEach(FoodInstruction.allCases) { f in
                                            Text(f.displayName).tag(Optional(f))
                                        }
                                    }

                                    textInputCard(
                                        title: NSLocalizedString("Special Instructions", comment: ""),
                                        placeholder: NSLocalizedString("Take after dinner", comment: ""),
                                        text: $specialInstructions,
                                        field: .specialInstructions
                                    )

                                    DisclosureGroup(isExpanded: $showAdditionalContext) {
                                        textInputCard(
                                            title: NSLocalizedString("Notes", comment: ""),
                                            placeholder: NSLocalizedString("Optional context", comment: ""),
                                            text: $notes,
                                            field: .notes,
                                            axis: .vertical,
                                            lineLimit: 2...4
                                        )
                                        .padding(.top, 6)
                                    } label: {
                                        HStack {
                                            Text(NSLocalizedString("Additional Context", comment: ""))
                                                .appFont(.subheadline)
                                                .fontWeight(.semibold)
                                            Spacer()
                                            Text(notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? NSLocalizedString("Optional", comment: "") : NSLocalizedString("Added", comment: ""))
                                                .appFont(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                }

                                Divider()

                                VStack(alignment: .leading, spacing: 14) {
                                    Text(NSLocalizedString("Supply & Course", comment: ""))
                                        .appFont(.headline)

                                    Toggle(NSLocalizedString("Track Supply", comment: ""), isOn: $trackSupply)
                                    if trackSupply {
                                        Stepper(value: $pillsRemaining, in: 0...999) {
                                            Text(String(format: NSLocalizedString("Pills remaining: %lld", comment: ""), pillsRemaining))
                                        }
                                        Stepper(value: $pillsPerDose, in: 1...10) {
                                            Text(String(format: NSLocalizedString("Pills per dose: %lld", comment: ""), pillsPerDose))
                                        }
                                        quickPillButtons
                                        if let estimatedSupplyDays {
                                            Text(String(format: NSLocalizedString("About %lld days of supply at your current schedule.", comment: ""), estimatedSupplyDays))
                                                .appFont(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                        Text(String(format: NSLocalizedString("Refill reminders start when about %lld days remain.", comment: ""), refillThresholdDays))
                                            .appFont(.caption)
                                            .foregroundStyle(.secondary)
                                    }

                                    Toggle(NSLocalizedString("Has Course End Date", comment: ""), isOn: $hasCourseEnd)
                                    if hasCourseEnd {
                                        DatePicker(NSLocalizedString("End Date", comment: ""), selection: $courseEndDate, displayedComponents: .date)
                                        quickCourseButtons
                                        if let courseDaysRemaining {
                                            Text(String(format: NSLocalizedString("Course ends in %lld days.", comment: ""), max(courseDaysRemaining, 0)))
                                                .appFont(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                        Text(String(format: NSLocalizedString("Course reminders start %lld days before the end date.", comment: ""), courseReminderThresholdDays))
                                            .appFont(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }

                                Divider()

                                VStack(alignment: .leading, spacing: 14) {
                                    Text(NSLocalizedString("Category & Photo", comment: ""))
                                        .appFont(.headline)

                                    Picker(NSLocalizedString("Category", comment: ""), selection: $category) {
                                        ForEach(MedicationCategory.allCases) { c in
                                            Text(c.displayName).tag(c)
                                        }
                                    }

                                    if category == .custom {
                                        textInputCard(
                                            title: NSLocalizedString("Custom Category", comment: ""),
                                            placeholder: NSLocalizedString("Cardiology", comment: ""),
                                            text: $customCategoryName,
                                            field: .customCategory
                                        )
                                    }

                                    photoAttachmentRow
                                }
                            }
                            .padding(.top, 10)
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(NSLocalizedString("Optional Details", comment: ""))
                                    .appFont(.headline)
                                Text(NSLocalizedString("Instructions, inventory, category, and photo.", comment: ""))
                                    .appFont(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }

                    Card {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(NSLocalizedString("Summary", comment: ""))
                                .appFont(.headline)
                            Text(summaryLine)
                                .appFont(.subheadline)
                            if !secondarySummaryLine.isEmpty {
                                Text(secondarySummaryLine)
                                    .appFont(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                .padding(16)
            }
            .navigationTitle(NSLocalizedString("Add Medication", comment: ""))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        if !isAsNeeded && remindersEnabled && times.isEmpty {
                            showScheduleAlert = true
                            return
                        }
                        saveMedication(remindersOverride: nil)
                    }
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button(NSLocalizedString("Done", comment: "")) {
                        focusedField = nil
                    }
                }
            }
            .onAppear {
                focusedField = .name
                showAdditionalContext = !notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            }
            .alert(NSLocalizedString("No Schedule Set", comment: ""), isPresented: $showScheduleAlert) {
                Button(NSLocalizedString("Add Time", comment: "")) {
                    schedulePreset = .custom
                    times.append(defaultCustomTime(after: nil))
                }
                Button(NSLocalizedString("Save Without Reminders", comment: "")) {
                    saveMedication(remindersOverride: false)
                }
            } message: {
                Text(NSLocalizedString("Reminders are enabled but no times are set. Add a time or save without reminders.", comment: ""))
            }
            .sheet(item: $ocrSuggestion) { suggestion in
                MedicationOCRReviewSheet(suggestion: suggestion) { editedSuggestion in
                    applyOCRSuggestion(editedSuggestion)
                }
            }
            .fullScreenCover(isPresented: $showOCRCamera) {
                CameraCaptureView { image in
                    runOCR(from: image)
                }
                .ignoresSafeArea()
            }
            .alert(NSLocalizedString("Couldn't Read Label", comment: ""), isPresented: $showOCRError) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(ocrErrorMessage ?? NSLocalizedString("We couldn't confidently extract medication details from that image. Try a clearer photo of the label.", comment: ""))
            }
            .alert(NSLocalizedString("Camera Unavailable", comment: ""), isPresented: $showCameraUnavailableAlert) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(NSLocalizedString("This device does not currently provide camera access for label scanning.", comment: ""))
            }
            .alert(NSLocalizedString("Switch to As Needed?", comment: ""), isPresented: $showPRNConfirmation) {
                Button(NSLocalizedString("Keep Scheduled", comment: ""), role: .cancel) { }
                Button(NSLocalizedString("Switch", comment: ""), role: .destructive) {
                    confirmSwitchToPRN()
                }
            } message: {
                Text(NSLocalizedString("This will turn off fixed reminders for this medication and remove any scheduled times from the form.", comment: ""))
            }
        }
    }

    private func runOCR(from image: UIImage) {
        isOCRLoading = true
        Task {
            do {
                guard let data = image.jpegData(compressionQuality: 0.9) else {
                    throw MedicationOCRService.OCRFailure.unreadableImage
                }
                let suggestion = try await MedicationOCRService.recognizeMedication(from: data)
                await MainActor.run {
                    isOCRLoading = false
                    ocrSuggestion = suggestion
                }
            } catch {
                await MainActor.run {
                    isOCRLoading = false
                    ocrErrorMessage = error.localizedDescription
                    showOCRError = true
                }
            }
        }
    }

    private func applyOCRSuggestion(_ suggestion: MedicationOCRSuggestion) {
        if let detectedName = suggestion.name, !detectedName.isEmpty {
            name = detectedName
        }
        if let detectedDose = suggestion.dose, !detectedDose.isEmpty {
            dose = detectedDose
        }
        if notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           let detectedNotes = suggestion.notes,
           !detectedNotes.isEmpty {
            notes = detectedNotes
            showOptionalDetails = true
            showAdditionalContext = true
        }
        ocrSuggestion = nil
    }

    private func saveMedication(remindersOverride: Bool?) {
        guard let med = makeMedication(remindersOverride: remindersOverride) else { return }
        onSave(med)
        Haptics.success()
        dismiss()
    }

    private func requestSwitchToPRN() {
        guard !isAsNeeded else { return }
        if remindersEnabled || !times.isEmpty {
            showPRNConfirmation = true
        } else {
            confirmSwitchToPRN()
        }
    }

    private func confirmSwitchToPRN() {
        isAsNeeded = true
        remindersEnabled = false
        times = []
        schedulePreset = .custom
    }

    private func makeMedication(remindersOverride: Bool?) -> Medication? {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return nil }

        let newID = UUID()
        var imagePath: String? = nil
        if let img = pickedImage, let path = saveMedImage(image: img, id: newID) {
            imagePath = path
        }

        let scheduledTimes = isAsNeeded
            ? []
            : times
                .sorted(by: { $0 < $1 })
                .map { Calendar.current.dateComponents([.hour, .minute], from: $0) }

        let shouldEnableReminders = remindersOverride ?? (!isAsNeeded && remindersEnabled)

        return Medication(
            id: newID,
            name: trimmedName,
            dose: dose.trimmingCharacters(in: .whitespacesAndNewlines),
            notes: notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : notes.trimmingCharacters(in: .whitespacesAndNewlines),
            timesOfDay: scheduledTimes,
            remindersEnabled: shouldEnableReminders,
            category: category,
            customCategoryName: category == .custom ? customCategoryName.trimmingCharacters(in: .whitespacesAndNewlines) : nil,
            imagePath: imagePath,
            pillsRemaining: trackSupply ? pillsRemaining : nil,
            pillsPerDose: trackSupply ? pillsPerDose : nil,
            foodInstruction: foodInstruction,
            isAsNeeded: isAsNeeded ? true : nil,
            courseEndDate: hasCourseEnd ? courseEndDate : nil,
            specialInstructions: specialInstructions.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : specialInstructions.trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }
}

private extension AddMedicationView {
    private var scanLabelButton: some View {
        Button {
            if UIImagePickerController.isSourceTypeAvailable(.camera) {
                showOCRCamera = true
            } else {
                showCameraUnavailableAlert = true
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "camera.viewfinder")
                    .font(.system(size: 12, weight: .semibold))
                Text(NSLocalizedString("Scan Label", comment: ""))
                    .appFont(.caption)
                    .fontWeight(.semibold)
                if isOCRLoading {
                    ProgressView()
                        .controlSize(.small)
                }
            }
            .foregroundStyle(Color.accentColor)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(
                Capsule(style: .continuous)
                    .fill(Color.accentColor.opacity(0.10))
            )
            .overlay(
                Capsule(style: .continuous)
                    .stroke(Color.accentColor.opacity(0.18), lineWidth: 0.8)
            )
        }
        .buttonStyle(.plain)
    }

    var photoPreview: some View {
        Group {
            if let img = pickedImage {
                Image(uiImage: img)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 64, height: 64)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            } else {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color(.secondarySystemBackground))
                    .frame(width: 64, height: 64)
                    .overlay(
                        Image(systemName: "photo")
                            .foregroundStyle(.secondary)
                    )
            }
        }
    }

    var photoAttachmentRow: some View {
        HStack(spacing: 12) {
            photoPreview

            Spacer(minLength: 8)

            PhotosPicker(selection: $pickedItem, matching: .images) {
                Image(systemName: pickedImage == nil ? "photo" : "arrow.triangle.2.circlepath")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 38, height: 38)
                    .background(
                        Circle()
                            .fill(Color.accentColor.opacity(0.10))
                    )
            }
            .buttonStyle(.plain)
            .accessibilityLabel(pickedImage == nil ? NSLocalizedString("Add Photo", comment: "") : NSLocalizedString("Change Photo", comment: ""))
            .onChange(of: pickedItem) { newItem in
                Task {
                    if let data = try? await newItem?.loadTransferable(type: Data.self),
                       let ui = UIImage(data: data) {
                        pickedImage = ui
                    }
                }
            }

            if pickedImage != nil {
                Button(role: .destructive) {
                    pickedImage = nil
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.red)
                        .frame(width: 38, height: 38)
                        .background(
                            Circle()
                                .fill(Color.red.opacity(0.10))
                        )
                }
                .buttonStyle(.plain)
                .accessibilityLabel(NSLocalizedString("Remove Photo", comment: ""))
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(.secondarySystemBackground))
        )
    }

    var summaryLine: String {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let displayName = trimmedName.isEmpty ? NSLocalizedString("Medication name", comment: "") : trimmedName
        let trimmedDose = dose.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedDose.isEmpty {
            return displayName
        }
        return "\(displayName) · \(trimmedDose)"
    }

    var secondarySummaryLine: String {
        if isAsNeeded {
            return NSLocalizedString("As needed medication with no fixed reminder schedule.", comment: "")
        }

        if times.isEmpty {
            return remindersEnabled
                ? NSLocalizedString("No reminder times yet.", comment: "")
                : NSLocalizedString("Scheduled medication without reminders.", comment: "")
        }

        let formatter = DateFormatter()
        formatter.timeStyle = .short
        let timeSummary = times.sorted(by: { $0 < $1 }).map { formatter.string(from: $0) }.joined(separator: " · ")
        if remindersEnabled {
            return String(format: NSLocalizedString("Scheduled at %@", comment: ""), timeSummary)
        }
        return String(format: NSLocalizedString("Times saved without reminders: %@", comment: ""), timeSummary)
    }

    @ViewBuilder
    private func textInputCard(
        title: String,
        placeholder: String,
        text: Binding<String>,
        field: EntryField,
        axis: Axis = .horizontal,
        lineLimit: ClosedRange<Int> = 1...1
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .appFont(.caption)
                .foregroundStyle(.secondary)

            TextField(placeholder, text: text, axis: axis)
                .focused($focusedField, equals: field)
                .lineLimit(lineLimit)
                .textFieldStyle(.plain)
                .appFont(field == .name || field == .dose ? .subheadline : .body)
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color(.secondarySystemBackground))
                )
        }
    }

    private func quickSupplyButton(title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .appFont(.caption)
                .fontWeight(.semibold)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 7)
                .background(
                    Capsule(style: .continuous)
                        .fill(Color(.secondarySystemBackground))
                )
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func intakeModeButton(
        title: String,
        subtitle: String,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .appFont(.label)
                    .fontWeight(.semibold)
                Text(subtitle)
                    .appFont(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(isSelected ? Color.accentColor.opacity(0.12) : Color(.secondarySystemBackground))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(isSelected ? Color.accentColor.opacity(0.45) : Color.primary.opacity(0.06), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func schedulePresetButton(_ preset: SchedulePreset) -> some View {
        let isSelected = schedulePreset == preset
        Button {
            if preset == .custom {
                schedulePreset = .custom
                if times.isEmpty {
                    times = [defaultCustomTime(after: nil)]
                }
            } else {
                applySchedulePreset(preset)
            }
        } label: {
            HStack(spacing: 8) {
                Text(preset.title)
                    .appFont(.label)
                    .fontWeight(.semibold)
                    .foregroundStyle(isSelected ? Color.accentColor : Color.primary)
                Spacer(minLength: 0)
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.accentColor)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(isSelected ? Color.accentColor.opacity(0.12) : Color(.secondarySystemBackground))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(isSelected ? Color.accentColor.opacity(0.45) : Color.primary.opacity(0.06), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private func secondaryActionLabel(_ title: String, systemImage: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage)
                .font(.system(size: 13, weight: .semibold))
            Text(title)
                .appFont(.label)
                .fontWeight(.semibold)
        }
        .foregroundStyle(Color.accentColor)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.accentColor.opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.accentColor.opacity(0.14), lineWidth: 0.8)
        )
    }

    @ViewBuilder
    private func timeRow(for idx: Int) -> some View {
        HStack(spacing: 10) {
            DatePicker(
                String(format: NSLocalizedString("Time %lld", comment: ""), idx + 1),
                selection: Binding(
                    get: { times[idx] },
                    set: { newValue in
                        schedulePreset = .custom
                        times[idx] = newValue
                    }
                ),
                displayedComponents: .hourAndMinute
            )

            Button(role: .destructive) {
                schedulePreset = .custom
                times.remove(at: idx)
            } label: {
                Image(systemName: "minus.circle.fill")
                    .font(.title3)
                    .foregroundStyle(.red)
            }
            .buttonStyle(.plain)
        }
    }

    private func applySchedulePreset(_ preset: SchedulePreset) {
        schedulePreset = preset
        let calendar = Calendar.current
        let today = Date()

        func makeTime(hour: Int, minute: Int) -> Date {
            calendar.date(bySettingHour: hour, minute: minute, second: 0, of: today) ?? today
        }

        switch preset {
        case .onceDaily:
            times = [makeTime(hour: 8, minute: 0)]
        case .twiceDaily:
            times = [makeTime(hour: 8, minute: 0), makeTime(hour: 20, minute: 0)]
        case .morningEvening:
            times = [makeTime(hour: 9, minute: 0), makeTime(hour: 18, minute: 0)]
        case .custom:
            break
        }
    }

    func defaultCustomTime(after previous: Date?) -> Date {
        guard let previous else {
            return Calendar.current.date(bySettingHour: 8, minute: 0, second: 0, of: Date()) ?? Date()
        }
        return previous.addingTimeInterval(4 * 3600)
    }
}

private struct MedicationOCRReviewSheet: View {
    let suggestion: MedicationOCRSuggestion
    let onApply: (MedicationOCRSuggestion) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var editedName: String
    @State private var editedDose: String
    @State private var editedNotes: String

    private var editedSuggestion: MedicationOCRSuggestion {
        MedicationOCRSuggestion(
            name: trimmedOrNil(editedName),
            dose: trimmedOrNil(editedDose),
            notes: trimmedOrNil(editedNotes),
            rawText: suggestion.rawText
        )
    }

    private var canApply: Bool {
        editedSuggestion.hasUsefulContent
    }

    init(suggestion: MedicationOCRSuggestion, onApply: @escaping (MedicationOCRSuggestion) -> Void) {
        self.suggestion = suggestion
        self.onApply = onApply
        _editedName = State(initialValue: suggestion.name ?? "")
        _editedDose = State(initialValue: suggestion.dose ?? "")
        _editedNotes = State(initialValue: suggestion.notes ?? "")
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Label(NSLocalizedString("OCR suggestions can be wrong. Confirm the medication name and dose before applying.", comment: ""), systemImage: "exclamationmark.triangle.fill")
                        .appFont(.caption)
                        .foregroundStyle(.orange)
                }

                Section(NSLocalizedString("Review Fields", comment: "")) {
                    TextField(NSLocalizedString("Medication Name", comment: ""), text: $editedName)
                        .textInputAutocapitalization(.words)
                    TextField(NSLocalizedString("Dose", comment: ""), text: $editedDose)
                    TextField(NSLocalizedString("Special Instructions", comment: ""), text: $editedNotes, axis: .vertical)
                        .lineLimit(2...4)
                }

                if !suggestion.hasUsefulContent {
                    Section {
                        Text(NSLocalizedString("No confident fields were detected. You can still copy from the raw text below.", comment: ""))
                            .appFont(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Section(NSLocalizedString("Raw Text", comment: "")) {
                    Text(suggestion.rawText.isEmpty ? NSLocalizedString("No OCR text found.", comment: "") : suggestion.rawText)
                        .appFont(.caption)
                        .textSelection(.enabled)
                }
            }
            .navigationTitle(NSLocalizedString("Review OCR Result", comment: ""))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(NSLocalizedString("Apply", comment: "")) {
                        onApply(editedSuggestion)
                        dismiss()
                    }
                    .disabled(!canApply)
                }
            }
        }
    }

    private func trimmedOrNil(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
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
    @State private var schedulePreset: EditSchedulePreset = .custom
    @State private var showPRNConfirmation = false
    @State private var showAdditionalContext = false
    @FocusState private var focusedField: EditEntryField?

    private enum EditEntryField: Hashable {
        case name
        case dose
        case notes
        case specialInstructions
        case customCategory
    }

    private enum EditSchedulePreset: String, CaseIterable, Identifiable {
        case onceDaily
        case twiceDaily
        case morningEvening
        case custom

        var id: String { rawValue }

        var title: LocalizedStringKey {
            switch self {
            case .onceDaily: return "Once Daily"
            case .twiceDaily: return "Twice Daily"
            case .morningEvening: return "Morning + Evening"
            case .custom: return "Custom"
            }
        }

        var subtitle: LocalizedStringKey {
            switch self {
            case .onceDaily: return "1 reminder"
            case .twiceDaily: return "2 reminders"
            case .morningEvening: return "AM + PM"
            case .custom: return "Edit times manually"
            }
        }
    }

    private var refillThresholdDays: Int {
        UserDefaults.standard.object(forKey: "prefs.refillThresholdDays") as? Int ?? 7
    }

    private var courseReminderThresholdDays: Int {
        UserDefaults.standard.object(forKey: "prefs.courseEndThresholdDays") as? Int ?? 3
    }

    private var estimatedSupplyDays: Int? {
        guard trackSupply else { return nil }
        guard !isAsNeeded, !times.isEmpty else { return nil }
        let dosesPerDay = max(times.count, 1)
        let pillsPerDay = max(pillsPerDose * dosesPerDay, 1)
        return pillsRemaining / pillsPerDay
    }

    private var courseDaysRemaining: Int? {
        let draft = previewMedication()
        return draft.daysUntilCourseEnd()
    }

    private var editQuickPillButtons: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(NSLocalizedString("Quick fill", comment: ""))
                .appFont(.caption)
                .foregroundStyle(.secondary)
            HStack(spacing: 8) {
                ForEach([30, 60, 90], id: \.self) { value in
                    editQuickSupplyButton(title: "+\(value)") {
                        pillsRemaining += value
                    }
                }
            }
        }
    }

    private var editQuickCourseButtons: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(NSLocalizedString("Quick extend", comment: ""))
                .appFont(.caption)
                .foregroundStyle(.secondary)
            HStack(spacing: 8) {
                editQuickSupplyButton(title: NSLocalizedString("+7 d", comment: "")) {
                    courseEndDate = Calendar.current.date(byAdding: .day, value: 7, to: courseEndDate) ?? courseEndDate
                }
                editQuickSupplyButton(title: NSLocalizedString("+14 d", comment: "")) {
                    courseEndDate = Calendar.current.date(byAdding: .day, value: 14, to: courseEndDate) ?? courseEndDate
                }
                editQuickSupplyButton(title: NSLocalizedString("+30 d", comment: "")) {
                    courseEndDate = Calendar.current.date(byAdding: .day, value: 30, to: courseEndDate) ?? courseEndDate
                }
            }
        }
    }

    init(medication: Medication, onSave: @escaping (Medication) -> Void, onDelete: (() -> Void)? = nil) {
        self.medication = medication
        self.onSave = onSave
        self.onDelete = onDelete
        // State will be initialized in .onAppear to avoid SwiftUI init warnings
    }

    var body: some View {
        NavigationStack {
            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 16) {
                    Card {
                        VStack(alignment: .leading, spacing: 14) {
                            Text(NSLocalizedString("Medication", comment: ""))
                                .appFont(.headline)

                            editTextInputCard(
                                title: NSLocalizedString("Medication Name", comment: ""),
                                placeholder: NSLocalizedString("Amlodipine", comment: ""),
                                text: $name,
                                field: .name
                            )

                            editTextInputCard(
                                title: NSLocalizedString("Dose", comment: ""),
                                placeholder: NSLocalizedString("5 mg", comment: ""),
                                text: $dose,
                                field: .dose
                            )

                            Divider()

                            Text(NSLocalizedString("How do you take it?", comment: ""))
                                .appFont(.headline)

                            HStack(spacing: 10) {
                                editIntakeModeButton(
                                    title: NSLocalizedString("Scheduled", comment: ""),
                                    subtitle: NSLocalizedString("Daily reminders", comment: ""),
                                    isSelected: !isAsNeeded
                                ) {
                                    isAsNeeded = false
                                    if times.isEmpty {
                                        schedulePreset = .onceDaily
                                        applyEditSchedulePreset(.onceDaily)
                                    }
                                    remindersEnabled = true
                                }

                                editIntakeModeButton(
                                    title: NSLocalizedString("As Needed", comment: ""),
                                    subtitle: NSLocalizedString("Log only when taken", comment: ""),
                                    isSelected: isAsNeeded
                                ) {
                                    requestEditSwitchToPRN()
                                }
                            }
                        }
                    }

                    if isAsNeeded {
                        Card {
                            VStack(alignment: .leading, spacing: 10) {
                                Text(NSLocalizedString("PRN Medication", comment: ""))
                                    .appFont(.headline)
                                Text(NSLocalizedString("As-needed medications skip fixed reminder times. You can still log each dose from the Today screen whenever you take it.", comment: ""))
                                    .appFont(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    } else {
                        Card {
                            VStack(alignment: .leading, spacing: 14) {
                                HStack(alignment: .firstTextBaseline, spacing: 10) {
                                    Text(NSLocalizedString("Schedule", comment: ""))
                                        .appFont(.headline)
                                    Spacer()
                                    Text(times.isEmpty ? NSLocalizedString("Needs time", comment: "") : scheduleTimeCountText)
                                        .appFont(.caption)
                                        .fontWeight(.semibold)
                                        .foregroundStyle(times.isEmpty ? .orange : Color.accentColor)
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 6)
                                        .background(
                                            Capsule(style: .continuous)
                                                .fill((times.isEmpty ? Color.orange : Color.accentColor).opacity(0.10))
                                        )
                                }

                                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                                    ForEach(EditSchedulePreset.allCases) { preset in
                                        editSchedulePresetButton(preset)
                                    }
                                }

                                VStack(alignment: .leading, spacing: 10) {
                                    if times.isEmpty {
                                        Text(NSLocalizedString("Choose a preset or add a custom time.", comment: ""))
                                            .appFont(.caption)
                                            .foregroundStyle(.secondary)
                                    } else {
                                        ForEach(Array(times.indices), id: \.self) { idx in
                                            editTimeRow(for: idx)
                                        }
                                    }
                                }
                                .padding(12)
                                .background(
                                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                                        .fill(Color(.secondarySystemBackground))
                                )

                                Button {
                                    schedulePreset = .custom
                                    times.append(defaultEditCustomTime(after: times.last))
                                } label: {
                                    editSecondaryActionLabel(NSLocalizedString("Add Time", comment: ""), systemImage: "plus.circle.fill")
                                }
                                .buttonStyle(.plain)

                                editToggleRow(
                                    title: NSLocalizedString("Remind Me", comment: ""),
                                    subtitle: remindersEnabled
                                        ? NSLocalizedString("Notifications will be scheduled for these times.", comment: "")
                                        : NSLocalizedString("Times are saved, but notifications are off.", comment: ""),
                                    systemImage: remindersEnabled ? "bell.fill" : "bell.slash.fill",
                                    isOn: $remindersEnabled
                                )

                                if remindersEnabled && times.isEmpty {
                                    Label(NSLocalizedString("Add at least one time for reminders", comment: ""), systemImage: "exclamationmark.triangle.fill")
                                        .appFont(.caption)
                                        .foregroundStyle(.orange)
                                }
                            }
                        }
                    }

                    Card {
                        VStack(alignment: .leading, spacing: 14) {
                            Text(NSLocalizedString("Instructions", comment: ""))
                                .appFont(.headline)

                            editPickerRow(
                                title: NSLocalizedString("Food Instruction", comment: ""),
                                systemImage: "fork.knife",
                                selection: $foodInstruction
                            ) {
                                Text(NSLocalizedString("None", comment: "")).tag(FoodInstruction?.none)
                                ForEach(FoodInstruction.allCases) { fi in
                                    Text(fi.displayName).tag(FoodInstruction?.some(fi))
                                }
                            }

                            editTextInputCard(
                                title: NSLocalizedString("Special Instructions", comment: ""),
                                placeholder: NSLocalizedString("Take after dinner", comment: ""),
                                text: $specialInstructions,
                                field: .specialInstructions,
                                axis: .vertical,
                                lineLimit: 2...4
                            )

                            DisclosureGroup(isExpanded: $showAdditionalContext) {
                                editTextInputCard(
                                    title: NSLocalizedString("Notes", comment: ""),
                                    placeholder: NSLocalizedString("Optional context", comment: ""),
                                    text: $notes,
                                    field: .notes,
                                    axis: .vertical,
                                    lineLimit: 2...4
                                )
                                .padding(.top, 6)
                            } label: {
                                HStack {
                                    Text(NSLocalizedString("Additional Context", comment: ""))
                                        .appFont(.subheadline)
                                        .fontWeight(.semibold)
                                    Spacer()
                                    Text(notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? NSLocalizedString("Optional", comment: "") : NSLocalizedString("Added", comment: ""))
                                        .appFont(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }

                    Card {
                        VStack(alignment: .leading, spacing: 14) {
                            Text(NSLocalizedString("Supply & Course", comment: ""))
                                .appFont(.headline)

                            Toggle(NSLocalizedString("Track Supply", comment: ""), isOn: $trackSupply)
                            if trackSupply {
                                Stepper(value: $pillsRemaining, in: 0...999) {
                                    Text(String(format: NSLocalizedString("Pills remaining: %lld", comment: ""), pillsRemaining))
                                }
                                Stepper(value: $pillsPerDose, in: 1...10) {
                                    Text(String(format: NSLocalizedString("Pills per dose: %lld", comment: ""), pillsPerDose))
                                }
                                editQuickPillButtons
                                if let estimatedSupplyDays {
                                    Text(String(format: NSLocalizedString("About %lld days of supply at your current schedule.", comment: ""), estimatedSupplyDays))
                                        .appFont(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Text(String(format: NSLocalizedString("Refill reminders start when about %lld days remain.", comment: ""), refillThresholdDays))
                                    .appFont(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            Toggle(NSLocalizedString("Has Course End Date", comment: ""), isOn: $hasCourseEnd)
                            if hasCourseEnd {
                                DatePicker(NSLocalizedString("End Date", comment: ""), selection: $courseEndDate, displayedComponents: .date)
                                editQuickCourseButtons
                                if let courseDaysRemaining {
                                    Text(String(format: NSLocalizedString("Course ends in %lld days.", comment: ""), max(courseDaysRemaining, 0)))
                                        .appFont(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Text(String(format: NSLocalizedString("Course reminders start %lld days before the end date.", comment: ""), courseReminderThresholdDays))
                                    .appFont(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }

                    Card {
                        VStack(alignment: .leading, spacing: 14) {
                            Text(NSLocalizedString("Category & Photo", comment: ""))
                                .appFont(.headline)

                            editPickerRow(
                                title: NSLocalizedString("Category", comment: ""),
                                systemImage: "tag.fill",
                                selection: $category
                            ) {
                                ForEach(MedicationCategory.allCases) { c in
                                    Text(c.displayName).tag(c)
                                }
                            }

                            if category == .custom {
                                editTextInputCard(
                                    title: NSLocalizedString("Custom Category", comment: ""),
                                    placeholder: NSLocalizedString("Cardiology", comment: ""),
                                    text: $customCategoryName,
                                    field: .customCategory
                                )
                            }

                            editPhotoAttachmentRow
                        }
                    }

                    if onDelete != nil {
                        Card {
                            Button(role: .destructive) {
                                onDelete?()
                                dismiss()
                            } label: {
                                Text(NSLocalizedString("Delete Medication", comment: ""))
                                    .appFont(.subheadline)
                                    .foregroundStyle(.red)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 6)
                            }
                        }
                    }
                }
                .padding(16)
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
                schedulePreset = .custom
                showAdditionalContext = !notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                focusedField = .name
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        if !isAsNeeded && remindersEnabled && times.isEmpty {
                            showScheduleAlert = true
                            return
                        }
                        saveAndDismiss()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button(NSLocalizedString("Done", comment: "")) {
                        focusedField = nil
                    }
                }
            }
            .alert(NSLocalizedString("No Schedule Set", comment: ""), isPresented: $showScheduleAlert) {
                Button(NSLocalizedString("Add Time", comment: "")) {
                    schedulePreset = .custom
                    times.append(defaultEditCustomTime(after: nil))
                }
                Button(NSLocalizedString("Save Without Reminders", comment: "")) {
                    remindersEnabled = false
                    saveAndDismiss()
                }
            } message: {
                Text(NSLocalizedString("Reminders are enabled but no times are set. Add a time or save without reminders.", comment: ""))
            }
            .alert(NSLocalizedString("Switch to As Needed?", comment: ""), isPresented: $showPRNConfirmation) {
                Button(NSLocalizedString("Keep Scheduled", comment: ""), role: .cancel) { }
                Button(NSLocalizedString("Switch", comment: ""), role: .destructive) {
                    confirmEditSwitchToPRN()
                }
            } message: {
                Text(NSLocalizedString("This will turn off fixed reminders for this medication and clear its scheduled times.", comment: ""))
            }
        }
    }

    private func saveAndDismiss() {
        let comps = isAsNeeded ? [] : times.sorted(by: { $0 < $1 }).map { Calendar.current.dateComponents([.hour, .minute], from: $0) }
        var updated = medication
        updated.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        updated.dose = dose.trimmingCharacters(in: .whitespacesAndNewlines)
        updated.notes = notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : notes.trimmingCharacters(in: .whitespacesAndNewlines)
        updated.timesOfDay = comps
        updated.remindersEnabled = isAsNeeded ? false : remindersEnabled
        updated.category = category
        updated.customCategoryName = category == .custom ? customCategoryName.trimmingCharacters(in: .whitespacesAndNewlines) : nil
        updated.pillsRemaining = trackSupply ? pillsRemaining : nil
        updated.pillsPerDose = trackSupply ? pillsPerDose : nil
        updated.foodInstruction = foodInstruction
        updated.isAsNeeded = isAsNeeded ? true : nil
        updated.courseEndDate = hasCourseEnd ? courseEndDate : nil
        updated.specialInstructions = specialInstructions.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : specialInstructions.trimmingCharacters(in: .whitespacesAndNewlines)
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

    private func previewMedication() -> Medication {
        let comps = isAsNeeded ? [] : times.sorted(by: { $0 < $1 }).map { Calendar.current.dateComponents([.hour, .minute], from: $0) }
        var updated = medication
        updated.timesOfDay = comps
        updated.pillsRemaining = trackSupply ? pillsRemaining : nil
        updated.pillsPerDose = trackSupply ? pillsPerDose : nil
        updated.isAsNeeded = isAsNeeded ? true : nil
        updated.courseEndDate = hasCourseEnd ? courseEndDate : nil
        return updated
    }

    private func requestEditSwitchToPRN() {
        guard !isAsNeeded else { return }
        if remindersEnabled || !times.isEmpty {
            showPRNConfirmation = true
        } else {
            confirmEditSwitchToPRN()
        }
    }

    private func confirmEditSwitchToPRN() {
        isAsNeeded = true
        remindersEnabled = false
        times = []
        schedulePreset = .custom
    }
}

private extension EditMedicationView {
    var medicationStatusCard: some View {
        let strategy = AdaptiveReminderEngine.strategy(for: previewMedication(), intakeLogs: store.intakeLogs)
        let profile = AdaptiveReminderEngine.profile(for: previewMedication(), intakeLogs: store.intakeLogs)

        return Card {
            VStack(alignment: .leading, spacing: 14) {
                Text(NSLocalizedString("Medication Status", comment: ""))
                    .appFont(.headline)

                HStack(spacing: 12) {
                    adherenceMetric(
                        value: lastTakenDisplay,
                        label: NSLocalizedString("Last taken", comment: ""),
                        tint: .green
                    )
                    adherenceMetric(
                        value: nextDoseDisplay,
                        label: NSLocalizedString("Next dose", comment: ""),
                        tint: .blue
                    )
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text(NSLocalizedString("Reminder Strategy", comment: ""))
                        .appFont(.caption)
                        .foregroundStyle(.secondary)
                    Text(reminderStateSummary(strategy: strategy))
                        .appFont(.subheadline)
                        .foregroundStyle(.primary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(reminderExplanation(strategy: strategy, profile: profile))
                        .appFont(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    var medicationMaintenanceCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 14) {
                Text(NSLocalizedString("Maintenance Status", comment: ""))
                    .appFont(.headline)

                if trackSupply {
                    maintenanceRow(
                        title: NSLocalizedString("Inventory", comment: ""),
                        message: supplyStatusText,
                        tint: supplyStatusTint,
                        emphasized: supplyNeedsAttention
                    )
                }

                if hasCourseEnd {
                    maintenanceRow(
                        title: NSLocalizedString("Course", comment: ""),
                        message: courseStatusText,
                        tint: courseStatusTint,
                        emphasized: courseNeedsAttention
                    )
                }
            }
        }
    }

    var adherenceOverviewCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 14) {
                Text(NSLocalizedString("Adherence", comment: ""))
                    .appFont(.headline)

                if hasLogs {
                    HStack(spacing: 12) {
                        adherenceMetric(
                            value: String(format: "%.0f%%", adherence7 * 100),
                            label: NSLocalizedString("7-day", comment: ""),
                            tint: adherence7 >= 0.8 ? .green : adherence7 >= 0.5 ? .orange : .red
                        )
                        adherenceMetric(
                            value: String(format: "%.0f%%", adherence30 * 100),
                            label: NSLocalizedString("30-day", comment: ""),
                            tint: adherence30 >= 0.8 ? .green : adherence30 >= 0.5 ? .orange : .red
                        )
                        adherenceMetric(
                            value: "\(streakCount)",
                            label: NSLocalizedString("day streak", comment: ""),
                            tint: .blue
                        )
                    }
                } else {
                    HStack(spacing: 10) {
                        Image(systemName: "chart.bar")
                            .foregroundStyle(.secondary)
                        Text(NSLocalizedString("Log your first dose to see stats here.", comment: ""))
                            .appFont(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    var hasLogs: Bool {
        store.intakeLogs.contains { $0.medicationID == medication.id }
    }

    var lastTakenDisplay: String {
        guard let lastTaken = store.intakeLogs
            .filter({ $0.medicationID == medication.id && $0.status == .taken })
            .max(by: { $0.effectiveRecordedAt < $1.effectiveRecordedAt }) else {
            return NSLocalizedString("None", comment: "")
        }

        if Calendar.current.isDateInToday(lastTaken.effectiveRecordedAt) {
            return lastTaken.effectiveRecordedAt.formatted(date: .omitted, time: .shortened)
        }

        return lastTaken.effectiveRecordedAt.formatted(date: .abbreviated, time: .shortened)
    }

    var nextDoseDisplay: String {
        let med = previewMedication()
        guard med.isAsNeeded != true else {
            return NSLocalizedString("PRN", comment: "")
        }
        guard med.remindersEnabled else {
            return NSLocalizedString("Off", comment: "")
        }

        let calendar = Calendar.current
        let now = Date()
        let sorted = med.timesOfDay.sorted { ($0.hour ?? 0, $0.minute ?? 0) < ($1.hour ?? 0, $1.minute ?? 0) }
        for offset in 0..<2 {
            guard let day = calendar.date(byAdding: .day, value: offset, to: calendar.startOfDay(for: now)) else { continue }
            for comps in sorted {
                guard let hour = comps.hour,
                      let minute = comps.minute,
                      let scheduled = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day),
                      scheduled >= now else { continue }
                return scheduled.formatted(offset == 0 ? .dateTime.hour().minute() : .dateTime.weekday(.abbreviated).hour().minute())
            }
        }

        return NSLocalizedString("Not scheduled", comment: "")
    }

    var adherence7: Double {
        store.adherencePercent(for: medication.id, days: 7)
    }

    var adherence30: Double {
        store.adherencePercent(for: medication.id, days: 30)
    }

    var streakCount: Int {
        store.currentStreak(for: medication.id)
    }

    func reminderStateSummary(strategy: AdaptiveReminderStrategy) -> String {
        let med = previewMedication()
        if med.isAsNeeded == true {
            return NSLocalizedString("This medication is set to as-needed, so fixed reminders are off.", comment: "")
        }
        if !med.remindersEnabled {
            return NSLocalizedString("Fixed reminders are turned off for this medication.", comment: "")
        }
        if med.timesOfDay.isEmpty {
            return NSLocalizedString("No reminder times are set yet.", comment: "")
        }

        var parts: [String] = []
        if strategy.leadMinutes > 0 {
            parts.append(String(format: NSLocalizedString("Starts %lld minutes early", comment: ""), strategy.leadMinutes))
        } else {
            parts.append(NSLocalizedString("Starts at the scheduled time", comment: ""))
        }

        if strategy.followUpIntervals.isEmpty {
            parts.append(NSLocalizedString("No follow-up reminders", comment: ""))
        } else {
            parts.append(String(format: NSLocalizedString("%lld follow-up reminders", comment: ""), strategy.followUpIntervals.count))
        }

        return parts.joined(separator: " · ")
    }

    func reminderExplanation(strategy: AdaptiveReminderStrategy, profile: AdherenceProfile) -> String {
        let med = previewMedication()
        if med.isAsNeeded == true {
            return NSLocalizedString("Log doses from Today whenever you take this medication.", comment: "")
        }
        if !med.remindersEnabled {
            return NSLocalizedString("Turn reminders back on if you want this medication to appear in notification scheduling.", comment: "")
        }
        if profile.sampleCount == 0 {
            return NSLocalizedString("The reminder engine will adapt after you log more scheduled doses.", comment: "")
        }

        switch strategy.riskLevel {
        case .high:
            return String(format: NSLocalizedString("Recent history shows a higher miss rate. The app is using a stronger reminder pattern with %lld follow-ups.", comment: ""), strategy.followUpIntervals.count)
        case .medium:
            return String(format: NSLocalizedString("Recent history shows some delays or snoozes. The app is keeping a balanced reminder pattern with %lld follow-ups.", comment: ""), strategy.followUpIntervals.count)
        case .low:
            return NSLocalizedString("Recent history looks consistent, so the app is keeping reminders lighter to reduce noise.", comment: "")
        }
    }

    var supplyStatusText: String {
        guard trackSupply else { return NSLocalizedString("Supply tracking is off.", comment: "") }
        if pillsRemaining == 0 {
            return NSLocalizedString("You are out of pills. Refill now to keep reminders useful.", comment: "")
        }
        if let estimatedSupplyDays, estimatedSupplyDays <= refillThresholdDays {
            return String(format: NSLocalizedString("About %lld days of supply remain. Consider refilling now.", comment: ""), estimatedSupplyDays)
        }
        if let estimatedSupplyDays {
            return String(format: NSLocalizedString("About %lld days of supply remain.", comment: ""), estimatedSupplyDays)
        }
        return String(format: NSLocalizedString("%lld pills remaining.", comment: ""), pillsRemaining)
    }

    var supplyStatusTint: Color {
        if pillsRemaining == 0 { return .red }
        if let estimatedSupplyDays, estimatedSupplyDays <= refillThresholdDays { return .orange }
        return .secondary
    }

    var supplyNeedsAttention: Bool {
        pillsRemaining == 0 || ((estimatedSupplyDays ?? .max) <= refillThresholdDays)
    }

    var courseStatusText: String {
        guard let courseState = previewMedication().courseState(thresholdDays: courseReminderThresholdDays) else {
            return NSLocalizedString("No course end date set.", comment: "")
        }
        switch courseState {
        case .ended(let daysPast):
            return String(format: NSLocalizedString("This course ended %lld days ago. Confirm whether it should continue.", comment: ""), daysPast)
        case .endsToday:
            return NSLocalizedString("This course ends today. Confirm whether it should continue.", comment: "")
        case .endingSoon(let daysRemaining):
            return String(format: NSLocalizedString("This course ends in %lld days.", comment: ""), daysRemaining)
        case .scheduled(let daysRemaining):
            return String(format: NSLocalizedString("This course ends in %lld days.", comment: ""), daysRemaining)
        }
    }

    var courseStatusTint: Color {
        guard let courseState = previewMedication().courseState(thresholdDays: courseReminderThresholdDays) else { return .secondary }
        switch courseState {
        case .ended:
            return .red
        case .endsToday, .endingSoon:
            return .orange
        case .scheduled:
            return .secondary
        }
    }

    var courseNeedsAttention: Bool {
        guard let courseState = previewMedication().courseState(thresholdDays: courseReminderThresholdDays) else { return false }
        switch courseState {
        case .ended, .endsToday, .endingSoon:
            return true
        case .scheduled:
            return false
        }
    }

    var editCorrelatedTypes: [MeasurementType] {
        let currentCategory: MedicationCategory? = category == .unspecified ? nil : category
        return currentCategory?.correlatedMeasurementTypes ?? []
    }

    var scheduleTimeCountText: String {
        String(format: NSLocalizedString("%lld times", comment: ""), times.count)
    }

    var editHasPhoto: Bool {
        pickedImage != nil || (medication.imagePath != nil && !removePhoto)
    }

    var editPhotoAttachmentRow: some View {
        HStack(spacing: 12) {
            editPhotoPreview

            Spacer(minLength: 8)

            PhotosPicker(selection: $pickedItem, matching: .images) {
                Image(systemName: editHasPhoto ? "arrow.triangle.2.circlepath" : "photo")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 38, height: 38)
                    .background(
                        Circle()
                            .fill(Color.accentColor.opacity(0.10))
                    )
            }
            .buttonStyle(.plain)
            .accessibilityLabel(editHasPhoto ? NSLocalizedString("Change Photo", comment: "") : NSLocalizedString("Add Photo", comment: ""))
            .onChange(of: pickedItem) { newItem in
                Task {
                    if let data = try? await newItem?.loadTransferable(type: Data.self),
                       let ui = UIImage(data: data) {
                        pickedImage = ui
                        removePhoto = false
                    }
                }
            }

            if editHasPhoto {
                Button(role: .destructive) {
                    pickedImage = nil
                    removePhoto = true
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.red)
                        .frame(width: 38, height: 38)
                        .background(
                            Circle()
                                .fill(Color.red.opacity(0.10))
                        )
                }
                .buttonStyle(.plain)
                .accessibilityLabel(NSLocalizedString("Remove Photo", comment: ""))
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(.secondarySystemBackground))
        )
    }

    var editPhotoPreview: some View {
        Group {
            if let img = pickedImage {
                Image(uiImage: img)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 72, height: 72)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            } else if !removePhoto, let existing = loadMedImage(path: medication.imagePath) {
                Image(uiImage: existing)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 72, height: 72)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            } else {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color(.secondarySystemBackground))
                    .frame(width: 72, height: 72)
                    .overlay(
                        Image(systemName: "photo")
                            .font(.system(size: 22, weight: .semibold))
                            .foregroundStyle(.secondary)
                    )
            }
        }
    }

    func relatedMeasurements(for type: MeasurementType) -> [Measurement]? {
        let data = store.measurements
            .filter { $0.type == type }
            .sorted { $0.date < $1.date }
            .suffix(30)
        return data.count >= 2 ? Array(data) : nil
    }

    @ViewBuilder
    func maintenanceRow(title: String, message: String, tint: Color, emphasized: Bool) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .appFont(.caption)
                .foregroundStyle(.secondary)
            Text(message)
                .appFont(.subheadline)
                .foregroundStyle(emphasized ? tint : .primary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    func adherenceMetric(value: String, label: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value)
                .appFont(.headline)
                .foregroundStyle(tint)
                .monospacedDigit()
            Text(label)
                .appFont(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(tint.opacity(0.08))
        )
    }

    @ViewBuilder
    private func editTextInputCard(
        title: String,
        placeholder: String,
        text: Binding<String>,
        field: EditEntryField,
        axis: Axis = .horizontal,
        lineLimit: ClosedRange<Int> = 1...1
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .appFont(.caption)
                .foregroundStyle(.secondary)

            TextField(placeholder, text: text, axis: axis)
                .focused($focusedField, equals: field)
                .lineLimit(lineLimit)
                .textFieldStyle(.plain)
                .appFont(field == .name || field == .dose ? .subheadline : .body)
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color(.secondarySystemBackground))
                )
        }
    }

    @ViewBuilder
    private func editPickerRow<SelectionValue: Hashable, Content: View>(
        title: String,
        systemImage: String,
        selection: Binding<SelectionValue>,
        @ViewBuilder content: () -> Content
    ) -> some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color.accentColor)
                .frame(width: 28, height: 28)
                .background(
                    Circle()
                        .fill(Color.accentColor.opacity(0.10))
                )

            Text(title)
                .appFont(.label)
                .fontWeight(.semibold)

            Spacer(minLength: 8)

            Picker(title, selection: selection) {
                content()
            }
            .labelsHidden()
            .pickerStyle(.menu)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(.secondarySystemBackground))
        )
    }

    @ViewBuilder
    private func editToggleRow(
        title: String,
        subtitle: String,
        systemImage: String,
        isOn: Binding<Bool>
    ) -> some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(isOn.wrappedValue ? Color.accentColor : Color.secondary)
                .frame(width: 28, height: 28)
                .background(
                    Circle()
                        .fill((isOn.wrappedValue ? Color.accentColor : Color.secondary).opacity(0.10))
                )

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .appFont(.label)
                    .fontWeight(.semibold)
                Text(subtitle)
                    .appFont(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 8)

            Toggle(title, isOn: isOn)
                .labelsHidden()
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(.secondarySystemBackground))
        )
    }

    private func editQuickSupplyButton(title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .appFont(.caption)
                .fontWeight(.semibold)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 7)
                .background(
                    Capsule(style: .continuous)
                        .fill(Color(.secondarySystemBackground))
                )
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func editIntakeModeButton(
        title: String,
        subtitle: String,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .appFont(.label)
                    .fontWeight(.semibold)
                Text(subtitle)
                    .appFont(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(isSelected ? Color.accentColor.opacity(0.12) : Color(.secondarySystemBackground))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(isSelected ? Color.accentColor.opacity(0.45) : Color.primary.opacity(0.06), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func editSchedulePresetButton(_ preset: EditSchedulePreset) -> some View {
        let isSelected = schedulePreset == preset
        Button {
            if preset == .custom {
                schedulePreset = .custom
                if times.isEmpty {
                    times = [defaultEditCustomTime(after: nil)]
                }
            } else {
                applyEditSchedulePreset(preset)
            }
        } label: {
            HStack(spacing: 8) {
                Text(preset.title)
                    .appFont(.label)
                    .fontWeight(.semibold)
                    .foregroundStyle(isSelected ? Color.accentColor : Color.primary)
                Spacer(minLength: 0)
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.accentColor)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(isSelected ? Color.accentColor.opacity(0.12) : Color(.secondarySystemBackground))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(isSelected ? Color.accentColor.opacity(0.45) : Color.primary.opacity(0.06), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private func editSecondaryActionLabel(_ title: String, systemImage: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage)
                .font(.system(size: 13, weight: .semibold))
            Text(title)
                .appFont(.label)
                .fontWeight(.semibold)
        }
        .foregroundStyle(Color.accentColor)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.accentColor.opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.accentColor.opacity(0.14), lineWidth: 0.8)
        )
    }

    @ViewBuilder
    private func editTimeRow(for idx: Int) -> some View {
        HStack(spacing: 10) {
            DatePicker(
                String(format: NSLocalizedString("Time %lld", comment: ""), idx + 1),
                selection: Binding(
                    get: { times[idx] },
                    set: { newValue in
                        schedulePreset = .custom
                        times[idx] = newValue
                    }
                ),
                displayedComponents: .hourAndMinute
            )

            Button(role: .destructive) {
                schedulePreset = .custom
                times.remove(at: idx)
            } label: {
                Image(systemName: "minus.circle.fill")
                    .font(.title3)
                    .foregroundStyle(.red)
            }
            .buttonStyle(.plain)
        }
    }

    private func applyEditSchedulePreset(_ preset: EditSchedulePreset) {
        schedulePreset = preset
        let calendar = Calendar.current
        let today = Date()

        func makeTime(hour: Int, minute: Int) -> Date {
            calendar.date(bySettingHour: hour, minute: minute, second: 0, of: today) ?? today
        }

        switch preset {
        case .onceDaily:
            times = [makeTime(hour: 8, minute: 0)]
        case .twiceDaily:
            times = [makeTime(hour: 8, minute: 0), makeTime(hour: 20, minute: 0)]
        case .morningEvening:
            times = [makeTime(hour: 9, minute: 0), makeTime(hour: 18, minute: 0)]
        case .custom:
            break
        }
    }

    func defaultEditCustomTime(after previous: Date?) -> Date {
        guard let previous else {
            return Calendar.current.date(bySettingHour: 8, minute: 0, second: 0, of: Date()) ?? Date()
        }
        return previous.addingTimeInterval(4 * 3600)
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
                case .remindersOn: return med.isAsNeeded != true && med.remindersEnabled
                case .remindersOff: return med.isAsNeeded != true && !med.remindersEnabled
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
        let active = store.medications.filter { $0.isAsNeeded != true && $0.remindersEnabled }.count
        let paused = store.medications.filter { $0.isAsNeeded != true && !$0.remindersEnabled }.count
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
                        if med.isAsNeeded != true && !med.remindersEnabled {
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
                if med.isAsNeeded != true {
                    reminderToggle(for: med)
                }
            }

            // Row 2: supply + status + quick-take (all inline)
            HStack(spacing: 8) {
                if let remaining = med.pillsRemaining {
                    compactSupplyLabel(remaining: remaining, med: med)
                }
                compactCourseLabel(for: med)
                if let (status, date) = latestTodayAction(for: med) {
                    inlineStatusLabel(status: status, date: date)
                }
                Spacer(minLength: 0)
                if med.isAsNeeded != true && med.remindersEnabled {
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
            if remaining == 0 {
                Text(NSLocalizedString("Out of pills", comment: ""))
                    .appFont(.caption)
                    .foregroundStyle(.red)
            } else if let days = med.daysOfSupplyRemaining, days > 0 {
                Text(String(format: NSLocalizedString("%lld pills · %lld d left", comment: "pills and days short"), remaining, days))
                    .appFont(.caption)
                    .foregroundStyle(isLow ? .red : .secondary)
            } else {
                Text(String(format: NSLocalizedString("%lld pills", comment: ""), remaining))
                    .appFont(.caption)
                    .foregroundStyle(isLow ? .red : .secondary)
            }
        }
    }

    @ViewBuilder
    private func compactCourseLabel(for med: Medication) -> some View {
        let threshold = UserDefaults.standard.object(forKey: "prefs.courseEndThresholdDays") as? Int ?? 3
        if let courseState = med.courseState(thresholdDays: threshold) {
            switch courseState {
            case .endingSoon(let daysRemaining):
                HStack(spacing: 4) {
                    Image(systemName: "calendar.badge.exclamationmark")
                        .font(.system(size: 13))
                    Text(String(format: NSLocalizedString("Ends in %lld d", comment: ""), daysRemaining))
                        .appFont(.caption)
                }
                .foregroundStyle(.orange)
            case .endsToday:
                HStack(spacing: 4) {
                    Image(systemName: "calendar.badge.exclamationmark")
                        .font(.system(size: 13))
                    Text(NSLocalizedString("Ends today", comment: ""))
                        .appFont(.caption)
                }
                .foregroundStyle(.orange)
            case .ended:
                HStack(spacing: 4) {
                    Image(systemName: "calendar.badge.exclamationmark")
                        .font(.system(size: 13))
                    Text(NSLocalizedString("Course ended", comment: ""))
                        .appFont(.caption)
                }
                .foregroundStyle(.red)
            default:
                EmptyView()
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
                store.upsertIntake(
                    medicationID: med.id,
                    status: .taken,
                    scheduleTime: dose.comps,
                    scheduledDate: dose.scheduledDate
                )
                store.decrementPills(for: med.id)
                NotificationManager.shared.suppressToday(for: med.id, timeComponents: dose.comps)
                NotificationManager.shared.cancelDoseNotifications(for: med.id, timeComponents: dose.comps)
                NotificationManager.shared.syncAll(medications: store.medications, intakeLogs: store.intakeLogs)
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

    private func nextUntakenDose(for med: Medication) -> (comps: DateComponents, scheduledDate: Date, timeStr: String)? {
        let cal = Calendar.current
        let now = Date()
        let dayStart = cal.startOfDay(for: now)
        guard let dayEnd = cal.date(byAdding: .day, value: 1, to: dayStart) else { return nil }
        let todayLogs = store.intakeLogs.filter { $0.medicationID == med.id && $0.date >= dayStart && $0.date < dayEnd }
        let sorted = med.timesOfDay.sorted { ($0.hour ?? 0) * 60 + ($0.minute ?? 0) < ($1.hour ?? 0) * 60 + ($1.minute ?? 0) }
        for comps in sorted {
            let key = String(format: "%02d:%02d", comps.hour ?? 0, comps.minute ?? 0)
            let resolved = todayLogs.contains { $0.scheduleKey == key && ($0.status == .taken || $0.status == .skipped) }
            guard !resolved,
                  let scheduledDate = cal.date(bySettingHour: comps.hour ?? 0, minute: comps.minute ?? 0, second: 0, of: now),
                  scheduledDate <= now else { continue }
            if !resolved {
                let formatter = DateFormatter()
                formatter.timeStyle = .short
                let timeStr = formatter.string(from: scheduledDate)
                return (comps, scheduledDate, timeStr)
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
                            NotificationManager.shared.syncAll(medications: store.medications, intakeLogs: store.intakeLogs)
                            NotificationManager.shared.updateBadge(store: store)
                            Haptics.impact(.light)
                            refreshNotificationStatus()
                        }
                    } else {
                        await MainActor.run {
                            var updated = med
                            updated.remindersEnabled = false
                            store.updateMedication(updated)
                            NotificationManager.shared.syncAll(medications: store.medications, intakeLogs: store.intakeLogs)
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
