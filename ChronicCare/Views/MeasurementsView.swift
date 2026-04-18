import SwiftUI
import UIKit

struct MeasurementsView: View {
    @EnvironmentObject var store: DataStore
    @State private var showAdd = false
    @State private var selectedType: MeasurementType? = nil
    @AppStorage("units.glucose") private var glucoseUnitRaw: String = GlucoseUnit.mgdL.rawValue

    var body: some View {
        NavigationStack {
            List {
                if filteredMeasurements.isEmpty {
                    EmptyStateView(systemImage: "heart.text.square", title: NSLocalizedString("No measurements yet", comment: ""), subtitle: NSLocalizedString("Add your first measurement", comment: ""), actionTitle: NSLocalizedString("Add", comment: "")) {
                        showAdd = true
                    }
                    .listRowBackground(Color.clear)
                } else {
                    ForEach(groupedMeasurements, id: \.day) { section in
                        Section(header: Text(sectionHeaderTitle(for: section.day)).appFont(.subheadline).foregroundStyle(.secondary)) {
                            ForEach(section.entries) { m in
                                HStack(spacing: 12) {
                                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                                        .fill(m.cardTint)
                                        .frame(width: 4)
                                    VStack(alignment: .leading, spacing: 6) {
                                        HStack(alignment: .firstTextBaseline) {
                                            Text(m.type.displayName).appFont(.headline)
                                            Spacer()
                                            if m.type == .bloodPressure, let d = m.diastolic {
                                                Text("\(Int(m.value))/\(Int(d)) \(m.type.unit)")
                                                    .appFont(.headline)
                                                    .foregroundStyle(m.valueForeground)
                                            } else if m.type == .bloodGlucose {
                                                let v = UnitPreferences.mgdlToPreferred(m.value)
                                                let unit = UnitPreferences.glucoseUnit.rawValue
                                                let formatted = UnitPreferences.glucoseUnit == .mgdL ? String(format: "%.0f", v) : String(format: "%.1f", v)
                                                Text("\(formatted) \(unit)")
                                                    .appFont(.headline)
                                                    .foregroundStyle(m.valueForeground)
                                            } else {
                                                Text("\(String(format: "%.1f", m.value)) \(m.type.unit)")
                                                    .appFont(.headline)
                                                    .foregroundStyle(m.valueForeground)
                                            }
                                        }
                                        Text(m.date, style: .time)
                                            .appFont(.caption)
                                            .foregroundStyle(.secondary)
                                        if let note = m.note, !note.isEmpty {
                                            Text(note).appFont(.footnote)
                                        }
                                    }
                                }
                                .padding(.vertical, 4)
                                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                    Button(role: .destructive) {
                                        if let i = store.measurements.firstIndex(where: { $0.id == m.id }) {
                                            store.removeMeasurement(at: IndexSet(integer: i))
                                        }
                                    } label: { Label("Delete", systemImage: "trash") }
                                    .tint(.red)
                                }
                                .contextMenu {
                                    Button(role: .destructive) { if let i = store.measurements.firstIndex(where: { $0.id == m.id }) { store.removeMeasurement(at: IndexSet(integer: i)) } } label: { Label("Delete", systemImage: "trash") }
                                    Button { UIPasteboard.general.string = "\(m.type.displayName): \(m.value)" } label: { Label("Copy", systemImage: "doc.on.doc") }
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Measurements")
            .navigationBarTitleDisplayMode(.inline)
            .safeAreaInset(edge: .top) {
                VStack(spacing: 8) {
                    Picker("Type", selection: $selectedType) {
                        Text("All").tag(MeasurementType?.none)
                        ForEach(MeasurementType.allCases) { t in
                            Text(t.displayName).tag(Optional(t))
                        }
                    }
                    .pickerStyle(.segmented)
                    .controlSize(.large)
                    .padding(.horizontal)
                }
                .padding(.vertical, 8)
                .background(.thinMaterial)
                .overlay(Divider(), alignment: .bottom)
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showAdd = true } label: { Image(systemName: "plus") }
                        .accessibilityLabel(NSLocalizedString("Add Measurement", comment: ""))
                }
            }
            .sheet(isPresented: $showAdd) {
                AddMeasurementView { m in
                    store.addMeasurement(m)
                    Haptics.success()
                }
            }
        }
    }
}

struct AddMeasurementView: View {
    var onSave: (Measurement) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var type: MeasurementType = .bloodPressure
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
                VStack(alignment: .leading, spacing: 16) {
                    measurementCard
                    timeCard
                    notesCard
                    validationBanner
                }
                .padding(16)
            }
            .navigationTitle("Add Measurement")
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
            .alert(validationIsWarning ? "Warning" : "Error", isPresented: $showValidationAlert) {
                if validationIsWarning {
                    Button("Save Anyway") {
                        saveWithoutValidation()
                    }
                    Button("Cancel", role: .cancel) { }
                } else {
                    Button("OK", role: .cancel) { }
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

    private var measurementCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 14) {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                    ForEach(MeasurementType.allCases) { measurementType in
                        measurementTypeButton(for: measurementType)
                    }
                }

                if type == .bloodPressure {
                    bloodPressureEntryLayout
                } else {
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

    private var timeCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                Button {
                    withAnimation(.easeInOut(duration: 0.18)) { showTimeEditor.toggle() }
                } label: {
                    HStack(alignment: .center, spacing: 12) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(NSLocalizedString("Time", comment: ""))
                                .appFont(.subheadline)
                                .fontWeight(.semibold)
                            Text(timeDescription)
                                .appFont(.footnote)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: showTimeEditor ? "chevron.up" : "chevron.down")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .frame(width: 32, height: 32)
                            .contentShape(Rectangle())
                    }
                    .padding(.vertical, 4)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                if showTimeEditor {
                    HStack(spacing: 8) {
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
            }
        }
    }

    private var notesCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                Button {
                    withAnimation(.easeInOut(duration: 0.18)) { showContextNotes.toggle() }
                } label: {
                    HStack(alignment: .center, spacing: 12) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(NSLocalizedString("Context Notes", comment: ""))
                                .appFont(.subheadline)
                                .fontWeight(.semibold)
                            Text(contextSummary)
                                .appFont(.footnote)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: showContextNotes ? "chevron.up" : "chevron.down")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .frame(width: 32, height: 32)
                            .contentShape(Rectangle())
                    }
                    .padding(.vertical, 4)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                if showContextNotes {
                    TextField(NSLocalizedString("Symptoms, meals, activity...", comment: ""), text: $note, axis: .vertical)
                        .focused($focusedField, equals: .note)
                        .lineLimit(2...4)
                        .textFieldStyle(.plain)
                        .appFont(.subheadline)
                        .submitLabel(.done)
                        .onSubmit { focusedField = nil }
                        .padding(.horizontal, AppSpacing.small)
                        .padding(.vertical, 14)
                        .background(
                            RoundedRectangle(cornerRadius: AppRadius.medium, style: .continuous)
                                .fill(Color(.secondarySystemBackground))
                        )
                }
            }
        }
    }

    @ViewBuilder
    private var validationBanner: some View {
        if let message = validationMessage {
            Card {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: validationIsWarning ? "exclamationmark.triangle.fill" : "info.circle.fill")
                        .foregroundStyle(validationIsWarning ? .orange : .blue)
                        .font(.system(size: 20))
                    Text(message)
                        .appFont(.caption)
                        .foregroundStyle(.primary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
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

        // Perform final validation
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
        guard let measurement = makeMeasurement() else { return }
        onSave(measurement.clampedToNow())
        Haptics.success()
        dismiss()
    }
}

private extension AddMeasurementView {
    private func measurementSectionHeader(step: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(step)
                .appFont(.caption)
                .fontWeight(.bold)
                .foregroundStyle(Color.accentColor)
                .frame(width: 24, height: 24)
                .background(
                    Circle()
                        .fill(Color.accentColor.opacity(0.12))
                )

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .appFont(.headline)
                Text(detail)
                    .appFont(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    var bloodPressureEntryLayout: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 10) {
                systolicEntryCard
                diastolicEntryCard
            }

            VStack(spacing: 10) {
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
            type = measurementType
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Circle()
                        .fill(measurementType.tint)
                        .frame(width: 8, height: 8)
                    Text(measurementType.displayName)
                        .appFont(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundStyle(.primary)
                }
                Text(measurementType.unit)
                    .appFont(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(AppSpacing.small)
            .background(
                RoundedRectangle(cornerRadius: AppRadius.panel, style: .continuous)
                    .fill(selected ? Color.accentColor.opacity(0.10) : Color(.secondarySystemBackground))
            )
            .overlay(
                RoundedRectangle(cornerRadius: AppRadius.panel, style: .continuous)
                    .stroke(selected ? Color.accentColor.opacity(0.45) : Color.primary.opacity(0.06), lineWidth: 1)
            )
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
                .foregroundStyle(.secondary)

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                TextField(placeholder, text: text)
                    .keyboardType(keyboard)
                    .focused($focusedField, equals: field)
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .multilineTextAlignment(.leading)

                Text(unit)
                    .appFont(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(AppSpacing.medium)
        .background(
            RoundedRectangle(cornerRadius: AppRadius.panel, style: .continuous)
                .fill(Color(.secondarySystemBackground))
        )
    }

    @ViewBuilder
    func quickDateButton(title: String, action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .buttonStyle(.bordered)
            .controlSize(.small)
    }

    func focusPrimaryField() {
        DispatchQueue.main.async {
            focusedField = type == .bloodPressure ? .systolic : .value
        }
    }

    func makeMeasurement() -> Measurement? {
        switch type {
        case .bloodPressure:
            guard let systolic = Double(systolicInput), let dia = Double(diastolicInput) else { return nil }
            return Measurement(
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
                type: .bloodGlucose,
                value: mgdl,
                diastolic: nil,
                date: date,
                note: note.isEmpty ? nil : note
            )
        default:
            guard let val = Double(valueInput) else { return nil }
            return Measurement(
                type: type,
                value: val,
                diastolic: nil,
                date: date,
                note: note.isEmpty ? nil : note
            )
        }
    }
}

private extension MeasurementsView {
    struct MeasurementSection {
        let day: Date
        let entries: [Measurement]
    }

    var filteredMeasurements: [Measurement] {
        if let t = selectedType {
            return store.measurements.filter { $0.type == t }
        } else {
            return store.measurements
        }
    }

    var groupedMeasurements: [MeasurementSection] {
        let cal = Calendar.current
        let groups = Dictionary(grouping: filteredMeasurements) { entry in
            cal.startOfDay(for: entry.date)
        }
        return groups.keys.sorted(by: >).map { key in
            MeasurementSection(day: key, entries: groups[key]!.sorted { $0.date > $1.date })
        }
    }

    func sectionHeaderTitle(for date: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(date) { return NSLocalizedString("Today", comment: "") }
        if cal.isDateInYesterday(date) { return NSLocalizedString("Yesterday", comment: "") }
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        return formatter.string(from: date)
    }
}


#Preview {
    MeasurementsView().environmentObject(DataStore())
}
