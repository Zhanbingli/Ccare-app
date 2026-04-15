import SwiftUI
import PhotosUI
import UIKit

/// Unified medication add/edit form. Pass `editing` to pre-fill for edit mode.
struct MedicationFormView: View {
    let editing: Medication?
    var onSave: (Medication) -> String?
    var onDelete: (() -> Void)?
    @Environment(\.dismiss) private var dismiss

    // MARK: - Core medication fields
    @State private var name: String = ""
    @State private var dose: String = ""
    @State private var notes: String = ""
    @State private var category: MedicationCategory = .unspecified
    @State private var customCategoryName: String = ""

    // MARK: - Schedule
    @State private var times: [Date] = []
    @State private var remindersEnabled: Bool = true
    @State private var isAsNeeded: Bool = false
    @State private var schedulePreset: SchedulePreset = .custom
    @State private var hasCourseEnd: Bool = false
    @State private var courseEndDate: Date = Calendar.current.date(byAdding: .day, value: 7, to: Date()) ?? Date()

    // MARK: - Inventory
    @State private var trackSupply: Bool = false
    @State private var pillsRemainingText: String = "30"
    @State private var pillsPerDose: Int = 1
    @State private var foodInstruction: FoodInstruction?
    @State private var specialInstructions: String = ""

    // MARK: - Photo / OCR
    @State private var pickedItem: PhotosPickerItem? = nil
    @State private var pickedImage: UIImage? = nil
    @State private var removePhoto: Bool = false
    @State private var isOCRLoading = false
    @State private var ocrSuggestion: MedicationOCRSuggestion?
    @State private var ocrErrorMessage: String?

    // MARK: - UI presentation flags
    @State private var showScheduleAlert = false
    @State private var showOCRError = false
    @State private var showOCRCamera = false
    @State private var showCameraUnavailableAlert = false
    @State private var showPRNConfirmation = false
    @State private var showInstructionsDetails = false
    @State private var showInventoryDetails = false
    @State private var showCategoryDetails = false
    @State private var showAddOptionalDetails = false
    @State private var showSaveError = false
    @State private var saveErrorMessage: String?
    @FocusState private var focusedField: EntryField?

    // MARK: - Validation
    @State private var nameValidation: ValidationResult = .valid
    @State private var scheduleValidation: ValidationResult = .valid
    @State private var courseEndValidation: ValidationResult = .valid

    private var isEditing: Bool { editing != nil }

    private var pillsRemaining: Int {
        Int(pillsRemainingText) ?? 0
    }

    init(editing: Medication? = nil, onSave: @escaping (Medication) -> String?, onDelete: (() -> Void)? = nil) {
        self.editing = editing
        self.onSave = onSave
        self.onDelete = onDelete
    }

    // MARK: - Shared Types

    enum EntryField: Hashable {
        case name, dose, notes, specialInstructions, customCategory, pillsRemaining
    }

    private enum IntakeMode: String, CaseIterable, Identifiable {
        case scheduled, asNeeded
        var id: String { rawValue }
    }

    enum SchedulePreset: String, CaseIterable, Identifiable {
        case onceDaily, twiceDaily, threeTimesDaily, custom
        var id: String { rawValue }

        var shortLabel: String {
            switch self {
            case .onceDaily: return NSLocalizedString("1×/day", comment: "Once daily short")
            case .twiceDaily: return NSLocalizedString("2×/day", comment: "Twice daily short")
            case .threeTimesDaily: return NSLocalizedString("3×/day", comment: "Three times daily short")
            case .custom: return NSLocalizedString("Custom", comment: "Custom schedule short")
            }
        }

        var title: LocalizedStringKey {
            switch self {
            case .onceDaily: return "Once Daily"
            case .twiceDaily: return "Twice Daily"
            case .threeTimesDaily: return "Three Times Daily"
            case .custom: return "Custom"
            }
        }

        var subtitle: LocalizedStringKey {
            switch self {
            case .onceDaily: return "1 reminder"
            case .twiceDaily: return "2 reminders"
            case .threeTimesDaily: return "3 reminders"
            case .custom: return "Edit times manually"
            }
        }

        var timeCount: Int? {
            switch self {
            case .onceDaily: return 1
            case .twiceDaily: return 2
            case .threeTimesDaily: return 3
            case .custom: return nil
            }
        }
    }

