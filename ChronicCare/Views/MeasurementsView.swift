import SwiftUI
import UIKit

struct MeasurementsView: View {
    @EnvironmentObject var store: DataStore
    @State private var showAdd = false
    @State private var selectedType: MeasurementType? = nil

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Picker("Type", selection: $selectedType) {
                        Text("All").tag(MeasurementType?.none)
                        ForEach(MeasurementType.allCases) { t in
                            Text(t.rawValue).tag(Optional(t))
                        }
                    }
                    .pickerStyle(.segmented)
                }
                if filteredMeasurements.isEmpty {
                    EmptyStateView(systemImage: "heart.text.square", title: "No measurements yet")
                        .listRowBackground(Color.clear)
                } else {
                    ForEach(filteredMeasurements) { m in
                        TintedCard(tint: m.cardTint) {
                            VStack(alignment: .leading, spacing: 6) {
                                HStack(alignment: .firstTextBaseline) {
                                    Text(m.type.rawValue).font(.headline)
                                    Spacer()
                                    if m.type == .bloodPressure, let d = m.diastolic {
                                        Text("\(Int(m.value))/\(Int(d)) \(m.type.unit)")
                                            .font(.headline)
                                            .foregroundStyle(m.valueForeground)
                                    } else {
                                        Text("\(String(format: "%.1f", m.value)) \(m.type.unit)")
                                            .font(.headline)
                                            .foregroundStyle(m.valueForeground)
                                    }
                                }
                                HStack(spacing: 8) {
                                    Text(m.date, style: .date)
                                    Text(m.date, style: .time)
                                }
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                if let note = m.note, !note.isEmpty {
                                    Text(note).font(.footnote)
                                }
                            }
                        }
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets())
                        .contextMenu {
                            Button(role: .destructive) { if let i = store.measurements.firstIndex(where: { $0.id == m.id }) { store.removeMeasurement(at: IndexSet(integer: i)) } } label: { Label("Delete", systemImage: "trash") }
                            Button { UIPasteboard.general.string = "\(m.type.rawValue): \(m.value)" } label: { Label("Copy", systemImage: "doc.on.doc") }
                        }
                        .padding(.vertical, 2)
                    }
                    .onDelete(perform: delete)
                }
            }
            .navigationTitle("Measurements")
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
    @State private var value: Double = 120
    @State private var diastolic: Double = 80
    @State private var note: String = ""
    @State private var date: Date = Date()

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
                        Stepper(value: $value, in: 60...240, step: 1) { Text("Systolic: \(Int(value))") }
                    }
                    HStack {
                        Stepper(value: $diastolic, in: 40...140, step: 1) { Text("Diastolic: \(Int(diastolic))") }
                    }
                } else {
                    HStack {
                        Text("Value")
                        Spacer()
                        TextField("0", value: $value, format: .number)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(maxWidth: 120)
                    }
                    Text("Unit: \(type.unit)").foregroundStyle(.secondary)
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
                        let m = Measurement(
                            type: type,
                            value: value,
                            diastolic: type == .bloodPressure ? diastolic : nil,
                            date: date,
                            note: note.isEmpty ? nil : note
                        )
                        onSave(m)
                        Haptics.success()
                        dismiss()
                    }
                }
            }
        }
    }
}

private extension MeasurementsView {
    var filteredMeasurements: [Measurement] {
        if let t = selectedType {
            return store.measurements.filter { $0.type == t }
        } else {
            return store.measurements
        }
    }
    func delete(at offsets: IndexSet) {
        let ids = offsets.map { filteredMeasurements[$0].id }
        var remove = IndexSet()
        for id in ids {
            if let idx = store.measurements.firstIndex(where: { $0.id == id }) {
                remove.insert(idx)
            }
        }
        if !remove.isEmpty { store.removeMeasurement(at: remove) }
    }
}

#Preview {
    MeasurementsView().environmentObject(DataStore())
}
