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
                    // Summary row
                    HStack(spacing: 12) {
                        summaryCard(title: "Measurements", value: "\(store.measurements.count)", systemImage: "waveform.path.ecg", tint: .teal)
                            .frame(maxWidth: .infinity)
                            .frame(height: topCardHeight)
                        summaryCard(title: "Medications", value: "\(store.medications.count)", systemImage: "pills.fill", tint: .indigo)
                            .frame(maxWidth: .infinity)
                            .frame(height: topCardHeight)
                    }

                    // Adherence + next medication
                    HStack(spacing: 12) {
                        adherenceCard
                            .frame(maxWidth: .infinity)
                            .frame(height: topCardHeight)
                        nextMedicationCard
                            .frame(maxWidth: .infinity)
                            .frame(height: topCardHeight)
                    }

                    statusOverviewCard
                    quickActionsCard
                    preferencesCard
                    goalsCard
                    dataManagementCard
                    knowledgeCard
                    aboutCard
                }
                .padding(.vertical, 24)
                .padding(.horizontal)
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
        .onAppear { refreshPermissions() }
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
                Text("Adherence (7d)").appFont(.headline)
                Text("\(Int(avg * 100))% average").appFont(.footnote).foregroundStyle(.secondary)
            }
        }
    }

    private var nextMedicationCard: some View {
        Card {
            if let (med, date) = nextMedication() {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Next Medication").appFont(.headline)
                    HStack {
                        Text(med.name).appFont(.subheadline)
                        Spacer()
                        Text(date, style: .time).appFont(.subheadline)
                    }
                    Text(med.dose).appFont(.caption).foregroundStyle(.secondary)
                }
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Next Medication").appFont(.headline)
                    Text("No schedule").appFont(.footnote).foregroundStyle(.secondary)
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
                    Text(title).appFont(.caption).foregroundStyle(.secondary)
                    Text(value).appFont(.title)
                }
                Spacer()
            }
        }
    }

    private var statusOverviewCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                Text(NSLocalizedString("Status", comment: "")).appFont(.headline)
                HStack(alignment: .center, spacing: 12) {
                    Image(systemName: "bell.badge.fill").foregroundStyle(.orange)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(NSLocalizedString("Notifications", comment: "")).appFont(.subheadline)
                        Text(permissionHint()).appFont(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    permissionButton()
                }
                Divider()
                HStack(alignment: .center, spacing: 12) {
                    Image(systemName: "heart.fill").foregroundStyle(.red)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Health").appFont(.subheadline)
                        Text(HealthKitManager.shared.isSharingAuthorized() ? NSLocalizedString("Synced", comment: "") : NSLocalizedString("Not Connected", comment: ""))
                            .appFont(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button {
                        HealthKitManager.shared.requestAuthorization { success, error in
                            DispatchQueue.main.async { refreshPermissions() }
                            if let error = error { print("HK auth error: \(error)") }
                        }
                    } label: {
                        Text(HealthKitManager.shared.isSharingAuthorized() ? NSLocalizedString("Manage", comment: "") : NSLocalizedString("Connect", comment: ""))
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
    }

    private var quickActionsCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                Text("Quick Actions").appFont(.headline)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        quickActionPill(title: "Connect Health", icon: "heart.fill", tint: .pink) {
                            HealthKitManager.shared.requestAuthorization { success, error in
                                DispatchQueue.main.async { hkAuthorized = success }
                                if let error = error { print("HK auth error: \(error)") }
                            }
                        }
                        quickActionPill(title: "Import 30d", icon: "arrow.down.doc.fill", tint: .orange) {
                            importFromHealth()
                        }
                        quickActionPill(title: "Export Report", icon: "doc.richtext", tint: .purple) {
                            exportPDF()
                        }
                        quickActionPill(title: "Export Data", icon: "externaldrive.fill", tint: .blue) {
                            exportBackup()
                        }
                        quickActionPill(title: "Restore", icon: "arrow.down.doc", tint: .teal) {
                            showImporter = true
                        }
                        quickActionPill(title: "Clear All", icon: "trash.fill", tint: .red) {
                            showConfirmClear = true
                        }
                        #if DEBUG
                        quickActionPill(title: "Export 10", icon: "arrow.up.doc.fill", tint: .gray) {
                            showConfirmExportRecent = true
                        }
                        quickActionPill(title: "Load Samples", icon: "tray.and.arrow.down", tint: .mint) {
                            loadSamples()
                        }
                        #endif
                    }
                }
            }
        }
    }

    private var preferencesCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 16) {
                Text(String(localized: "Preferences")).appFont(.headline)
                Toggle(String(localized: "Haptics"), isOn: $hapticsEnabled)
                    .onChange(of: hapticsEnabled) { newValue in Haptics.setEnabled(newValue) }
                Divider()
                VStack(alignment: .leading, spacing: 8) {
                    Text(String(localized: "Overdue Grace")).appFont(.subheadline)
                    Picker("Grace", selection: $graceMinutes) {
                        Text("15m").tag(15)
                        Text("30m").tag(30)
                        Text("60m").tag(60)
                    }
                    .pickerStyle(.segmented)
                }
                Divider()
                VStack(alignment: .leading, spacing: 8) {
                    Text(String(localized: "Blood Glucose Unit")).appFont(.subheadline)
                    Picker("Blood Glucose Unit", selection: $glucoseUnitRaw) {
                        Text(GlucoseUnit.mgdL.rawValue).tag(GlucoseUnit.mgdL.rawValue)
                        Text(GlucoseUnit.mmolL.rawValue).tag(GlucoseUnit.mmolL.rawValue)
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: glucoseUnitRaw) { newValue in
                        if let u = GlucoseUnit(rawValue: newValue) { UnitPreferences.setGlucoseUnit(u) }
                    }
                }
                Divider()
                VStack(alignment: .leading, spacing: 8) {
                    Text(String(localized: "Effectiveness Settings")).appFont(.subheadline)
                    Picker("Mode", selection: $effMode) {
                        Text(String(localized: "Conservative")).tag("conservative")
                        Text(String(localized: "Balanced")).tag("balanced")
                        Text(String(localized: "Aggressive")).tag("aggressive")
                    }
                    .pickerStyle(.segmented)
                    Picker("Min Samples", selection: $effMinSamples) {
                        Text("3").tag(3)
                        Text("5").tag(5)
                        Text("7").tag(7)
                    }
                    .pickerStyle(.segmented)
                }
            }
        }
    }

    private var goalsCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                Text(String(localized: "Goals")).appFont(.headline)
                DisclosureGroup(String(localized: "Blood Glucose")) {
                    HStack {
                        Stepper(value: glucoseLowDisplayBinding, in: glucoseLowDisplayRange, step: glucoseDisplayStep) {
                            Text(glucoseLowLabel)
                        }
                        Stepper(value: glucoseHighDisplayBinding, in: glucoseHighDisplayRange, step: glucoseDisplayStep) {
                            Text(glucoseHighLabel)
                        }
                    }
                }
                DisclosureGroup(String(localized: "Heart Rate")) {
                    HStack {
                        Stepper(value: $hrLow, in: 30...100, step: 1) { Text(String(format: String(localized: "Low: %d bpm"), Int(hrLow))) }
                        Stepper(value: $hrHigh, in: 80...180, step: 1) { Text(String(format: String(localized: "High: %d bpm"), Int(hrHigh))) }
                    }
                }
                DisclosureGroup(String(localized: "Blood Pressure")) {
                    HStack {
                        Stepper(value: $bpSysHigh, in: 90...200, step: 1) { Text(String(format: String(localized: "Sys High: %d mmHg"), Int(bpSysHigh))) }
                        Stepper(value: $bpDiaHigh, in: 50...130, step: 1) { Text(String(format: String(localized: "Dia High: %d mmHg"), Int(bpDiaHigh))) }
                    }
                }
            }
        }
    }

    private var dataManagementCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                Text("Data & Backups").appFont(.headline)
                VStack(spacing: 10) {
                    dataActionRow(title: "Export Report", subtitle: "PDF summary", icon: "doc.richtext", tint: .purple, action: exportPDF)
                    dataActionRow(title: "Export Data", subtitle: "Local backup", icon: "externaldrive.fill", tint: .blue, action: exportBackup)
                    dataActionRow(title: "Restore", subtitle: "Import backup", icon: "arrow.down.doc", tint: .teal) { showImporter = true }
                    dataActionRow(title: "Clear All", subtitle: "Remove measurements and meds", icon: "trash.fill", tint: .red) { showConfirmClear = true }
                }
            }
        }
    }

