import SwiftUI
import UIKit
import UserNotifications
import UniformTypeIdentifiers

struct ProfileView: View {
    @EnvironmentObject var store: DataStore
    @State private var showConfirmClear = false
    @State private var hkAuthorized = false
    @State private var showShare = false
    @State private var shareURL: URL?
    @State private var showImporter = false
    @State private var showConfirmExportRecent = false
    @AppStorage("hapticsEnabled") private var hapticsEnabled: Bool = true
    @AppStorage("units.glucose") private var glucoseUnitRaw: String = GlucoseUnit.mgdL.rawValue
    @AppStorage("prefs.graceMinutes") private var graceMinutes: Int = 30
    @AppStorage("eff.mode") private var effMode: String = "balanced"
    @AppStorage("eff.minSamples") private var effMinSamples: Int = 3
    @AppStorage("ui.expand.quick") private var expandQuick: Bool = false
    @AppStorage("ui.expand.goals") private var expandGoals: Bool = false
    @AppStorage("ui.expand.about") private var expandAbout: Bool = false
    @AppStorage("ui.expand.how") private var expandHow: Bool = false
    @AppStorage("ui.expand.prefs") private var expandPrefs: Bool = false
    @AppStorage("ui.expand.perms") private var expandPerms: Bool = true
    @State private var notifStatus: UNAuthorizationStatus = .notDetermined
    private let topCardHeight: CGFloat = 96
    // Goal preferences
    @AppStorage("goals.glucose.low") private var glucoseLow: Double = 70
    @AppStorage("goals.glucose.high") private var glucoseHigh: Double = 180
    @AppStorage("goals.hr.low") private var hrLow: Double = 50
    @AppStorage("goals.hr.high") private var hrHigh: Double = 110
    @AppStorage("goals.bp.sysHigh") private var bpSysHigh: Double = 140
    @AppStorage("goals.bp.diaHigh") private var bpDiaHigh: Double = 90

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    // Summary Cards
                    HStack(spacing: 12) {
                        summaryCard(title: "Measurements", value: "\(store.measurements.count)", systemImage: "waveform.path.ecg", tint: .teal)
                            .frame(maxWidth: .infinity)
                            .frame(height: topCardHeight)
                        summaryCard(title: "Medications", value: "\(store.medications.count)", systemImage: "pills.fill", tint: .indigo)
                            .frame(maxWidth: .infinity)
                            .frame(height: topCardHeight)
                    }
                    .padding(.horizontal)

                    // Adherence + Next medication
                    HStack(spacing: 12) {
                        adherenceCard
                            .frame(maxWidth: .infinity)
                            .frame(height: topCardHeight)
                        nextMedicationCard
                            .frame(maxWidth: .infinity)
                            .frame(height: topCardHeight)
                    }
                    .padding(.horizontal)

