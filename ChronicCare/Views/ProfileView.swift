import SwiftUI
import UIKit
import UserNotifications
import UniformTypeIdentifiers

struct ProfileView: View {
    @EnvironmentObject var store: DataStore
    @State private var showConfirmClear = false
    @State private var showShare = false
    @State private var shareURL: URL?
    @State private var showImporter = false
    @State private var showConfirmExportRecent = false
    @State private var showClearedConfirmation = false
    @State private var showErrorAlert = false
    @State private var errorMessage = ""
    @State private var showSuccessAlert = false
    @State private var successMessage = ""
    @AppStorage("hapticsEnabled") private var hapticsEnabled: Bool = true
    @AppStorage("units.glucose") private var glucoseUnitRaw: String = GlucoseUnit.mgdL.rawValue
    @AppStorage("prefs.graceMinutes") private var graceMinutes: Int = 30
    @AppStorage("prefs.refillThresholdDays") private var refillThresholdDays: Int = 7
    @State private var notifStatus: UNAuthorizationStatus = .notDetermined
    @State private var aiProvider: AIProvider = .openai
    @State private var aiApiKey: String = ""
    @State private var aiOptIn: Bool = false
    @AppStorage("goals.glucose.low") private var glucoseLow: Double = 70
    @AppStorage("goals.glucose.high") private var glucoseHigh: Double = 180
    @AppStorage("goals.hr.low") private var hrLow: Double = 50
    @AppStorage("goals.hr.high") private var hrHigh: Double = 110
    @AppStorage("goals.bp.sysHigh") private var bpSysHigh: Double = 140
    @AppStorage("goals.bp.diaHigh") private var bpDiaHigh: Double = 90

