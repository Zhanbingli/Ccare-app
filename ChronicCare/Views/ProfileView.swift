import SwiftUI

struct ProfileView: View {
    @EnvironmentObject var store: DataStore
    @State private var showConfirmClear = false
    @State private var hkAuthorized = false
    @State private var showShare = false
    @State private var pdfURL: URL?
    @AppStorage("hapticsEnabled") private var hapticsEnabled: Bool = true
    private let topCardHeight: CGFloat = 96

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    // Summary Cards
                    HStack(spacing: 12) {
                        summaryCard(title: "Measurements", value: "\(store.measurements.count)", systemImage: "waveform.path.ecg", tint: .teal)
                            .frame(height: topCardHeight)
                        summaryCard(title: "Medications", value: "\(store.medications.count)", systemImage: "pills.fill", tint: .indigo)
                            .frame(height: topCardHeight)
                    }
                    .padding(.horizontal)

                    // Adherence + Next medication
                    HStack(spacing: 12) {
                        adherenceCard
                            .frame(height: topCardHeight)
                        nextMedicationCard
                            .frame(height: topCardHeight)
                    }
                    .padding(.horizontal)

                    // Quick Actions
                    sectionHeader("Quick Actions", systemImage: "bolt.fill")
                    Card {
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 12) {
                            ActionTile(color: .green, title: "Connect Health", systemImage: "heart.fill") {
                                HealthKitManager.shared.requestAuthorization { success, error in
                                    DispatchQueue.main.async { hkAuthorized = success }
                                    if let error = error { print("HK auth error: \(error)") }
                                }
                            }
                            ActionTile(color: .orange, title: "Import 30d", systemImage: "arrow.down.doc.fill") {
                                importFromHealth()
                            }
                            ActionTile(color: .blue, title: "Export 10", systemImage: "arrow.up.doc.fill") {
                                exportToHealth()
                            }
                            ActionTile(color: .purple, title: "Export PDF", systemImage: "doc.richtext") { exportPDF() }
                            ActionTile(color: .teal, title: "Load Samples", systemImage: "tray.and.arrow.down") { loadSamples() }
                            ActionTile(color: .red, title: "Clear All", systemImage: "trash.fill") { showConfirmClear = true }
                        }
                    }
                    .padding(.horizontal)

                    // Preferences
                    sectionHeader("Preferences", systemImage: "gear")
                    Card {
                        Toggle("Haptics", isOn: $hapticsEnabled)
                            .onChange(of: hapticsEnabled) { newValue in Haptics.setEnabled(newValue) }
                    }
                    .padding(.horizontal)

                    // About
                    sectionHeader("About", systemImage: "info.circle")
                    Card {
                        Text("Ccare keeps your data on device and uses Apple Health only with your permission. It is intended for wellness tracking and does not provide medical advice.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal)
                }
                .padding(.vertical)
            }
            .navigationTitle("More")
            .alert("Clear all data?", isPresented: $showConfirmClear) {
                Button("Cancel", role: .cancel) {}
                Button("Clear", role: .destructive) { store.clearAll() }
            }
            .sheet(isPresented: $showShare) {
                if let url = pdfURL {
                    ShareSheet(activityItems: [url])
                }
            }
        }
    }

    @MainActor
    private func loadSamples() {
        let now = Date()
        let cal = Calendar.current
        // Measurements
        let samples: [Measurement] = [
            Measurement(type: .bloodPressure, value: 126, diastolic: 82, date: cal.date(byAdding: .day, value: -1, to: now)!, note: "AM"),
            Measurement(type: .bloodGlucose, value: 108, diastolic: nil, date: cal.date(byAdding: .day, value: -2, to: now)!, note: nil),
            Measurement(type: .weight, value: 72.3, diastolic: nil, date: cal.date(byAdding: .day, value: -3, to: now)!, note: nil),
            Measurement(type: .heartRate, value: 68, diastolic: nil, date: cal.date(byAdding: .day, value: -1, to: now)!, note: "resting")
        ]
        samples.forEach { store.addMeasurement($0) }

        // Medications
        let comps1 = DateComponents(hour: 8, minute: 0)
        let comps2 = DateComponents(hour: 20, minute: 0)
        let meds = [
            Medication(name: "Metformin", dose: "500mg", notes: nil, timeOfDay: comps1, remindersEnabled: true),
            Medication(name: "Amlodipine", dose: "5mg", notes: nil, timeOfDay: comps2, remindersEnabled: false)
        ]
        meds.forEach { store.addMedication($0) }
    }

    @MainActor
    private func exportPDF() {
        do {
            let url = try PDFGenerator.generateReport(store: store)
            self.pdfURL = url
            self.showShare = true
        } catch {
            print("PDF export error: \(error)")
        }
    }

    private func importFromHealth() {
        let start = Calendar.current.date(byAdding: .day, value: -30, to: Date())!
        HealthKitManager.shared.fetchMeasurements(since: start) { list in
            let existing = store.measurements
            let fiveMin: TimeInterval = 5 * 60
            for m in list {
                let dup = existing.contains { e in
                    e.type == m.type && abs(e.date.timeIntervalSince(m.date)) < fiveMin &&
                    (e.diastolic ?? -1) == (m.diastolic ?? -2) && abs(e.value - m.value) < 0.0001
                }
                if !dup { store.addMeasurement(m) }
            }
        }
    }

    private func exportToHealth() {
        let recent = Array(store.measurements.sorted(by: { $0.date > $1.date }).prefix(10))
        for m in recent {
            HealthKitManager.shared.saveMeasurement(m) { success, error in
                if let error = error { print("HK save error: \(error)") }
                else { print("Saved to Health: \(success)") }
            }
        }
    }

    private func nextMedication() -> (Medication, Date)? {
        let cal = Calendar.current
        let now = Date()
        return store.medications
            .filter { $0.remindersEnabled }
            .compactMap { med -> (Medication, Date)? in
                guard let h = med.timeOfDay.hour, let m = med.timeOfDay.minute else { return nil }
                let today = cal.date(bySettingHour: h, minute: m, second: 0, of: now)!
                let date = today < now ? cal.date(byAdding: .day, value: 1, to: today)! : today
                return (med, date)
            }
            .sorted(by: { $0.1 < $1.1 })
            .first
    }

    private var adherenceCard: some View {
        let weekly = store.weeklyAdherence()
        let avg = weekly.map { $0.1 }.reduce(0, +) / Double(max(1, weekly.count))
        return Card {
            VStack(alignment: .leading, spacing: 6) {
                Text("Adherence (7d)").font(.headline)
                Text("\(Int(avg * 100))% average").foregroundStyle(.secondary)
            }
        }
    }

    private var nextMedicationCard: some View {
        Card {
            if let (med, date) = nextMedication() {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Next Medication").font(.headline)
                    HStack { Text(med.name).font(.subheadline); Spacer(); Text(date, style: .time).font(.subheadline) }
                    Text(med.dose).font(.caption).foregroundStyle(.secondary)
                }
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Next Medication").font(.headline)
                    Text("No schedule").foregroundStyle(.secondary)
                }
            }
        }
    }
    
    private func summaryCard(title: String, value: String, systemImage: String, tint: Color) -> some View {
        Card {
            HStack(alignment: .center, spacing: 12) {
                ZStack {
                    Circle().fill(tint.opacity(0.18)).frame(width: 40, height: 40)
                    Image(systemName: systemImage)
                        .foregroundStyle(tint)
                        .font(.system(size: 18, weight: .semibold))
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.caption).foregroundStyle(.secondary)
                    Text(value).font(.title3).fontWeight(.semibold)
                }
                Spacer()
            }
        }
    }

    
}

#Preview {
    ProfileView().environmentObject(DataStore())
}
