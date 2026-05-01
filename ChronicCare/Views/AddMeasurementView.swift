import SwiftUI
import UIKit

struct AddMeasurementView: View {
    var onSave: (Measurement) -> Void
    private let editing: Measurement?
    @Environment(\.dismiss) private var dismiss

    @State private var type: MeasurementType
    @State private var systolicInput: String = ""
    @State private var diastolicInput: String = ""
    @State private var valueInput: String = ""
    @State private var note: String = ""
    @State private var date: Date = Date()
    @State private var timeManuallySet: Bool = false
    @State private var showTimeEditor: Bool = false
    @State private var glucoseUnit: GlucoseUnit = UnitPreferences.glucoseUnit
    @State private var validationMessage: String?
    @State private var showValidationAlert = false
    @State private var validationIsWarning = false
    @State private var showContextNotes = false
    @FocusState private var focusedField: EntryField?

    private enum EntryField: Hashable {
        case systolic
        case diastolic
        case value
        case note
    }

    init(initialType: MeasurementType = .bloodPressure, editing: Measurement? = nil, onSave: @escaping (Measurement) -> Void) {
        self.onSave = onSave
        self.editing = editing
        let resolvedType = editing?.type ?? initialType
        _type = State(initialValue: resolvedType)
        _note = State(initialValue: editing?.note ?? "")
        _date = State(initialValue: min(editing?.date ?? Date(), Date()))
        _timeManuallySet = State(initialValue: editing != nil)
        if let editing {
            switch editing.type {
            case .bloodPressure:
                _systolicInput = State(initialValue: Self.inputString(editing.value, decimals: 0))
                _diastolicInput = State(initialValue: Self.inputString(editing.diastolic ?? 0, decimals: 0))
            case .bloodGlucose:
                let unit = UnitPreferences.glucoseUnit
                _glucoseUnit = State(initialValue: unit)
                _valueInput = State(initialValue: Self.inputString(UnitPreferences.mgdlToPreferred(editing.value), decimals: unit == .mgdL ? 0 : 1))
            case .weight:
                _valueInput = State(initialValue: Self.inputString(editing.value, decimals: 1))
            case .heartRate:
                _valueInput = State(initialValue: Self.inputString(editing.value, decimals: 0))
            }
        }
    }