    var body: some View {
        NavigationStack {
            List {
                // MARK: - Apple Health
                Section {
                    Button {
                        HealthKitManager.shared.requestAuthorization { granted, error in
                            DispatchQueue.main.async {
                                if let error = error {
                                    errorMessage = String(format: NSLocalizedString("Could not connect to Health: %@", comment: ""), error.localizedDescription)
                                    showErrorAlert = true
                                } else if granted {
                                    Haptics.success()
                                    successMessage = NSLocalizedString("Connected to Apple Health.", comment: "")
                                    showSuccessAlert = true
                                }
                            }
                        }
                    } label: {
                        Label(NSLocalizedString("Connect Apple Health", comment: ""), systemImage: "heart.fill")
                    }
                    Button {
                        importFromHealth()
                    } label: {
                        Label(NSLocalizedString("Import Last 30 Days", comment: ""), systemImage: "arrow.down.doc.fill")
                    }
                } header: {
                    Text(NSLocalizedString("Apple Health", comment: ""))
                }

                // MARK: - Notifications
                Section {
                    HStack {
                        Label(NSLocalizedString("Status", comment: ""), systemImage: "bell.badge.fill")
                        Spacer()
                        Text(permissionHint())
                            .appFont(.caption)
                            .foregroundStyle(.secondary)
                        if notifStatus != .authorized {
                            permissionButton()
                        }
                    }
                    HStack {
                        Text(NSLocalizedString("Overdue Grace Period", comment: ""))
                        Spacer()
                        Picker("", selection: $graceMinutes) {
                            Text("15m").tag(15)
                            Text("30m").tag(30)
                            Text("1h").tag(60)
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 160)
                    }
                    HStack {
                        Text(NSLocalizedString("Refill Reminder", comment: ""))
                        Spacer()
                        Picker("", selection: $refillThresholdDays) {
                            Text("3d").tag(3)
                            Text("7d").tag(7)
                            Text("14d").tag(14)
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 140)
                    }
                } header: {
                    Text(NSLocalizedString("Notifications", comment: ""))
                }

                // MARK: - Goals
                Section {
                    DisclosureGroup(NSLocalizedString("Blood Glucose", comment: "")) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(String(format: NSLocalizedString("Unit: %@", comment: ""), glucoseUnitLabel))
                                .appFont(.caption)
                                .foregroundStyle(.secondary)
                            Stepper(value: glucoseLowDisplayBinding, in: glucoseLowDisplayRange, step: glucoseDisplayStep) {
                                Text(glucoseLowLabel).appFont(.subheadline)
                            }
                            Stepper(value: glucoseHighDisplayBinding, in: glucoseHighDisplayRange, step: glucoseDisplayStep) {
                                Text(glucoseHighLabel).appFont(.subheadline)
                            }
                        }
                    }
                    DisclosureGroup(NSLocalizedString("Heart Rate", comment: "")) {
                        Stepper(value: $hrLow, in: 30...100, step: 1) {
                            Text(String(format: NSLocalizedString("Low: %d bpm", comment: ""), Int(hrLow))).appFont(.subheadline)
                        }
                        Stepper(value: $hrHigh, in: 80...180, step: 1) {
                            Text(String(format: NSLocalizedString("High: %d bpm", comment: ""), Int(hrHigh))).appFont(.subheadline)
                        }
                    }
                    DisclosureGroup(NSLocalizedString("Blood Pressure", comment: "")) {
                        Stepper(value: $bpSysHigh, in: 90...200, step: 1) {
                            Text(String(format: NSLocalizedString("Systolic High: %d", comment: ""), Int(bpSysHigh))).appFont(.subheadline)
                        }
                        Stepper(value: $bpDiaHigh, in: 50...130, step: 1) {
                            Text(String(format: NSLocalizedString("Diastolic High: %d", comment: ""), Int(bpDiaHigh))).appFont(.subheadline)
                        }
                    }
                } header: {
                    Text(NSLocalizedString("Goals", comment: ""))
                }

                // MARK: - General
                Section {
                    Toggle(NSLocalizedString("Haptic Feedback", comment: ""), isOn: $hapticsEnabled)
                        .onChange(of: hapticsEnabled) { newValue in Haptics.setEnabled(newValue) }
                } header: {
                    Text(NSLocalizedString("General", comment: ""))
                }

                // MARK: - AI Analysis
                Section {
                    Picker(NSLocalizedString("Provider", comment: ""), selection: $aiProvider) {
                        ForEach(AIProvider.allCases, id: \.self) { p in
                            Text(p.rawValue).tag(p)
                        }
                    }
                    SecureField(NSLocalizedString("API Key", comment: ""), text: $aiApiKey)
                        .textContentType(.password)
                        .autocorrectionDisabled()
                    Toggle(NSLocalizedString("Allow AI Analysis", comment: ""), isOn: $aiOptIn)
                    if !aiApiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && aiOptIn {
                        HStack {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                            Text(NSLocalizedString("AI insights enabled", comment: ""))
                                .appFont(.caption)
                                .foregroundStyle(.green)
                        }
                    }
                    Text(NSLocalizedString("Used for drug interaction analysis and trend insights. Your API key is stored securely in Keychain.", comment: ""))
                        .appFont(.caption)
                        .foregroundStyle(.secondary)
                } header: {
                    Text(NSLocalizedString("AI Analysis", comment: ""))
                }

                // MARK: - Data
                Section {
                    Button { exportPDF() } label: {
                        Label(NSLocalizedString("Export PDF Report", comment: ""), systemImage: "doc.richtext")
                    }
                    Button { exportBackup() } label: {
                        Label(NSLocalizedString("Export Backup", comment: ""), systemImage: "externaldrive.fill")
                    }
                    Button { showImporter = true } label: {
                        Label(NSLocalizedString("Restore from Backup", comment: ""), systemImage: "arrow.down.doc")
                    }
                    #if DEBUG
                    Button { showConfirmExportRecent = true } label: {
                        Label("Export 10 to Health", systemImage: "arrow.up.doc.fill")
                    }
                    #endif
                    Button(role: .destructive) { showConfirmClear = true } label: {
                        Label(NSLocalizedString("Clear All Data", comment: ""), systemImage: "trash.fill")
                    }
                } header: {
                    Text(NSLocalizedString("Data", comment: ""))
                }

                // MARK: - About
                Section {
                    Text(NSLocalizedString("Ccare keeps your data on device and uses Apple Health only with your permission. It does not provide medical advice.", comment: ""))
                        .appFont(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle(NSLocalizedString("Settings", comment: ""))
            .alert("Clear all data?", isPresented: $showConfirmClear) {
                Button("Cancel", role: .cancel) {}
                Button("Clear", role: .destructive) {
                    let meds = store.medications
                    meds.forEach { NotificationManager.shared.cancelAll(for: $0) }
                    store.clearAll()
                    NotificationManager.shared.updateBadge(store: store)
                    Haptics.success()
                    showClearedConfirmation = true
                }
            }
            .alert(NSLocalizedString("Data Cleared", comment: ""), isPresented: $showClearedConfirmation) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(NSLocalizedString("All measurements, medications, and logs have been removed.", comment: ""))
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
                        let current = store.medications
                        current.forEach { NotificationManager.shared.cancelAll(for: $0) }
                        store.importBackup(backup)
                        for med in store.medications where med.remindersEnabled {
                            NotificationManager.shared.schedule(for: med)
                        }
                        NotificationManager.shared.cleanOrphanedRequests(validMedicationIDs: Set(store.medications.map { $0.id }))
                        Haptics.success()
                        successMessage = NSLocalizedString("Backup restored successfully.", comment: "")
                        showSuccessAlert = true
                    } catch {
                        errorMessage = String(format: NSLocalizedString("Could not restore backup: %@", comment: ""), error.localizedDescription)
                        showErrorAlert = true
                    }
                case .failure(let error):
                    errorMessage = String(format: NSLocalizedString("Could not open file: %@", comment: ""), error.localizedDescription)
                    showErrorAlert = true
                }
            }
            .alert(NSLocalizedString("Error", comment: ""), isPresented: $showErrorAlert) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage)
            }
            .alert(NSLocalizedString("Success", comment: ""), isPresented: $showSuccessAlert) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(successMessage)
            }
        }
        .onAppear {
            refreshPermissions()
            let config = AIService.shared.getConfiguration()
            aiProvider = config.provider
            aiApiKey = config.apiKey
            aiOptIn = AIService.shared.hasUserConsent
        }
        .onChange(of: aiProvider) { _ in saveAIConfig() }
        .onChange(of: aiApiKey) { _ in saveAIConfig() }
        .onChange(of: aiOptIn) { newVal in AIService.shared.hasUserConsent = newVal }
    }

    // MARK: - Actions

    @MainActor
    private func exportPDF() {
        do {
            let url = try PDFGenerator.generateReport(store: store)
            self.shareURL = url
            self.showShare = true
        } catch {
            errorMessage = String(format: NSLocalizedString("Could not create report: %@", comment: ""), error.localizedDescription)
            showErrorAlert = true
        }
    }

    @MainActor
    private func exportBackup() {
        do {
            let url = try BackupManager.makeBackup(store: store)
            self.shareURL = url
            self.showShare = true
        } catch {
            errorMessage = String(format: NSLocalizedString("Could not create backup: %@", comment: ""), error.localizedDescription)
            showErrorAlert = true
        }
    }

    private func importFromHealth() {
        let start = Calendar.current.date(byAdding: .day, value: -30, to: Date())!
        HealthKitManager.shared.fetchMeasurements(since: start) { list in
            let existing = store.measurements
            let fiveMin: TimeInterval = 5 * 60
            var imported = 0
            for m in list {
                let dup = existing.contains { e in
                    e.type == m.type && abs(e.date.timeIntervalSince(m.date)) < fiveMin &&
                    (e.diastolic ?? -1) == (m.diastolic ?? -2) && abs(e.value - m.value) < 0.0001
                }
                if !dup { store.addMeasurement(m); imported += 1 }
            }
            Haptics.success()
            if imported > 0 {
                successMessage = String(format: NSLocalizedString("Imported %lld new measurements from Health.", comment: ""), imported)
            } else {
                successMessage = NSLocalizedString("No new measurements found in Health.", comment: "")
            }
            showSuccessAlert = true
        }
    }

    #if DEBUG
    private func exportToHealthRecentDedup() {
        let recent = Array(store.measurements.sorted(by: { $0.date > $1.date }).prefix(10))
        let defaults = UserDefaults.standard
        let key = "exported.measurement.ids"
        var exported = Set(defaults.array(forKey: key) as? [String] ?? [])
        let toExport = recent.filter { !exported.contains($0.id.uuidString) }
        guard !toExport.isEmpty else { return }
        for m in toExport {
            HealthKitManager.shared.saveMeasurement(m) { success, error in
                if success {
                    exported.insert(m.id.uuidString)
                    defaults.set(Array(exported), forKey: key)
                }
            }
        }
    }
    #endif

    private func saveAIConfig() {
        AIService.shared.updateConfiguration(AIConfiguration(provider: aiProvider, apiKey: aiApiKey))
    }

    // MARK: - Permissions

    private func refreshPermissions() {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            DispatchQueue.main.async {
                self.notifStatus = settings.authorizationStatus
            }
        }
    }

    private func permissionHint() -> String {
        switch notifStatus {
        case .notDetermined: return NSLocalizedString("Not set up", comment: "")
        case .denied: return NSLocalizedString("Off", comment: "")
        case .authorized, .provisional, .ephemeral: return NSLocalizedString("On", comment: "")
        @unknown default: return ""
        }
    }

    @ViewBuilder
    private func permissionButton() -> some View {
        Button {
            if notifStatus == .denied {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            } else {
                NotificationManager.shared.requestAuthorization()
                refreshPermissions()
            }
        } label: {
            Text(notifStatus == .denied ? NSLocalizedString("Settings", comment: "") : NSLocalizedString("Enable", comment: ""))
                .appFont(.caption)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.mini)
    }

    // MARK: - Glucose goals helpers

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
        String(format: NSLocalizedString("Low: %.0f %@", comment: ""), glucoseLowDisplayBinding.wrappedValue, glucoseUnitLabel)
    }
    private var glucoseHighLabel: String {
        let fmt = gluUnit == .mgdL ? "%.0f" : "%.1f"
        return String(format: "High: \(fmt) %@", glucoseHighDisplayBinding.wrappedValue, glucoseUnitLabel)
    }
}