private var knowledgeCard: some View {
    Card {
        VStack(alignment: .leading, spacing: 12) {
            Text(String(localized: "How.It.Works.Title", defaultValue: "How It Works"))
                .appFont(.headline)
            ForEach(knowledgeSections) { section in
                    DisclosureGroup(section.title) {
                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(section.bullets, id: \.self) { bulletText in
                                bullet(bulletText)
                            }
                        }
                        .padding(.top, 4)
                    }
                }
            }
        }
}

private var aboutCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 8) {
                Text("About").appFont(.headline)
                Text("Ccare keeps your data on device and uses Apple Health only with your permission. It is intended for wellness tracking and does not provide medical advice.").appFont(.footnote).foregroundStyle(.secondary)
            }
        }
    }

    private func quickActionPill(title: LocalizedStringKey, icon: String, tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .semibold))
                    .frame(width: 32, height: 32)
                    .background(Circle().fill(tint))
                    .foregroundStyle(.white)
                Text(title).appFont(.subheadline)
                    .foregroundStyle(.primary)
            }
            .padding(.vertical, 10)
            .padding(.horizontal, 14)
            .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Color(.systemBackground)))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(Color.primary.opacity(0.08), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private func dataActionRow(title: LocalizedStringKey, subtitle: LocalizedStringKey, icon: String, tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .semibold))
                    .frame(width: 40, height: 40)
                    .background(Circle().fill(tint.opacity(0.2)))
                    .foregroundStyle(tint)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).appFont(.subheadline)
                    Text(subtitle).appFont(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right").foregroundStyle(.tertiary)
            }
            .padding(.vertical, 6)
        }
        .buttonStyle(.plain)
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
        .appFont(.footnote)
    }
}

