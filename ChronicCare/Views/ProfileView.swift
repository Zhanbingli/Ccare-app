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
    @State private var showExportSheet = false
    @State private var showAISection = false
    @State private var showDataSection = false
    @AppStorage("hapticsEnabled") private var hapticsEnabled: Bool = true
    @AppStorage("units.glucose") private var glucoseUnitRaw: String = GlucoseUnit.mgdL.rawValue
    @AppStorage("prefs.graceMinutes") private var graceMinutes: Int = 30
    @AppStorage("prefs.refillThresholdDays") private var refillThresholdDays: Int = 7
    @AppStorage("prefs.courseEndThresholdDays") private var courseEndThresholdDays: Int = 3
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
                            if let error = error {
                                errorMessage = String(format: NSLocalizedString("Could not connect to Health: %@", comment: ""), error.localizedDescription)
                                showErrorAlert = true
                            } else if granted {
                                Haptics.success()
                                successMessage = NSLocalizedString("Connected to Apple Health.", comment: "")
                                showSuccessAlert = true
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
                        if !notificationsEnabled {
                            permissionButton()
                        }
                    }
                    Text(notificationCoverageSummary)
                        .appFont(.caption)
                        .foregroundStyle(.secondary)

                    DisclosureGroup(NSLocalizedString("Reminder Rules", comment: "")) {
                        LabeledContent(NSLocalizedString("Overdue Grace Period", comment: "")) {
                            Menu(graceMinutesLabel) {
                                Button("15 min") { graceMinutes = 15 }
                                Button("30 min") { graceMinutes = 30 }
                                Button("1 hour") { graceMinutes = 60 }
                            }
                        }
                        LabeledContent(NSLocalizedString("Refill Reminder", comment: "")) {
                            Menu(refillThresholdLabel) {
                                Button("3 days") { refillThresholdDays = 3 }
                                Button("7 days") { refillThresholdDays = 7 }
                                Button("14 days") { refillThresholdDays = 14 }
                            }
                        }
                        LabeledContent(NSLocalizedString("Course End Reminder", comment: "")) {
                            Menu(courseEndThresholdLabel) {
                                Button("1 day") { courseEndThresholdDays = 1 }
                                Button("3 days") { courseEndThresholdDays = 3 }
                                Button("7 days") { courseEndThresholdDays = 7 }
                            }
                        }
                    }
                } header: {
                    Text(NSLocalizedString("Notifications", comment: ""))
                } footer: {
                    Text(NSLocalizedString("Scheduled medications need both permission and reminder times before alerts can fire.", comment: ""))
                        .appFont(.caption)
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

                // MARK: - Care & Emergency
                Section {
                    NavigationLink {
                        EmergencyInfoEditView().environmentObject(store)
                    } label: {
                        Label(NSLocalizedString("Edit Emergency Info", comment: ""), systemImage: "cross.case")
                    }
                    NavigationLink {
                        EmergencyCardView().environmentObject(store)
                    } label: {
                        Label(NSLocalizedString("View Emergency Card", comment: ""), systemImage: "person.text.rectangle")
                    }
                    NavigationLink {
                        CaregiversView().environmentObject(store)
                    } label: {
                        Label(NSLocalizedString("Manage Caregivers", comment: ""), systemImage: "person.2")
                    }
                } header: {
                    Text(NSLocalizedString("Care & Emergency", comment: ""))
                } footer: {
                    Text(NSLocalizedString("Keep emergency details and caregiver access up to date for missed-dose support.", comment: ""))
                        .appFont(.caption)
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
                    Toggle(NSLocalizedString("Allow AI Analysis", comment: ""), isOn: $aiOptIn)

                    if aiOptIn {
                        DisclosureGroup(NSLocalizedString("Provider & API Access", comment: ""), isExpanded: $showAISection) {
                            Picker(NSLocalizedString("Provider", comment: ""), selection: $aiProvider) {
                                ForEach(AIProvider.allCases, id: \.self) { p in
                                    Text(p.rawValue).tag(p)
                                }
                            }
                            SecureField(NSLocalizedString("API Key", comment: ""), text: $aiApiKey)
                                .textContentType(.password)
                                .autocorrectionDisabled()
                            Button {
                                let urlStr: String
                                switch aiProvider {
                                case .openai: urlStr = "https://platform.openai.com/api-keys"
                                case .anthropic: urlStr = "https://console.anthropic.com/settings/keys"
                                }
                                if let url = URL(string: urlStr) {
                                    UIApplication.shared.open(url)
                                }
                            } label: {
                                Label(String(format: NSLocalizedString("Get %@ API Key", comment: ""), aiProvider.rawValue), systemImage: "key.fill")
                                    .appFont(.subheadline)
                            }
                        }

                        if !aiApiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            HStack {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.green)
                                Text(NSLocalizedString("AI insights enabled", comment: ""))
                                    .appFont(.caption)
                                    .foregroundStyle(.green)
                            }
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
                    DisclosureGroup(NSLocalizedString("Backup & Export", comment: ""), isExpanded: $showDataSection) {
                        Button { showExportSheet = true } label: {
                            Label(NSLocalizedString("Export Reports", comment: ""), systemImage: "doc.richtext")
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
                    }
                } header: {
                    Text(NSLocalizedString("Data", comment: ""))
                } footer: {
                    Text(NSLocalizedString("Use backup before restoring or clearing data on this device.", comment: ""))
                        .appFont(.caption)
                }

                Section {
                    Button(role: .destructive) { showConfirmClear = true } label: {
                        Label(NSLocalizedString("Clear All Data", comment: ""), systemImage: "trash.fill")
                    }
                } header: {
                    Text(NSLocalizedString("Danger Zone", comment: ""))
                } footer: {
                    Text(NSLocalizedString("This permanently removes medications, measurements, and intake history from this device.", comment: ""))
                        .appFont(.caption)
                }

                // MARK: - About
                Section {
                    Text(NSLocalizedString("ChronicCare keeps your data on device and uses Apple Health only with your permission. It does not provide medical advice.", comment: ""))
                        .appFont(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle(NSLocalizedString("Settings", comment: ""))
            .navigationBarTitleDisplayMode(.inline)
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
            .sheet(isPresented: $showExportSheet) {
                ExportOptionsSheet(store: store)
            }
            .fileImporter(isPresented: $showImporter, allowedContentTypes: [.json]) { result in
                switch result {
                case .success(let url):
                    do {
                        let backup = try BackupManager.loadBackup(from: url)
                        let current = store.medications
                        current.forEach { NotificationManager.shared.cancelAll(for: $0) }
                        store.importBackup(backup)
                        NotificationManager.shared.syncAll(medications: store.medications, intakeLogs: store.intakeLogs)
                        NotificationManager.shared.updateBadge(store: store)
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
        .onChange(of: graceMinutes) { _ in refreshNotificationConfiguration() }
        .onChange(of: refillThresholdDays) { _ in refreshNotificationConfiguration() }
        .onChange(of: courseEndThresholdDays) { _ in refreshNotificationConfiguration() }
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

    private func refreshNotificationConfiguration() {
        NotificationManager.shared.syncAll(medications: store.medications, intakeLogs: store.intakeLogs)
        NotificationManager.shared.updateBadge(store: store)
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

    private var graceMinutesLabel: String {
        switch graceMinutes {
        case 15: return "15 min"
        case 30: return "30 min"
        case 60: return "1 hour"
        default: return "\(graceMinutes) min"
        }
    }

    private var refillThresholdLabel: String {
        switch refillThresholdDays {
        case 3: return "3 days"
        case 7: return "7 days"
        case 14: return "14 days"
        default: return "\(refillThresholdDays) days"
        }
    }

    private var courseEndThresholdLabel: String {
        switch courseEndThresholdDays {
        case 1: return "1 day"
        case 3: return "3 days"
        case 7: return "7 days"
        default: return "\(courseEndThresholdDays) days"
        }
    }

    private var notificationsEnabled: Bool {
        switch notifStatus {
        case .authorized, .provisional, .ephemeral:
            return true
        default:
            return false
        }
    }

    private var scheduledWithoutRemindersCount: Int {
        store.medications.filter {
            $0.isAsNeeded != true && !$0.timesOfDay.isEmpty && !$0.remindersEnabled
        }.count
    }

    private var untimedScheduledCount: Int {
        store.medications.filter {
            $0.isAsNeeded != true && $0.timesOfDay.isEmpty
        }.count
    }

    private var notificationCoverageSummary: String {
        if notifStatus == .denied {
            return NSLocalizedString("System notifications are currently off. Scheduled reminders will not fire until permission is restored.", comment: "")
        }
        if untimedScheduledCount > 0 {
            return String(format: NSLocalizedString("%lld scheduled medications still need reminder times.", comment: ""), untimedScheduledCount)
        }
        if scheduledWithoutRemindersCount > 0 {
            return String(format: NSLocalizedString("%lld scheduled medications currently have reminders turned off.", comment: ""), scheduledWithoutRemindersCount)
        }
        return NSLocalizedString("Reminder coverage looks healthy for your scheduled medications.", comment: "")
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

// MARK: - Export Options Sheet

private struct ExportOptionsSheet: View {
    @ObservedObject var store: DataStore
    @Environment(\.dismiss) private var dismiss
    @State private var exportDays: Int = 30
    @State private var useCustomRange = false
    @State private var customStart = Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? Date()
    @State private var customEnd = Date()
    @State private var showShare = false
    @State private var shareURL: URL?
    @State private var errorMessage: String?

    private var dateRange: (start: Date, end: Date) {
        if useCustomRange {
            return (Calendar.current.startOfDay(for: customStart),
                    Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: customEnd)) ?? Date())
        }
        let end = Date()
        let start = Calendar.current.date(byAdding: .day, value: -exportDays, to: end) ?? end
        return (start, end)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle(NSLocalizedString("Custom Date Range", comment: ""), isOn: $useCustomRange)
                    if useCustomRange {
                        DatePicker(NSLocalizedString("Start", comment: ""), selection: $customStart, displayedComponents: .date)
                        DatePicker(NSLocalizedString("End", comment: ""), selection: $customEnd, displayedComponents: .date)
                    } else {
                        Picker(NSLocalizedString("Period", comment: ""), selection: $exportDays) {
                            Text(NSLocalizedString("7 days", comment: "")).tag(7)
                            Text(NSLocalizedString("30 days", comment: "")).tag(30)
                            Text(NSLocalizedString("90 days", comment: "")).tag(90)
                        }
                        .pickerStyle(.segmented)
                    }
                } header: {
                    Text(NSLocalizedString("Time Range", comment: ""))
                }

                Section {
                    Button {
                        exportPDF()
                    } label: {
                        Label(NSLocalizedString("Export PDF Report", comment: ""), systemImage: "doc.richtext")
                    }
                    Button {
                        exportIntakeCSV()
                    } label: {
                        Label(NSLocalizedString("Export Intake Log (CSV)", comment: ""), systemImage: "tablecells")
                    }
                    Button {
                        exportMeasurementsCSV()
                    } label: {
                        Label(NSLocalizedString("Export Measurements (CSV)", comment: ""), systemImage: "chart.line.uptrend.xyaxis")
                    }
                } header: {
                    Text(NSLocalizedString("Export Format", comment: ""))
                }

                if let err = errorMessage {
                    Section {
                        Text(err).foregroundStyle(.red).appFont(.caption)
                    }
                }
            }
            .navigationTitle(NSLocalizedString("Export Reports", comment: ""))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(NSLocalizedString("Done", comment: "")) { dismiss() }
                }
            }
            .sheet(isPresented: $showShare) {
                if let url = shareURL {
                    ShareSheet(activityItems: [url])
                }
            }
        }
    }

    private func exportPDF() {
        do {
            let days = useCustomRange
                ? max(1, Calendar.current.dateComponents([.day], from: customStart, to: customEnd).day ?? 30)
                : exportDays
            let url = try PDFGenerator.generateReport(store: store, days: days)
            shareURL = url
            showShare = true
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func exportIntakeCSV() {
        do {
            let range = dateRange
            let url = try BackupManager.generateIntakeCSV(store: store, startDate: range.start, endDate: range.end)
            shareURL = url
            showShare = true
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func exportMeasurementsCSV() {
        do {
            let range = dateRange
            let url = try BackupManager.generateMeasurementsCSV(store: store, startDate: range.start, endDate: range.end)
            shareURL = url
            showShare = true
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
