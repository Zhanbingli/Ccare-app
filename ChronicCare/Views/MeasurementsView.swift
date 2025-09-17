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
                    EmptyStateView(systemImage: "heart.text.square", title: "No measurements yet", subtitle: NSLocalizedString("Add your first measurement", comment: ""), actionTitle: NSLocalizedString("Add", comment: "")) {
                        showAdd = true
                    }
                    .listRowBackground(Color.clear)
                } else {
                    ForEach(groupedMeasurements, id: \.day) { section in
                        Section(header: Text(sectionHeaderTitle(for: section.day)).appFont(.subheadline).foregroundStyle(.secondary)) {
                            ForEach(section.entries) { m in
                                TintedCard(tint: m.cardTint) {
                                    VStack(alignment: .leading, spacing: 6) {
                                        HStack(alignment: .firstTextBaseline) {
                                            Text(m.type.rawValue).appFont(.headline)
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
                                .cornerRadius(16, corners: [.topLeft, .bottomLeft])
                                .listRowBackground(Color.clear)
                                .listRowSeparator(.hidden)
                                .listRowInsets(EdgeInsets())
                                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                    Button(role: .destructive) {
                                        if let i = store.measurements.firstIndex(where: { $0.id == m.id }) {
                                            store.removeMeasurement(at: IndexSet(integer: i))
                                        }
                                    } label: { Label("Delete", systemImage: "trash") }
                                    .tint(.red)
                                }
                                .swipeActions(edge: .leading, allowsFullSwipe: true) {
                                    Button(role: .destructive) {
                                        if let i = store.measurements.firstIndex(where: { $0.id == m.id }) {
                                            store.removeMeasurement(at: IndexSet(integer: i))
                                        }
                                    } label: { Label("Delete", systemImage: "trash") }
                                    .tint(.red)
                                }
                                .contextMenu {
                                    Button(role: .destructive) { if let i = store.measurements.firstIndex(where: { $0.id == m.id }) { store.removeMeasurement(at: IndexSet(integer: i)) } } label: { Label("Delete", systemImage: "trash") }
                                    Button { UIPasteboard.general.string = "\(m.type.rawValue): \(m.value)" } label: { Label("Copy", systemImage: "doc.on.doc") }
                                }
                                .padding(.vertical, 2)
                            }
                        }
                    }
                }
            }
            .applyListStyling()
            .navigationTitle("Measurements")
            .navigationBarTitleDisplayMode(.inline)
            .safeAreaInset(edge: .top) {
                VStack(spacing: 8) {
                    Picker("Type", selection: $selectedType) {
                        Text("All").tag(MeasurementType?.none)
                        ForEach(MeasurementType.allCases) { t in
                            Text(t.rawValue).tag(Optional(t))
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
    @State private var glucoseUnit: GlucoseUnit = UnitPreferences.glucoseUnit
    @State private var overrideGlucoseUnit: Bool = false

    var body: some View {
        NavigationStack {
            Form {
                Picker("Type", selection: $type) {
                    ForEach(MeasurementType.allCases) { t in
                        Text(t.rawValue).tag(t)
                    }
                }
                if type == .bloodPressure {
                    HStack {
                        Text(NSLocalizedString("Systolic:", comment: ""))
                        Spacer()
                        TextField("", text: $systolicInput)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .frame(maxWidth: 140)
                    }
                    HStack {
                        Text(NSLocalizedString("Diastolic:", comment: ""))
                        Spacer()
                        TextField("", text: $diastolicInput)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .frame(maxWidth: 140)
                    }
                } else {
                    HStack {
                        Text(NSLocalizedString("Value", comment: ""))
                        Spacer()
                        TextField("", text: $valueInput)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(maxWidth: 140)
                    }
                    if type == .bloodGlucose {
                        if overrideGlucoseUnit {
                            Picker("Unit", selection: $glucoseUnit) {
                                ForEach(GlucoseUnit.allCases) { u in
                                    Text(u.rawValue).tag(u)
                                }
                            }
                            .pickerStyle(.segmented)
                        } else {
                            HStack {
                                Text(String(format: NSLocalizedString("Unit: %@", comment: ""), UnitPreferences.glucoseUnit.rawValue))
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Button(NSLocalizedString("Change Unit", comment: "")) { overrideGlucoseUnit = true }
                            }
                        }
                    } else {
                        Text(String(format: NSLocalizedString("Unit: %@", comment: ""), type.unit))
                            .foregroundStyle(.secondary)
                    }
                }
                DatePicker("Date", selection: $date)
                TextField("Note (optional)", text: $note)
            }
            .navigationTitle("Add Measurement")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        guard let measurement = makeMeasurement() else { return }
                        onSave(measurement)
                        Haptics.success()
                        dismiss()
                    }
                    .disabled(!canSave)
                }
            }
            .onChange(of: type) { newType in
                switch newType {
                case .bloodPressure:
                    valueInput = ""
                default:
                    systolicInput = ""
                    diastolicInput = ""
                }
            }
        }
    }
}

private extension AddMeasurementView {
    var canSave: Bool {
        switch type {
        case .bloodPressure:
            return Double(systolicInput) != nil && Double(diastolicInput) != nil
        default:
            return Double(valueInput) != nil
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
            let unitToUse = overrideGlucoseUnit ? glucoseUnit : UnitPreferences.glucoseUnit
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

private extension View {
    @ViewBuilder
    func applyListStyling() -> some View {
        if #available(iOS 16.0, *) {
            self
                .scrollContentBackground(.hidden)
                .background(Color(.systemGroupedBackground))
        } else {
            self
        }
    }
}

#Preview {
    MeasurementsView().environmentObject(DataStore())
}