                    // Quick Actions (collapsible)
                    SectionToggleHeader("Quick Actions", systemImage: "bolt.fill", isExpanded: $expandQuick)
                    if expandQuick {
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
                                ActionTile(color: .purple, title: "Export Report (PDF)", systemImage: "doc.richtext") { exportPDF() }
                                #if DEBUG
                                ActionTile(color: .blue, title: "Export Recent 10", systemImage: "arrow.up.doc.fill") {
                                    showConfirmExportRecent = true
                                }
                                ActionTile(color: .teal, title: "Load Samples", systemImage: "tray.and.arrow.down") { loadSamples() }
                                #endif
                                ActionTile(color: .red, title: "Clear All", systemImage: "trash.fill") { showConfirmClear = true }
                                ActionTile(color: .blue, title: "Export Data", systemImage: "externaldrive.fill") { exportBackup() }
                                ActionTile(color: .orange, title: "Restore", systemImage: "arrow.down.doc") { showImporter = true }
                            }
                        }
                        .padding(.horizontal)
                    }

                    // Permissions (collapsible)
                    SectionToggleHeader("Permissions", systemImage: "bell.badge", isExpanded: $expandPerms)
                    if expandPerms {
                        Card {
                            VStack(alignment: .leading, spacing: 12) {
                                HStack(alignment: .center) {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(NSLocalizedString("Notifications", comment: "")).font(.subheadline)
                                        Text(permissionHint())
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    permissionButton()
                                }
                                Divider()
                                HStack(alignment: .center) {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("Health").font(.subheadline)
                                        Text(HealthKitManager.shared.isSharingAuthorized() ? NSLocalizedString("Enabled", comment: "") : NSLocalizedString("Not Connected", comment: ""))
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Button {
                                        HealthKitManager.shared.requestAuthorization { success, error in
                                            DispatchQueue.main.async { refreshPermissions() }
                                            if let error = error { print("HK auth error: \(error)") }
                                        }
                                    } label: {
                                        Image(systemName: "heart.fill")
                                            .imageScale(.large)
                                            .accessibilityLabel(NSLocalizedString("Connect Health", comment: ""))
                                    }
                                    .buttonStyle(.bordered)
                                    .controlSize(.small)
                                }
                            }
                        }
                        .padding(.horizontal)
                        .onAppear { refreshPermissions() }
                    }

                    // Preferences (collapsible)
                    SectionToggleHeader("Preferences", systemImage: "gear", isExpanded: $expandPrefs)
                    if expandPrefs {
                        Card {
                            VStack(alignment: .leading, spacing: 12) {
                                Toggle("Haptics", isOn: $hapticsEnabled)
                                    .onChange(of: hapticsEnabled) { newValue in Haptics.setEnabled(newValue) }
                                Divider()
                                // Overdue grace window (minutes)
                                HStack {
                                    Text(NSLocalizedString("Overdue Grace", comment: ""))
                                    Spacer()
                                    Picker("Grace", selection: $graceMinutes) {
                                        Text("15m").tag(15)
                                        Text("30m").tag(30)
                                        Text("60m").tag(60)
                                    }
                                    .pickerStyle(.segmented)
                                    .frame(maxWidth: 220)
                                }
                                Divider()
                                // Default glucose unit
                                HStack {
                                    Text(NSLocalizedString("Blood Glucose Unit", comment: ""))
                                    Spacer()
                                    Picker("Blood Glucose Unit", selection: $glucoseUnitRaw) {
                                        Text(GlucoseUnit.mgdL.rawValue).tag(GlucoseUnit.mgdL.rawValue)
                                        Text(GlucoseUnit.mmolL.rawValue).tag(GlucoseUnit.mmolL.rawValue)
                                    }
                                    .pickerStyle(.segmented)
                                    .frame(maxWidth: 260)
                                    .onChange(of: glucoseUnitRaw) { newValue in
                                        if let u = GlucoseUnit(rawValue: newValue) { UnitPreferences.setGlucoseUnit(u) }
                                    }
                                }
                                Divider()
                                // Effectiveness settings
                                Text(NSLocalizedString("Effectiveness Settings", comment: "")).font(.subheadline)
                                HStack {
                                    Text(NSLocalizedString("Mode", comment: ""))
                                    Spacer()
                                    Picker("Mode", selection: $effMode) {
                                        Text(NSLocalizedString("Conservative", comment: "")).tag("conservative")
                                        Text(NSLocalizedString("Balanced", comment: "")).tag("balanced")
                                        Text(NSLocalizedString("Aggressive", comment: "")).tag("aggressive")
                                    }
                                    .pickerStyle(.segmented)
                                    .frame(maxWidth: 320)
                                }
                                HStack {
                                    Text(NSLocalizedString("Min Samples", comment: ""))
                                    Spacer()
                                    Picker("Min Samples", selection: $effMinSamples) {
                                        Text("3").tag(3)
                                        Text("5").tag(5)
                                        Text("7").tag(7)
                                    }
                                    .pickerStyle(.segmented)
                                    .frame(maxWidth: 220)
                                }
                            }
                        }
                        .padding(.horizontal)
                    }

                    // Goals (collapsible)
                    SectionToggleHeader("Goals", systemImage: "target", isExpanded: $expandGoals)
                    if expandGoals {
                        Card {
                            VStack(alignment: .leading, spacing: 12) {
                                Text("Blood Glucose").font(.subheadline)
                                HStack {
                                    Stepper(value: glucoseLowDisplayBinding,
                                            in: glucoseLowDisplayRange,
                                            step: glucoseDisplayStep) {
                                        Text(glucoseLowLabel)
                                    }
                                    Stepper(value: glucoseHighDisplayBinding,
                                            in: glucoseHighDisplayRange,
                                            step: glucoseDisplayStep) {
                                        Text(glucoseHighLabel)
                                    }
                                }
                                Divider()
                                Text("Heart Rate").font(.subheadline)
                                HStack {
                                    Stepper(value: $hrLow, in: 30...100, step: 1) { Text("Low: \(Int(hrLow)) bpm") }
                                    Stepper(value: $hrHigh, in: 80...180, step: 1) { Text("High: \(Int(hrHigh)) bpm") }
                                }
                                Divider()
                                Text("Blood Pressure (High thresholds)").font(.subheadline)
                                HStack {
                                    Stepper(value: $bpSysHigh, in: 90...200, step: 1) { Text("Sys High: \(Int(bpSysHigh)) mmHg") }
                                    Stepper(value: $bpDiaHigh, in: 50...130, step: 1) { Text("Dia High: \(Int(bpDiaHigh)) mmHg") }
                                }
                            }
                        }
                        .padding(.horizontal)
                    }

                    // About (collapsible)
                    SectionToggleHeader("About", systemImage: "info.circle", isExpanded: $expandAbout)
                    if expandAbout {
                        Card {
                            Text("Ccare keeps your data on device and uses Apple Health only with your permission. It is intended for wellness tracking and does not provide medical advice.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal)
                    }

                    // How It Works (collapsible)
                    SectionToggleHeader("How It Works", systemImage: "questionmark.circle", isExpanded: $expandHow)
                    if expandHow {
                        Card {
                            VStack(alignment: .leading, spacing: 12) {
                                Text(NSLocalizedString("Trends Calculations", comment: "")).font(.headline)
                                VStack(alignment: .leading, spacing: 6) {
                                    bullet(NSLocalizedString("Trends.Range", comment: ""))
                                    bullet(NSLocalizedString("Trends.BP", comment: ""))
                                    bullet(NSLocalizedString("Trends.Other", comment: ""))
                                }
                                Divider()
                                Text(NSLocalizedString("Adherence Calculations", comment: "")).font(.headline)
                                VStack(alignment: .leading, spacing: 6) {
                                    bullet(NSLocalizedString("Adherence.Def", comment: ""))
                                    bullet(NSLocalizedString("Adherence.Keys", comment: ""))
                                }
                                Divider()
                                Text(NSLocalizedString("Effectiveness How", comment: "")).font(.headline)
                                VStack(alignment: .leading, spacing: 6) {
                                    bullet(NSLocalizedString("Effectiveness.How.1", comment: ""))
                                    bullet(NSLocalizedString("Effectiveness.How.2", comment: ""))
                                    bullet(NSLocalizedString("Effectiveness.How.3", comment: ""))
                                    bullet(NSLocalizedString("Effectiveness.How.4", comment: ""))
                                }
                                Divider()
                                Text(NSLocalizedString("Overdue Reminders", comment: "")).font(.headline)
                                VStack(alignment: .leading, spacing: 6) {
                                    bullet(NSLocalizedString("Overdue.Def", comment: ""))
                                    bullet(NSLocalizedString("Overdue.Suppress", comment: ""))
                                }
                                Divider()
                                Text(NSLocalizedString("Units Goals", comment: "")).font(.headline)
                                VStack(alignment: .leading, spacing: 6) {
                                    bullet(NSLocalizedString("Units.Glucose", comment: ""))
                                    bullet(NSLocalizedString("Goals.Source", comment: ""))
                                }
                                Divider()
                                Text(NSLocalizedString("Data Privacy", comment: "")).font(.headline)
                                VStack(alignment: .leading, spacing: 6) {
                                    bullet(NSLocalizedString("Data.Stored", comment: ""))
                                }
                            }
                        }
                        .padding(.horizontal)
                    }
                }
                .padding(.vertical)
            }
            .navigationTitle("More")
            .alert("Clear all data?", isPresented: $showConfirmClear) {
                Button("Cancel", role: .cancel) {}
                Button("Clear", role: .destructive) {
                    // Cancel all existing reminders before clearing
                    let meds = store.medications
                    meds.forEach { NotificationManager.shared.cancelAll(for: $0) }
                    store.clearAll()
                    NotificationManager.shared.updateBadge(store: store)
                }
            }
            #if DEBUG
            .alert("Export recent 10 to Health?", isPresented: $showConfirmExportRecent) {
                Button("Cancel", role: .cancel) {}
                Button("Export") { exportToHealthRecentDedup() }
            }
            #endif
            .sheet(isPresented: $showShare) {
                if let url = shareURL {
                    ShareSheet(activityItems: [url])
                }
            }
            .fileImporter(isPresented: $showImporter, allowedContentTypes: [.json]) { result in
                switch result {
                case .success(let url):
                    do {
                        let backup = try BackupManager.loadBackup(from: url)
                        // Cancel reminders for current meds to avoid leftovers
                        let current = store.medications
                        current.forEach { NotificationManager.shared.cancelAll(for: $0) }
                        store.importBackup(backup)
                        // Reschedule reminders for restored meds
                        for med in store.medications where med.remindersEnabled {
                            NotificationManager.shared.schedule(for: med)
                        }
                    } catch {
                        print("Backup import error: \(error)")
                    }
                case .failure(let error):
                    print("File import error: \(error)")
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
            Medication(name: "Metformin", dose: "500mg", notes: nil, timesOfDay: [comps1], remindersEnabled: true),
            Medication(name: "Amlodipine", dose: "5mg", notes: nil, timesOfDay: [comps2], remindersEnabled: false)
        ]
        meds.forEach { store.addMedication($0) }
    }

    @MainActor
    private func exportPDF() {
        do {
            let url = try PDFGenerator.generateReport(store: store)
            self.shareURL = url
            self.showShare = true
        } catch {
            print("PDF export error: \(error)")
        }
    }

    @MainActor
    private func exportBackup() {
        do {
            let url = try BackupManager.makeBackup(store: store)
            self.shareURL = url
            self.showShare = true
        } catch {
            print("Backup export error: \(error)")
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

    #if DEBUG
    private func exportToHealthRecentDedup() {
        let recent = Array(store.measurements.sorted(by: { $0.date > $1.date }).prefix(10))
        let defaults = UserDefaults.standard
        let key = "exported.measurement.ids"
        var exported = Set(defaults.array(forKey: key) as? [String] ?? [])
        let toExport = recent.filter { !exported.contains($0.id.uuidString) }
        guard !toExport.isEmpty else { print("No new items to export"); return }
        for m in toExport {
            HealthKitManager.shared.saveMeasurement(m) { success, error in
                if let error = error {
                    print("HK save error: \(error)")
                } else if success {
                    exported.insert(m.id.uuidString)
                    defaults.set(Array(exported), forKey: key)
                    print("Saved to Health and marked exported: \(m.id)")
                }
            }
        }
    }
    #endif

    private func nextMedication() -> (Medication, Date)? {
        let cal = Calendar.current
        let now = Date()
        var pairs: [(Medication, Date)] = []
        for med in store.medications where med.remindersEnabled {
            for t in med.timesOfDay {
                guard let h = t.hour, let m = t.minute else { continue }
                let today = cal.date(bySettingHour: h, minute: m, second: 0, of: now)!
                let date = today < now ? cal.date(byAdding: .day, value: 1, to: today)! : today
                pairs.append((med, date))
            }
        }
        return pairs.sorted(by: { $0.1 < $1.1 }).first
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

    // MARK: - Glucose goals helpers (display in preferred unit, store in mg/dL)
    private var gluUnit: GlucoseUnit { GlucoseUnit(rawValue: glucoseUnitRaw) ?? .mgdL }
    private var glucoseDisplayStep: Double { gluUnit == .mgdL ? 1.0 : 0.1 }
    private var glucoseUnitLabel: String { gluUnit.rawValue }

    private var glucoseLowDisplayBinding: Binding<Double> {
        Binding<Double>(
            get: { UnitPreferences.convertFromMgdl(glucoseLow, to: gluUnit) },
            set: { newVal in glucoseLow = UnitPreferences.convertToMgdl(newVal, from: gluUnit) }
        )
    }
    private var glucoseHighDisplayBinding: Binding<Double> {
        Binding<Double>(
            get: { UnitPreferences.convertFromMgdl(glucoseHigh, to: gluUnit) },
            set: { newVal in glucoseHigh = UnitPreferences.convertToMgdl(newVal, from: gluUnit) }
        )
    }
    private var glucoseLowDisplayRange: ClosedRange<Double> {
        let min = UnitPreferences.convertFromMgdl(40, to: gluUnit)
        let max = UnitPreferences.convertFromMgdl(200, to: gluUnit)
        return min...max
    }
    private var glucoseHighDisplayRange: ClosedRange<Double> {
        let min = UnitPreferences.convertFromMgdl(80, to: gluUnit)
        let max = UnitPreferences.convertFromMgdl(300, to: gluUnit)
        return min...max
    }
    private var glucoseLowLabel: String {
        let v = UnitPreferences.convertFromMgdl(glucoseLow, to: gluUnit)
        if gluUnit == .mgdL { return "Low: \(Int(v)) \(glucoseUnitLabel)" }
        return String(format: "Low: %.1f %@", v, glucoseUnitLabel)
    }
    private var glucoseHighLabel: String {
        let v = UnitPreferences.convertFromMgdl(glucoseHigh, to: gluUnit)
        if gluUnit == .mgdL { return "High: \(Int(v)) \(glucoseUnitLabel)" }
        return String(format: "High: %.1f %@", v, glucoseUnitLabel)
    }

    // MARK: - Bulleted helper
    @ViewBuilder
    private func bullet(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text("•")
            Text(text)
                .foregroundStyle(.secondary)
        }
        .font(.footnote)
    }
}

// MARK: - Permissions helpers
private extension ProfileView {
    func refreshPermissions() {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            DispatchQueue.main.async { self.notifStatus = settings.authorizationStatus }
        }
    }

    func permissionHint() -> String {
        switch notifStatus {
        case .notDetermined: return NSLocalizedString("Enable notifications to get timely reminders", comment: "")
        case .denied: return NSLocalizedString("Notifications are off in Settings", comment: "")
        case .authorized, .provisional, .ephemeral: return NSLocalizedString("Notifications enabled", comment: "")
        @unknown default: return ""
        }
    }

    @ViewBuilder
    func permissionButton() -> some View {
        switch notifStatus {
        case .notDetermined:
            Button {
                UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in
                    DispatchQueue.main.async { refreshPermissions() }
                }
            } label: {
                Image(systemName: "bell.badge.fill")
                    .imageScale(.large)
                    .accessibilityLabel(NSLocalizedString("Enable Notifications", comment: ""))
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        case .denied:
            Button {
                if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
            } label: {
                Image(systemName: "gearshape.fill")
                    .imageScale(.large)
                    .accessibilityLabel(NSLocalizedString("Open Settings", comment: ""))
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        case .authorized, .provisional, .ephemeral:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .imageScale(.large)
                .accessibilityLabel(NSLocalizedString("Enabled", comment: ""))
        @unknown default:
            EmptyView()
        }
    }
}

#Preview {
    ProfileView().environmentObject(DataStore())
}