private struct KnowledgeSection: Identifiable {
    let id = UUID()
    let title: String
    let bullets: [String]
}

private extension ProfileView {
    var knowledgeSections: [KnowledgeSection] {
        [
            KnowledgeSection(
                title: String(localized: "How.Reminders.Title", defaultValue: "Reminders"),
                bullets: [
                    String(localized: "How.Reminders.1", defaultValue: "Allow notifications so Ccare can deliver time-sensitive alerts for every planned dose. Reminders now renew 14 days ahead."),
                    String(localized: "How.Reminders.2", defaultValue: "Logging taken or skipped clears the badge and suppresses duplicate alerts for the rest of the day."),
                    String(localized: "How.Reminders.3", defaultValue: "Use Preferences to adjust grace minutes and pick the snooze interval that matches your routine." )
                ]
            ),
            KnowledgeSection(
                title: String(localized: "How.Adherence.Title", defaultValue: "Adherence Tracking"),
                bullets: [
                    String(localized: "How.Adherence.1", defaultValue: "Seven-day adherence uses the latest status for every medication-time pair each day."),
                    String(localized: "How.Adherence.2", defaultValue: "Single-dose medications accept unscheduled logs; multi-dose schedules need the matching time stamp."),
                    String(localized: "How.Adherence.3", defaultValue: "Restore or clear data from the Data section—notifications reschedule automatically afterward.")
                ]
            ),
            KnowledgeSection(
                title: String(localized: "How.Trends.Title", defaultValue: "Trend Charts"),
                bullets: [
                    String(localized: "How.Trends.1", defaultValue: "Charts aggregate readings by day and highlight the goal ranges configured in Preferences."),
                    String(localized: "How.Trends.2", defaultValue: "Blood pressure plots median systolic/diastolic values with a shaded band between them."),
                    String(localized: "How.Trends.3", defaultValue: "Switch between 7/30/90-day windows to compare recent changes against longer histories.")
                ]
            ),
            KnowledgeSection(
                title: String(localized: "How.Effectiveness.Title", defaultValue: "Medication Effectiveness"),
                bullets: [
                    String(localized: "How.Effectiveness.1", defaultValue: "Analysis runs on categorized antihypertensive or antidiabetic meds once enough measurements exist."),
                    String(localized: "How.Effectiveness.2", defaultValue: "Per-dose deltas blend with 14-day trends and adherence gates to produce verdict and confidence."),
                    String(localized: "How.Effectiveness.3", defaultValue: "Fine-tune sensitivity and sample minimums under Preferences when clinical guidance differs.")
                ]
            )
        ]
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