    // MARK: - Computed Properties

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
        let cal = Calendar.current
        let start = cal.startOfDay(for: Date())
        let end = cal.startOfDay(for: courseEndDate)
        return cal.dateComponents([.day], from: start, to: end).day
    }

    private var intakeModeSelection: Binding<IntakeMode> {
        Binding(
            get: { isAsNeeded ? .asNeeded : .scheduled },
            set: { newValue in
                switch newValue {
                case .scheduled:
                    isAsNeeded = false
                    if times.isEmpty {
                        schedulePreset = .onceDaily
                        updateSchedulePreset(.onceDaily)
                    }
                    remindersEnabled = true
                case .asNeeded:
                    requestSwitchToPRN()
                }
            }
        )
    }


    private var instructionsSummary: String {
        if let foodInstruction { return foodInstruction.displayName }
        if !specialInstructions.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return NSLocalizedString("Custom instructions added", comment: "")
        }
        if !notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return NSLocalizedString("Notes added", comment: "")
        }
        return NSLocalizedString("None", comment: "")
    }

    private var inventorySummary: String {
        if trackSupply, let estimatedSupplyDays {
            return String(format: NSLocalizedString("%lld-day supply", comment: ""), estimatedSupplyDays)
        }
        if hasCourseEnd, let courseDaysRemaining {
            return String(format: NSLocalizedString("Ends in %lld days", comment: ""), max(courseDaysRemaining, 0))
        }
        return NSLocalizedString("Not tracking", comment: "")
    }

    private var categorySummary: String {
        if category == .custom {
            let trimmed = customCategoryName.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { return trimmed }
        } else if category != .unspecified {
            return category.displayName
        }
        if hasPhoto { return NSLocalizedString("Photo added", comment: "") }
        return NSLocalizedString("Optional", comment: "")
    }

    private var hasPhoto: Bool {
        pickedImage != nil || (editing?.imagePath != nil && !removePhoto)
    }

    private var existingMedicationImage: UIImage? {
        guard !removePhoto, let path = editing?.imagePath else { return nil }
        return loadMedicationImage(path: path)
    }

    private var navigationTitleText: String {
        isEditing
            ? NSLocalizedString("Edit Medication", comment: "")
            : NSLocalizedString("Add Medication", comment: "")
    }

    private var optionalDetailsCompletedCount: Int {
        var count = 0
        if instructionsSummary != NSLocalizedString("None", comment: "") { count += 1 }
        if inventorySummary != NSLocalizedString("Not tracking", comment: "") { count += 1 }
        if categorySummary != NSLocalizedString("Optional", comment: "") { count += 1 }
        return count
    }

    private var addOptionalDetailsSummaryText: String {
        if optionalDetailsCompletedCount == 0 {
            return NSLocalizedString("You can save now and add instructions, supply, category, or a photo later.", comment: "")
        }
        return String(format: NSLocalizedString("%lld optional sections filled in.", comment: ""), optionalDetailsCompletedCount)
    }

    @ViewBuilder
    private var formSections: some View {
        VStack(alignment: .leading, spacing: isEditing ? 16 : 24) {
            medicationSection
            if isEditing {
                intakeModeSection
                if !isAsNeeded { scheduleSection }
                optionalDetailsSection
                if onDelete != nil { deleteSection }
            } else {
                combinedScheduleSection
                addOptionalDetailsEntrySection
            }
        }
        .padding(.horizontal, isEditing ? 16 : 20)
        .padding(.top, 12)
        .padding(.bottom, 28)
    }

    private var editorScrollView: some View {
        ScrollView(.vertical) {
            formSections
        }
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            editorScrollView
            .navigationTitle(navigationTitleText)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { bodyToolbar }
            .onAppear { populateFromEditing() }
            .onChange(of: schedulePreset) { newValue in updateSchedulePreset(newValue) }
            .onChange(of: name) { _ in validateName() }
            .onChange(of: times) { _ in validateSchedule() }
            .onChange(of: courseEndDate) { _ in validateCourseEnd() }
            .alert(NSLocalizedString("No Schedule Set", comment: ""), isPresented: $showScheduleAlert) {
                Button(NSLocalizedString("Add Time", comment: "")) {
                    schedulePreset = .custom
                    times.append(defaultCustomTime(after: nil))
                }
                Button(NSLocalizedString("Save Without Reminders", comment: "")) {
                    saveAndDismiss(remindersOverride: false)
                }
            } message: {
                Text(NSLocalizedString("Reminders are enabled but no times are set. Add a time or save without reminders.", comment: ""))
            }
            .sheet(item: $ocrSuggestion) { suggestion in
                medicationOCRReviewSheet(for: suggestion)
            }
            .sheet(isPresented: $showAddOptionalDetails) {
                addOptionalDetailsSheet
            }
            .fullScreenCover(isPresented: $showOCRCamera) {
                CameraCaptureView { image in runOCR(from: image) }
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
                Button(NSLocalizedString("Switch", comment: ""), role: .destructive) { confirmSwitchToPRN() }
            } message: {
                Text(NSLocalizedString("This will turn off fixed reminders for this medication and remove any scheduled times from the form.", comment: ""))
            }
            .alert(NSLocalizedString("Couldn't Save Medication", comment: ""), isPresented: $showSaveError) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(saveErrorMessage ?? NSLocalizedString("Review the medication details and try again.", comment: ""))
            }
        }
    }

    @ToolbarContentBuilder
    private var bodyToolbar: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button("Cancel") { dismiss() }
        }
        ToolbarItem(placement: .confirmationAction) {
            Button("Save") {
                if !isAsNeeded && remindersEnabled && times.isEmpty {
                    showScheduleAlert = true
                    return
                }
                saveAndDismiss(remindersOverride: nil)
            }
            .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        ToolbarItemGroup(placement: .keyboard) {
            Spacer()
            Button(NSLocalizedString("Done", comment: "")) { focusedField = nil }
        }
    }

    private func medicationOCRReviewSheet(for suggestion: MedicationOCRSuggestion) -> some View {
        MedicationOCRReviewSheet(suggestion: suggestion) { edited in
            applyOCRSuggestion(edited)
        }
    }

    // MARK: - Sections

    private var medicationSection: some View {
        sectionWrapper {
            VStack(alignment: .leading, spacing: 16) {
                sectionHeader(
                    step: "1",
                    title: NSLocalizedString("Medication", comment: ""),
                    detail: isEditing
                        ? NSLocalizedString("Update the saved details below if this medication changes.", comment: "")
                        : NSLocalizedString("Start with the essentials. You can scan a label or type manually.", comment: "")
                )

                if !isEditing { scanAssistPanel }

                textInputCard(
                    title: NSLocalizedString("Medication Name", comment: ""),
                    placeholder: NSLocalizedString("Amlodipine", comment: ""),
                    text: $name,
                    field: .name
                )
                validationHint(nameValidation)

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
            }
        }
    }

    private var intakeModeSection: some View {
        sectionWrapper {
            VStack(alignment: .leading, spacing: 14) {
                sectionHeader(
                    step: "2",
                    title: NSLocalizedString("How is it taken?", comment: ""),
                    detail: isEditing
                        ? NSLocalizedString("Keep this medication on a fixed schedule or switch it to as-needed logging.", comment: "")
                        : NSLocalizedString("Choose whether this medication follows a fixed schedule or is logged only when needed.", comment: "")
                )

                Picker("", selection: intakeModeSelection) {
                    Text(NSLocalizedString("Scheduled", comment: "")).tag(IntakeMode.scheduled)
                    Text(NSLocalizedString("As Needed", comment: "")).tag(IntakeMode.asNeeded)
                }
                .pickerStyle(.segmented)

                if isAsNeeded {
                    InsetPanel(tint: .blue) {
                        Text(NSLocalizedString("As-needed medications skip fixed reminder times. Log each dose from Today only when you actually take it.", comment: ""))
                            .appFont(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                } else {
                    InsetPanel {
                        Text(NSLocalizedString("Choose a frequency first, then confirm the times below.", comment: ""))
                            .appFont(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    /// Combined schedule section for new-entry mode: frequency + times + as-needed toggle in one panel.
    private var combinedScheduleSection: some View {
        sectionWrapper {
            VStack(alignment: .leading, spacing: 16) {
                sectionHeader(
                    step: "2",
                    title: NSLocalizedString("Schedule", comment: ""),
                    detail: NSLocalizedString("Pick a frequency, then adjust the times.", comment: "")
                )

                InsetPanel {
                    VStack(alignment: .leading, spacing: 14) {
                        if !isAsNeeded {
                            // Frequency picker
                            Picker(NSLocalizedString("Frequency", comment: ""), selection: $schedulePreset) {
                                ForEach(SchedulePreset.allCases) { preset in
                                    Text(preset.shortLabel).tag(preset)
                                }
                            }
                            .pickerStyle(.segmented)

                            Divider()

                            // Inline time pickers
                            ForEach(Array(times.indices), id: \.self) { idx in
                                HStack {
                                    Text(times.count == 1
                                         ? NSLocalizedString("Time", comment: "Single reminder time label")
                                         : String(format: NSLocalizedString("Time %lld", comment: ""), idx + 1))
                                        .appFont(.subheadline)
                                    Spacer()
                                    DatePicker(
                                        "",
                                        selection: Binding(
                                            get: { times[idx] },
                                            set: { newValue in
                                                schedulePreset = .custom
                                                times[idx] = newValue
                                            }
                                        ),
                                        displayedComponents: .hourAndMinute
                                    )
                                    .labelsHidden()
                                    if schedulePreset == .custom && times.count > 1 {
                                        Button(role: .destructive) {
                                            times.remove(at: idx)
                                        } label: {
                                            Image(systemName: "minus.circle.fill")
                                                .foregroundStyle(.red)
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                            }

                            validationHint(scheduleValidation)

                            if schedulePreset == .custom {
                                Button {
                                    times.append(defaultCustomTime(after: times.last))
                                } label: {
                                    secondaryActionLabel(NSLocalizedString("Add Time", comment: ""), systemImage: "plus.circle.fill")
                                }
                                .buttonStyle(.plain)
                            }

                            Divider()

                            // Reminders toggle
                            HStack {
                                Text(NSLocalizedString("Reminders", comment: ""))
                                    .appFont(.subheadline)
                                Spacer()
                                Toggle("", isOn: $remindersEnabled)
                                    .labelsHidden()
                            }
                            if !remindersEnabled {
                                Text(NSLocalizedString("Times saved, but notifications won't fire.", comment: ""))
                                    .appFont(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        } else {
                            Text(NSLocalizedString("As-needed medications skip fixed reminder times. Log each dose from Today only when you actually take it.", comment: ""))
                                .appFont(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        Divider()

                        // As-needed toggle at bottom
                        HStack {
                            Text(NSLocalizedString("As Needed Only", comment: ""))
                                .appFont(.subheadline)
                            Spacer()
                            Toggle("", isOn: Binding(
                                get: { isAsNeeded },
                                set: { newValue in
                                    if newValue {
                                        requestSwitchToPRN()
                                    } else {
                                        isAsNeeded = false
                                        if times.isEmpty {
                                            schedulePreset = .onceDaily
                                            updateSchedulePreset(.onceDaily)
                                        }
                                        remindersEnabled = true
                                    }
                                }
                            ))
                            .labelsHidden()
                        }
                    }
                }
            }
        }
    }

    private var scheduleSection: some View {
        sectionWrapper {
            VStack(alignment: .leading, spacing: 16) {
                sectionHeader(
                    step: "3",
                    title: NSLocalizedString("Schedule", comment: ""),
                    detail: NSLocalizedString("Pick a frequency, then adjust the times.", comment: "")
                )

                InsetPanel {
                    VStack(alignment: .leading, spacing: 14) {
                        // Frequency picker
                        Picker(NSLocalizedString("Frequency", comment: ""), selection: $schedulePreset) {
                            ForEach(SchedulePreset.allCases) { preset in
                                Text(preset.shortLabel).tag(preset)
                            }
                        }
                        .pickerStyle(.segmented)

                        Divider()

                        // Inline time pickers
                        ForEach(Array(times.indices), id: \.self) { idx in
                            HStack {
                                Text(times.count == 1
                                     ? NSLocalizedString("Time", comment: "Single reminder time label")
                                     : String(format: NSLocalizedString("Time %lld", comment: ""), idx + 1))
                                    .appFont(.subheadline)
                                Spacer()
                                DatePicker(
                                    "",
                                    selection: Binding(
                                        get: { times[idx] },
                                        set: { newValue in
                                            schedulePreset = .custom
                                            times[idx] = newValue
                                        }
                                    ),
                                    displayedComponents: .hourAndMinute
                                )
                                .labelsHidden()
                                if schedulePreset == .custom && times.count > 1 {
                                    Button(role: .destructive) {
                                        times.remove(at: idx)
                                    } label: {
                                        Image(systemName: "minus.circle.fill")
                                            .foregroundStyle(.red)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }

                        validationHint(scheduleValidation)

                        if schedulePreset == .custom {
                            Button {
                                times.append(defaultCustomTime(after: times.last))
                            } label: {
                                secondaryActionLabel(NSLocalizedString("Add Time", comment: ""), systemImage: "plus.circle.fill")
                            }
                            .buttonStyle(.plain)
                        }

                        Divider()

                        // Reminders toggle
                        HStack {
                            Text(NSLocalizedString("Reminders", comment: ""))
                                .appFont(.subheadline)
                            Spacer()
                            Toggle("", isOn: $remindersEnabled)
                                .labelsHidden()
                        }
                        if !remindersEnabled {
                            Text(NSLocalizedString("Times saved, but notifications won't fire.", comment: ""))
                                .appFont(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
    }

    private var optionalDetailsSection: some View {
        sectionWrapper(showDivider: false) {
            VStack(alignment: .leading, spacing: 16) {
                sectionHeader(
                    step: "4",
                    title: NSLocalizedString("Optional Details", comment: ""),
                    detail: NSLocalizedString("Add instructions, supply tracking, category, or a photo only if they help later.", comment: "")
                )

                optionalDetailsControls
            }
        }
    }

    private var addOptionalDetailsEntrySection: some View {
        sectionWrapper(showDivider: false) {
            VStack(alignment: .leading, spacing: 16) {
                sectionHeader(
                    step: "3",
                    title: NSLocalizedString("More Details", comment: ""),
                    detail: NSLocalizedString("Keep the first pass short. Add instructions, supply tracking, category, or a photo only if they matter right now.", comment: "")
                )

                InsetPanel {
                    VStack(alignment: .leading, spacing: 14) {
                        Text(addOptionalDetailsSummaryText)
                            .appFont(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)

                        compactOptionalRow(title: NSLocalizedString("Instructions", comment: ""), summary: instructionsSummary)
                        compactOptionalRow(title: NSLocalizedString("Inventory & Course", comment: ""), summary: inventorySummary)
                        compactOptionalRow(title: NSLocalizedString("Category & Photo", comment: ""), summary: categorySummary)

                        Button {
                            showAddOptionalDetails = true
                        } label: {
                            secondaryActionLabel(NSLocalizedString("Add More Details", comment: ""), systemImage: "slider.horizontal.3")
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var optionalDetailsControls: some View {
        optionalSectionButton(
            title: NSLocalizedString("Instructions", comment: ""),
            summary: instructionsSummary,
            isExpanded: $showInstructionsDetails
        )
        if showInstructionsDetails {
            InsetPanel {
                VStack(alignment: .leading, spacing: 14) {
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
                        field: .specialInstructions,
                        axis: .vertical,
                        lineLimit: 2...4
                    )

                    textInputCard(
                        title: NSLocalizedString("Notes", comment: ""),
                        placeholder: NSLocalizedString("Optional context", comment: ""),
                        text: $notes,
                        field: .notes,
                        axis: .vertical,
                        lineLimit: 2...4
                    )
                }
            }
        }

        optionalSectionButton(
            title: NSLocalizedString("Inventory & Course", comment: ""),
            summary: inventorySummary,
            isExpanded: $showInventoryDetails
        )
        if showInventoryDetails {
            InsetPanel {
                VStack(alignment: .leading, spacing: 14) {
                    Toggle(NSLocalizedString("Track Supply", comment: ""), isOn: $trackSupply)
                    if trackSupply {
                        pillsRemainingField
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
                        validationHint(courseEndValidation)
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
            }
        }

        optionalSectionButton(
            title: NSLocalizedString("Category & Photo", comment: ""),
            summary: categorySummary,
            isExpanded: $showCategoryDetails
        )
        if showCategoryDetails {
            InsetPanel {
                VStack(alignment: .leading, spacing: 14) {
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
        }
    }

    private var addOptionalDetailsSheet: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    sectionHeader(
                        step: "4",
                        title: NSLocalizedString("Optional Details", comment: ""),
                        detail: NSLocalizedString("These fields help with context and maintenance, but they are not required to save the medication.", comment: "")
                    )
                    optionalDetailsControls
                }
                .padding(20)
            }
            .navigationTitle(NSLocalizedString("More Details", comment: ""))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(NSLocalizedString("Done", comment: "")) {
                        showAddOptionalDetails = false
                    }
                }
            }
        }
    }

    private var deleteSection: some View {
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

    // MARK: - Pills remaining text field (replaces stepper)

    private var pillsRemainingField: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(NSLocalizedString("Pills remaining", comment: ""))
                .appFont(.caption)
                .foregroundStyle(.secondary)
            HStack(spacing: 10) {
                TextField("30", text: $pillsRemainingText)
                    .keyboardType(.numberPad)
                    .focused($focusedField, equals: .pillsRemaining)
                    .textFieldStyle(.plain)
                    .appFont(.subheadline)
                    .frame(width: 80)
                    .padding(12)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(Color(.secondarySystemBackground))
                    )
                    .onChange(of: pillsRemainingText) { newValue in
                        // Strip non-numeric characters
                        let filtered = newValue.filter { $0.isNumber }
                        if filtered != newValue { pillsRemainingText = filtered }
                    }

                Stepper("", value: Binding(
                    get: { pillsRemaining },
                    set: { pillsRemainingText = "\(max(0, $0))" }
                ), in: 0...9999)
                .labelsHidden()
            }
        }
    }

    // MARK: - Quick buttons

    private var quickPillButtons: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(isEditing ? NSLocalizedString("Quick fill", comment: "") : NSLocalizedString("Quick fill", comment: ""))
                .appFont(.caption)
                .foregroundStyle(.secondary)
            HStack(spacing: 8) {
                if isEditing {
                    ForEach([30, 60, 90], id: \.self) { value in
                        quickButton(title: "+\(value)") {
                            pillsRemainingText = "\(pillsRemaining + value)"
                        }
                    }
                } else {
                    ForEach([30, 60, 90], id: \.self) { value in
                        quickButton(title: "\(value)") {
                            pillsRemainingText = "\(value)"
                        }
                    }
                }
            }
        }
    }

    private var quickCourseButtons: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(isEditing ? NSLocalizedString("Quick extend", comment: "") : NSLocalizedString("Quick duration", comment: ""))
                .appFont(.caption)
                .foregroundStyle(.secondary)
            HStack(spacing: 8) {
                if isEditing {
                    quickButton(title: NSLocalizedString("+7 d", comment: "")) {
                        courseEndDate = Calendar.current.date(byAdding: .day, value: 7, to: courseEndDate) ?? courseEndDate
                    }
                    quickButton(title: NSLocalizedString("+14 d", comment: "")) {
                        courseEndDate = Calendar.current.date(byAdding: .day, value: 14, to: courseEndDate) ?? courseEndDate
                    }
                    quickButton(title: NSLocalizedString("+30 d", comment: "")) {
                        courseEndDate = Calendar.current.date(byAdding: .day, value: 30, to: courseEndDate) ?? courseEndDate
                    }
                } else {
                    quickButton(title: NSLocalizedString("7 days", comment: "")) {
                        courseEndDate = Calendar.current.date(byAdding: .day, value: 7, to: Date()) ?? courseEndDate
                    }
                    quickButton(title: NSLocalizedString("14 days", comment: "")) {
                        courseEndDate = Calendar.current.date(byAdding: .day, value: 14, to: Date()) ?? courseEndDate
                    }
                    quickButton(title: NSLocalizedString("30 days", comment: "")) {
                        courseEndDate = Calendar.current.date(byAdding: .day, value: 30, to: Date()) ?? courseEndDate
                    }
                }
            }
        }
    }

    // MARK: - Validation

    private func validateName() {
        nameValidation = DataValidator.validateMedicationName(name)
    }

    private func validateSchedule() {
        scheduleValidation = DataValidator.validateMedicationSchedule(
            times.map { Calendar.current.dateComponents([.hour, .minute], from: $0) }
        )
    }

    private func validateCourseEnd() {
        if hasCourseEnd && courseEndDate < Calendar.current.startOfDay(for: Date()) {
            courseEndValidation = .warning(NSLocalizedString("Course end date is in the past.", comment: ""))
        } else {
            courseEndValidation = .valid
        }
    }

    @ViewBuilder
    private func validationHint(_ result: ValidationResult) -> some View {
        switch result {
        case .valid:
            EmptyView()
        case .warning(let msg):
            Label(msg, systemImage: "exclamationmark.triangle.fill")
                .appFont(.caption)
                .foregroundStyle(.orange)
        case .error(let msg):
            Label(msg, systemImage: "xmark.circle.fill")
                .appFont(.caption)
                .foregroundStyle(.red)
        }
    }

    // MARK: - State Population

    private func populateFromEditing() {
        if let med = editing {
            name = med.name
            dose = med.dose
            notes = med.notes ?? ""
            let cal = Calendar.current
            times = med.timesOfDay.compactMap { comps in
                guard let h = comps.hour, let m = comps.minute else { return nil }
                return cal.date(bySettingHour: h, minute: m, second: 0, of: Date()) ?? Date()
            }
            remindersEnabled = med.remindersEnabled
            category = med.category ?? .unspecified
            customCategoryName = med.customCategoryName ?? ""
            trackSupply = med.pillsRemaining != nil
            pillsRemainingText = "\(med.pillsRemaining ?? 30)"
            pillsPerDose = med.pillsPerDose ?? 1
            foodInstruction = med.foodInstruction
            isAsNeeded = med.isAsNeeded ?? false
            hasCourseEnd = med.courseEndDate != nil
            courseEndDate = med.courseEndDate ?? Calendar.current.date(byAdding: .month, value: 1, to: Date()) ?? Date()
            specialInstructions = med.specialInstructions ?? ""
        }
        if editing != nil {
            schedulePreset = inferredSchedulePreset(from: times)
        } else {
            // New entry: default to once daily with pre-filled time
            schedulePreset = .onceDaily
            updateSchedulePreset(.onceDaily)
        }
        showInstructionsDetails = foodInstruction != nil || !specialInstructions.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        showInventoryDetails = trackSupply || hasCourseEnd
        showCategoryDetails = category != .unspecified || hasPhoto
        focusedField = .name
    }

    // MARK: - Save

    private func saveAndDismiss(remindersOverride: Bool?) {
        let comps = isAsNeeded ? [] : times.sorted(by: { $0 < $1 }).map { Calendar.current.dateComponents([.hour, .minute], from: $0) }
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return }
        if case .error(let message) = DataValidator.validateMedicationName(trimmedName) {
            presentSaveError(message)
            return
        }
        if !isAsNeeded, case .error(let message) = DataValidator.validateMedicationSchedule(comps) {
            presentSaveError(message)
            return
        }

        let id: UUID
        var imagePath: String?

        if let existing = editing {
            id = existing.id
            if removePhoto {
                deleteMedicationImage(path: existing.imagePath)
                imagePath = nil
            } else if let img = pickedImage {
                imagePath = storeMedicationImage(img, id: id)
            } else {
                imagePath = existing.imagePath
            }
        } else {
            id = UUID()
            if let img = pickedImage {
                imagePath = storeMedicationImage(img, id: id)
            }
        }

        let shouldEnableReminders = remindersOverride ?? (!isAsNeeded && remindersEnabled)

        let med = Medication(
            id: id,
            name: trimmedName,
            dose: dose.trimmingCharacters(in: .whitespacesAndNewlines),
            notes: notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : notes.trimmingCharacters(in: .whitespacesAndNewlines),
            startDate: editing?.startDate ?? Date(),
            timesOfDay: comps,
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
        if let error = onSave(med) {
            presentSaveError(error)
            return
        }
        Haptics.success()
        dismiss()
    }

    private func presentSaveError(_ message: String) {
        saveErrorMessage = message
        showSaveError = true
    }

    // MARK: - PRN

    private func requestSwitchToPRN() {
        guard !isAsNeeded else { return }
        if !times.isEmpty {
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

    // MARK: - OCR

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
            showInstructionsDetails = true
        }
        ocrSuggestion = nil
        // Auto-advance focus past filled fields
        if !name.isEmpty && !dose.isEmpty {
            focusedField = nil // dismiss keyboard, let user proceed to schedule
        } else if name.isEmpty {
            focusedField = .name
        } else {
            focusedField = .dose
        }
    }

    // MARK: - Schedule helpers

    private func updateSchedulePreset(_ preset: SchedulePreset) {
        let calendar = Calendar.current
        let today = Date()
        func makeTime(hour: Int, minute: Int) -> Date {
            calendar.date(bySettingHour: hour, minute: minute, second: 0, of: today) ?? today
        }
        let defaultsByCount: [Int: [Date]] = [
            1: [makeTime(hour: 8, minute: 0)],
            2: [makeTime(hour: 8, minute: 0), makeTime(hour: 20, minute: 0)],
            3: [makeTime(hour: 8, minute: 0), makeTime(hour: 14, minute: 0), makeTime(hour: 20, minute: 0)]
        ]
        switch preset {
        case .onceDaily:
            times = mergedTimes(existing: times, defaults: defaultsByCount[1] ?? [])
        case .twiceDaily:
            times = mergedTimes(existing: times, defaults: defaultsByCount[2] ?? [])
        case .threeTimesDaily:
            times = mergedTimes(existing: times, defaults: defaultsByCount[3] ?? [])
        case .custom:
            if times.isEmpty {
                times = defaultsByCount[1] ?? [makeTime(hour: 8, minute: 0)]
            }
        }
    }

    private func inferredSchedulePreset(from currentTimes: [Date]) -> SchedulePreset {
        switch currentTimes.count {
        case 1: return .onceDaily
        case 2: return .twiceDaily
        case 3: return .threeTimesDaily
        default: return .custom
        }
    }

    private func mergedTimes(existing: [Date], defaults: [Date]) -> [Date] {
        let sortedExisting = existing.sorted()
        guard !defaults.isEmpty else { return sortedExisting }
        if sortedExisting.isEmpty { return defaults }
        if sortedExisting.count >= defaults.count {
            return Array(sortedExisting.prefix(defaults.count))
        }
        return sortedExisting + defaults.dropFirst(sortedExisting.count)
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
    var onApply: (MedicationOCRSuggestion) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var name: String
    @State private var dose: String
    @State private var notes: String

    init(suggestion: MedicationOCRSuggestion, onApply: @escaping (MedicationOCRSuggestion) -> Void) {
        self.suggestion = suggestion
        self.onApply = onApply
        _name = State(initialValue: suggestion.name ?? "")
        _dose = State(initialValue: suggestion.dose ?? "")
        _notes = State(initialValue: suggestion.notes ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(NSLocalizedString("Medication Name", comment: ""), text: $name)
                    TextField(NSLocalizedString("Dose", comment: ""), text: $dose)
                    TextField(NSLocalizedString("Notes", comment: ""), text: $notes, axis: .vertical)
                        .lineLimit(2...4)
                } header: {
                    Text(NSLocalizedString("Review OCR Result", comment: ""))
                } footer: {
                    Text(NSLocalizedString("Edit anything that looks wrong before applying it to the form.", comment: ""))
                }

                if !suggestion.rawText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Section(NSLocalizedString("Detected Text", comment: "")) {
                        Text(suggestion.rawText)
                            .appFont(.footnote)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                }
            }
            .navigationTitle(NSLocalizedString("Review Scan", comment: ""))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(NSLocalizedString("Cancel", comment: "")) {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(NSLocalizedString("Apply", comment: "")) {
                        let edited = MedicationOCRSuggestion(
                            name: name.nilIfBlank,
                            dose: dose.nilIfBlank,
                            notes: notes.nilIfBlank,
                            rawText: suggestion.rawText
                        )
                        onApply(edited)
                        dismiss()
                    }
                }
            }
        }
    }
}

private extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

// MARK: - Subviews

private extension MedicationFormView {

    func sectionWrapper<Content: View>(showDivider: Bool = true, @ViewBuilder content: () -> Content) -> some View {
        if isEditing {
            AnyView(Card { content() })
        } else {
            AnyView(
                VStack(alignment: .leading, spacing: 0) {
                    content().padding(.vertical, 2)
                    if showDivider {
                        Divider().padding(.top, 20)
                    }
                }
            )
        }
    }

    func sectionHeader(step: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(step)
                .appFont(.caption)
                .fontWeight(.bold)
                .foregroundStyle(Color.accentColor)
                .frame(width: 22, height: 22)
                .background(Circle().fill(Color.accentColor.opacity(0.12)))

            VStack(alignment: .leading, spacing: 4) {
                Text(title).appFont(.headline)
                Text(detail)
                    .appFont(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    func optionalSectionButton(title: String, summary: String, isExpanded: Binding<Bool>) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.18)) { isExpanded.wrappedValue.toggle() }
        } label: {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).appFont(.subheadline).fontWeight(.semibold)
                    Text(summary).appFont(.footnote).foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: isExpanded.wrappedValue ? "chevron.up" : "chevron.down")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 32, height: 32)
                    .contentShape(Rectangle())
                    .accessibilityHidden(true)
            }
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    func compactOptionalRow(title: String, summary: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(title)
                .appFont(.subheadline)
                .foregroundStyle(.primary)
            Spacer(minLength: 12)
            Text(summary)
                .appFont(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.trailing)
        }
    }


    var scanAssistPanel: some View {
        InsetPanel(tint: .blue) {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(NSLocalizedString("Scan Label", comment: ""))
                        .appFont(.subheadline)
                        .fontWeight(.semibold)
                    Text(NSLocalizedString("Use the camera if typing from a box or bottle is slower.", comment: ""))
                        .appFont(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                scanLabelButton
            }
        }
    }

    var scanLabelButton: some View {
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
                if isOCRLoading { ProgressView().controlSize(.small) }
            }
            .foregroundStyle(Color.accentColor)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Capsule(style: .continuous).fill(Color.accentColor.opacity(0.10)))
            .overlay(Capsule(style: .continuous).stroke(Color.accentColor.opacity(0.18), lineWidth: 0.8))
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    func textInputCard(
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
                .submitLabel(submitLabel(for: field))
                .onSubmit { handleSubmit(for: field) }
                .padding(13)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color(.secondarySystemBackground))
                )
        }
    }

    func submitLabel(for field: EntryField) -> SubmitLabel {
        switch field {
        case .name:
            return .next
        default:
            return .done
        }
    }

    func handleSubmit(for field: EntryField) {
        switch field {
        case .name:
            focusedField = .dose
        default:
            focusedField = nil
        }
    }

    func quickButton(title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .appFont(.caption)
                .fontWeight(.semibold)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 7)
                .background(Capsule(style: .continuous).fill(Color(.secondarySystemBackground)))
        }
        .buttonStyle(.plain)
    }

    func secondaryActionLabel(_ title: String, systemImage: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage).font(.system(size: 13, weight: .semibold))
            Text(title).appFont(.label).fontWeight(.semibold)
        }
        .foregroundStyle(Color.accentColor)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 9)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.accentColor.opacity(0.08)))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Color.accentColor.opacity(0.14), lineWidth: 0.8))
    }

    @ViewBuilder

    var photoAttachmentRow: some View {
        HStack(spacing: 12) {
            photoPreview
            Spacer(minLength: 8)
            PhotosPicker(selection: $pickedItem, matching: .images) {
                Image(systemName: hasPhoto ? "arrow.triangle.2.circlepath" : "photo")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 38, height: 38)
                    .background(Circle().fill(Color.accentColor.opacity(0.10)))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(hasPhoto ? NSLocalizedString("Change Photo", comment: "") : NSLocalizedString("Add Photo", comment: ""))
            .onChange(of: pickedItem) { newItem in
                Task {
                    if let data = try? await newItem?.loadTransferable(type: Data.self),
                       let ui = UIImage(data: data) {
                        pickedImage = ui
                        removePhoto = false
                    }
                }
            }

            if hasPhoto {
                Button(role: .destructive) {
                    pickedImage = nil
                    removePhoto = true
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.red)
                        .frame(width: 38, height: 38)
                        .background(Circle().fill(Color.red.opacity(0.10)))
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

    var photoPreview: some View {
        Group {
            if let img = pickedImage {
                Image(uiImage: img)
                    .resizable().scaledToFill()
                    .frame(width: 64, height: 64)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            } else if let existing = existingMedicationImage {
                Image(uiImage: existing)
                    .resizable().scaledToFill()
                    .frame(width: 64, height: 64)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            } else {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color(.secondarySystemBackground))
                    .frame(width: 64, height: 64)
                    .overlay(Image(systemName: "photo").foregroundStyle(.secondary))
            }
        }
    }
}