    private var contextSummary: String {
        let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return NSLocalizedString("Optional", comment: "")
        }
        return trimmed.count > 30 ? String(trimmed.prefix(30)) + "..." : trimmed
    }

    private var timeDescription: String {
        if !timeManuallySet {
            return NSLocalizedString("Now", comment: "")
        }
        return date.formatted(date: .abbreviated, time: .shortened)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: EditorialSpacing.xxl) {
                    measurementSection
                    timeSection
                    notesSection
                    validationBanner
                }
                .padding(.horizontal, EditorialSpacing.lg)
                .padding(.vertical, EditorialSpacing.xl)
            }
            .background(AppColor.background)
            .navigationTitle(editing == nil
                             ? NSLocalizedString("Add Measurement", comment: "")
                             : NSLocalizedString("Edit Measurement", comment: ""))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        validateAndSave()
                    }
                    .disabled(!canSave)
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button(NSLocalizedString("Done", comment: "")) {
                        focusedField = nil
                    }
                }
            }
            .alert(validationIsWarning ? NSLocalizedString("Warning", comment: "") : NSLocalizedString("Error", comment: ""), isPresented: $showValidationAlert) {
                if validationIsWarning {
                    Button(NSLocalizedString("Save Anyway", comment: "")) {
                        saveWithoutValidation()
                    }
                    Button(NSLocalizedString("Cancel", comment: ""), role: .cancel) { }
                } else {
                    Button(NSLocalizedString("OK", comment: ""), role: .cancel) { }
                }
            } message: {
                if let message = validationMessage {
                    Text(message)
                }
            }
            .onAppear {
                focusPrimaryField()
                showContextNotes = !note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            }
            .onChange(of: type) { newType in
                validationMessage = nil
                switch newType {
                case .bloodPressure:
                    valueInput = ""
                default:
                    systolicInput = ""
                    diastolicInput = ""
                }
                focusPrimaryField()
            }
            .onChange(of: systolicInput) { _ in validateInput() }
            .onChange(of: diastolicInput) { _ in validateInput() }
            .onChange(of: valueInput) { _ in validateInput() }
        }
    }

    private var measurementSection: some View {
        VStack(alignment: .leading, spacing: EditorialSpacing.xl) {
            EditorialSection(NSLocalizedString("Measurement Type", comment: "")) {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: EditorialSpacing.sm) {
                    ForEach(MeasurementType.allCases) { measurementType in
                        measurementTypeButton(for: measurementType)
                    }
                }
            }

            EditorialSection(NSLocalizedString("Reading", comment: "")) {
                if type == .bloodPressure {
                    bloodPressureEntryLayout
                } else {
                    VStack(alignment: .leading, spacing: EditorialSpacing.md) {
                        measurementInputCard(
                            title: NSLocalizedString("Value", comment: ""),
                            text: $valueInput,
                            placeholder: suggestedPlaceholder,
                            unit: displayedUnitLabel,
                            field: .value,
                            keyboard: .decimalPad
                        )

                        if type == .bloodGlucose {
                            Picker(NSLocalizedString("Unit", comment: ""), selection: $glucoseUnit) {
                                ForEach(GlucoseUnit.allCases) { unit in
                                    Text(unit.rawValue).tag(unit)
                                }
                            }
                            .pickerStyle(.segmented)
                        }
                    }
                }
            }
        }
    }

    private var timeSection: some View {
        EditorialSection(NSLocalizedString("Time", comment: "")) {
            VStack(alignment: .leading, spacing: EditorialSpacing.md) {
                Button {
                    Haptics.impact(.light)
                    withAnimation(.easeInOut(duration: 0.18)) { showTimeEditor.toggle() }
                } label: {
                    HStack(alignment: .center, spacing: EditorialSpacing.md) {
                        VStack(alignment: .leading, spacing: EditorialSpacing.xs) {
                            Text(NSLocalizedString("Recorded Time", comment: ""))
                                .appFont(.subheadline)
                                .fontWeight(.semibold)
                                .foregroundStyle(AppColor.textPrimary)
                            Text(timeDescription)
                                .appFont(.footnote)
                                .foregroundStyle(AppColor.textSecondary)
                        }
                        Spacer()
                        Image(systemName: showTimeEditor ? "chevron.up" : "chevron.down")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(AppColor.textSecondary)
                            .frame(width: 32, height: 32)
                            .contentShape(Rectangle())
                    }
                    .padding(.vertical, EditorialSpacing.xs)
                    .contentShape(Rectangle())
                }
                .buttonStyle(EditorialRowButtonStyle())

                if showTimeEditor {
                    VStack(alignment: .leading, spacing: EditorialSpacing.md) {
                        HStack(spacing: EditorialSpacing.sm) {
                            quickDateButton(title: NSLocalizedString("Now", comment: "")) {
                                date = Date()
                                timeManuallySet = true
                            }
                            quickDateButton(title: NSLocalizedString("1h Ago", comment: "")) {
                                date = Date().addingTimeInterval(-3600)
                                timeManuallySet = true
                            }
                            quickDateButton(title: NSLocalizedString("Today 8 PM", comment: "")) {
                                let cal = Calendar.current
                                let candidate = cal.date(bySettingHour: 20, minute: 0, second: 0, of: Date()) ?? Date()
                                date = min(candidate, Date())
                                timeManuallySet = true
                            }
                        }

                        DatePicker(NSLocalizedString("Date", comment: ""), selection: $date, in: ...Date())
                            .datePickerStyle(.compact)
                            .onChange(of: date) { _ in timeManuallySet = true }
                    }
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
            .animation(.easeInOut(duration: 0.18), value: showTimeEditor)
        }
    }

    private var notesSection: some View {
        EditorialSection(NSLocalizedString("Context", comment: "")) {
            VStack(alignment: .leading, spacing: EditorialSpacing.md) {
                Button {
                    Haptics.impact(.light)
                    withAnimation(.easeInOut(duration: 0.18)) { showContextNotes.toggle() }
                } label: {
                    HStack(alignment: .center, spacing: EditorialSpacing.md) {
                        VStack(alignment: .leading, spacing: EditorialSpacing.xs) {
                            Text(NSLocalizedString("Context Notes", comment: ""))
                                .appFont(.subheadline)
                                .fontWeight(.semibold)
                                .foregroundStyle(AppColor.textPrimary)
                            Text(contextSummary)
                                .appFont(.footnote)
                                .foregroundStyle(AppColor.textSecondary)
                        }
                        Spacer()
                        Image(systemName: showContextNotes ? "chevron.up" : "chevron.down")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(AppColor.textSecondary)
                            .frame(width: 32, height: 32)
                            .contentShape(Rectangle())
                    }
                    .padding(.vertical, EditorialSpacing.xs)
                    .contentShape(Rectangle())
                }
                .buttonStyle(EditorialRowButtonStyle())

                if showContextNotes {
                    TextField(NSLocalizedString("Symptoms, meals, activity...", comment: ""), text: $note, axis: .vertical)
                        .focused($focusedField, equals: .note)
                        .lineLimit(2...4)
                        .textFieldStyle(.plain)
                        .appFont(.subheadline)
                        .submitLabel(.done)
                        .onSubmit { focusedField = nil }
                        .padding(.horizontal, AppSpacing.small)
                        .padding(.vertical, EditorialSpacing.md)
                        .background(
                            RoundedRectangle(cornerRadius: AppRadius.medium, style: .continuous)
                                .fill(AppColor.surface)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: AppRadius.medium, style: .continuous)
                                .stroke(AppColor.divider, lineWidth: 1)
                        )
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
            .animation(.easeInOut(duration: 0.18), value: showContextNotes)
        }
    }

    @ViewBuilder
    private var validationBanner: some View {
        if let message = validationMessage {
            HStack(alignment: .top, spacing: EditorialSpacing.md) {
                Rectangle()
                    .fill(validationIsWarning ? AppColor.warning : AppColor.primary)
                    .frame(width: 2)
                    .clipShape(Capsule())

                Image(systemName: validationIsWarning ? "exclamationmark.triangle" : "info.circle")
                    .foregroundStyle(validationIsWarning ? AppColor.warning : AppColor.primary)
                    .font(.system(size: 14, weight: .regular))

                Text(message)
                    .appFont(.caption)
                    .foregroundStyle(AppColor.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.vertical, EditorialSpacing.sm)
        }
    }

    private func validateInput() {
        validationMessage = nil
        validationIsWarning = false

        switch type {
        case .bloodPressure:
            guard let sys = Double(systolicInput), let dia = Double(diastolicInput) else { return }
            let result = DataValidator.validateBloodPressure(systolic: sys, diastolic: dia)
            handleValidationResult(result)

        case .bloodGlucose:
            guard let val = Double(valueInput) else { return }
            let unitToUse = glucoseUnit
            let result = DataValidator.validateBloodGlucose(value: val, unit: unitToUse)
            handleValidationResult(result)

        case .weight:
            guard let val = Double(valueInput) else { return }
            let result = DataValidator.validateWeight(value: val)
            handleValidationResult(result)

        case .heartRate:
            guard let val = Double(valueInput) else { return }
            let result = DataValidator.validateHeartRate(value: val)
            handleValidationResult(result)
        }
    }

    private func handleValidationResult(_ result: ValidationResult) {
        switch result {
        case .valid:
            validationMessage = nil
            validationIsWarning = false
        case .warning(let message):
            validationMessage = message
            validationIsWarning = true
        case .error(let message):
            validationMessage = message
            validationIsWarning = false
        }
    }

    private func validateAndSave() {
        guard let measurement = makeMeasurement() else { return }

        var finalResult: ValidationResult = .valid

        switch type {
        case .bloodPressure:
            finalResult = DataValidator.validateBloodPressure(systolic: measurement.value, diastolic: measurement.diastolic)
        case .bloodGlucose:
            finalResult = DataValidator.validateBloodGlucose(value: measurement.value, unit: .mgdL)
        case .weight:
            finalResult = DataValidator.validateWeight(value: measurement.value)
        case .heartRate:
            finalResult = DataValidator.validateHeartRate(value: measurement.value)
        }

        switch finalResult {
        case .valid:
            saveWithoutValidation()
        case .warning(let message):
            validationMessage = message
            validationIsWarning = true
            showValidationAlert = true
        case .error(let message):
            validationMessage = message
            validationIsWarning = false
            showValidationAlert = true
            Haptics.error()
        }
    }

    private func saveWithoutValidation() {
        if !timeManuallySet {
            date = Date()
        }
        guard let measurement = makeMeasurement() else { return }
        onSave(measurement.clampedToNow())
        Haptics.success()
        dismiss()
    }
}

private extension AddMeasurementView {
    var bloodPressureEntryLayout: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: EditorialSpacing.sm) {
                systolicEntryCard
                diastolicEntryCard
            }

            VStack(spacing: EditorialSpacing.sm) {
                systolicEntryCard
                diastolicEntryCard
            }
        }
    }

    var systolicEntryCard: some View {
        measurementInputCard(
            title: NSLocalizedString("Systolic", comment: ""),
            text: $systolicInput,
            placeholder: "120",
            unit: "mmHg",
            field: .systolic,
            keyboard: .numberPad
        )
    }

    var diastolicEntryCard: some View {
        measurementInputCard(
            title: NSLocalizedString("Diastolic", comment: ""),
            text: $diastolicInput,
            placeholder: "80",
            unit: "mmHg",
            field: .diastolic,
            keyboard: .numberPad
        )
    }

    var displayedUnitLabel: String {
        if type == .bloodGlucose { return glucoseUnit.rawValue }
        return type.unit
    }

    var suggestedPlaceholder: String {
        switch type {
        case .bloodGlucose:
            return glucoseUnit == .mgdL ? "110" : "6.1"
        case .weight:
            return "68.5"
        case .heartRate:
            return "72"
        case .bloodPressure:
            return ""
        }
    }

    var canSave: Bool {
        switch type {
        case .bloodPressure:
            return Double(systolicInput) != nil && Double(diastolicInput) != nil
        default:
            return Double(valueInput) != nil
        }
    }

    @ViewBuilder
    func measurementTypeButton(for measurementType: MeasurementType) -> some View {
        let selected = type == measurementType
        Button {
            Haptics.impact(.light)
            type = measurementType
        } label: {
            VStack(alignment: .leading, spacing: EditorialSpacing.sm) {
                HStack(spacing: EditorialSpacing.sm) {
                    Image(systemName: selected ? "checkmark.circle" : "circle")
                        .font(.system(size: 13, weight: .regular))
                        .foregroundStyle(selected ? AppColor.primary : AppColor.textTertiary)
                    Text(measurementType.displayName)
                        .appFont(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundStyle(AppColor.textPrimary)
                }
                Text(measurementType.unit)
                    .appFont(.caption)
                    .foregroundStyle(AppColor.textSecondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(minHeight: 64, alignment: .center)
            .padding(EditorialSpacing.md)
            .background(
                RoundedRectangle(cornerRadius: AppRadius.medium, style: .continuous)
                    .fill(AppColor.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: AppRadius.medium, style: .continuous)
                    .stroke(selected ? AppColor.primary.opacity(0.55) : AppColor.divider, lineWidth: 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func measurementInputCard(
        title: String,
        text: Binding<String>,
        placeholder: String,
        unit: String,
        field: EntryField,
        keyboard: UIKeyboardType
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .appFont(.caption)
                .foregroundStyle(AppColor.textSecondary)

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                TextField(placeholder, text: text)
                    .keyboardType(keyboard)
                    .focused($focusedField, equals: field)
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundStyle(AppColor.textPrimary)
                    .multilineTextAlignment(.leading)

                Text(unit)
                    .appFont(.caption)
                    .foregroundStyle(AppColor.textSecondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(AppSpacing.medium)
        .background(
            RoundedRectangle(cornerRadius: AppRadius.panel, style: .continuous)
                .fill(AppColor.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: AppRadius.panel, style: .continuous)
                .stroke(AppColor.divider, lineWidth: 1)
        )
    }

    @ViewBuilder
    func quickDateButton(title: String, action: @escaping () -> Void) -> some View {
        Button {
            Haptics.impact(.light)
            action()
        } label: {
            Text(title)
        }
            .buttonStyle(.bordered)
            .tint(AppColor.primary)
            .controlSize(.small)
    }

    func focusPrimaryField() {
        DispatchQueue.main.async {
            focusedField = type == .bloodPressure ? .systolic : .value
        }
    }

    static func inputString(_ value: Double, decimals: Int) -> String {
        if decimals == 0 {
            return String(format: "%.0f", value)
        }
        return String(format: "%.\(decimals)f", value)
    }

    func makeMeasurement() -> Measurement? {
        switch type {
        case .bloodPressure:
            guard let systolic = Double(systolicInput), let dia = Double(diastolicInput) else { return nil }
            return Measurement(
                id: editing?.id ?? UUID(),
                type: .bloodPressure,
                value: systolic,
                diastolic: dia,
                date: date,
                note: note.isEmpty ? nil : note
            )
        case .bloodGlucose:
            guard let input = Double(valueInput) else { return nil }
            let unitToUse = glucoseUnit
            let mgdl = UnitPreferences.convertToMgdl(input, from: unitToUse)
            return Measurement(
                id: editing?.id ?? UUID(),
                type: .bloodGlucose,
                value: mgdl,
                diastolic: nil,
                date: date,
                note: note.isEmpty ? nil : note
            )
        default:
            guard let val = Double(valueInput) else { return nil }
            return Measurement(
                id: editing?.id ?? UUID(),
                type: type,
                value: val,
                diastolic: nil,
                date: date,
                note: note.isEmpty ? nil : note
            )
        }
    }
}
