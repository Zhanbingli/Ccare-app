import SwiftUI
import UserNotifications

struct HealthView: View {
    @EnvironmentObject var store: DataStore
    @State private var scrollProxy: ScrollViewProxy?
    @State private var showAdd = false
    @State private var editTarget: Medication? = nil
    @State private var showNotificationDeniedAlert = false
    @State private var deniedMedName: String? = nil
    @State private var notificationStatus: UNAuthorizationStatus = .notDetermined
    @State private var searchText: String = ""
    @State private var filter: MedFilter = .all
    @State private var scrollToMedicationID: UUID? = nil
    @AppStorage("units.glucose") private var glucoseUnitRaw: String = GlucoseUnit.mgdL.rawValue

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                List {
                    medicationSections
                    quickLinksSection
                    insightsSection
                    measurementsSection
                }
                .listStyle(.insetGrouped)
                .onAppear { scrollProxy = proxy }
                .onChange(of: store.medications.count) { _ in scrollProxy = proxy }
            }
            .navigationTitle(NSLocalizedString("Health", comment: ""))
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showAdd = true } label: { Image(systemName: "plus") }
                }
            }
            .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always), prompt: NSLocalizedString("Search medications", comment: ""))
            .sheet(isPresented: $showAdd) {
                AddMedicationView { med in
                    store.addMedication(med)
                    if med.remindersEnabled {
                        NotificationManager.shared.schedule(for: med)
                        NotificationManager.shared.updateBadge(store: store)
                    }
                    refreshNotificationStatus()
                }
            }
            .sheet(item: $editTarget) { med in
                EditMedicationView(medication: med, onSave: { updated in
                    store.updateMedication(updated)
                    if updated.remindersEnabled {
                        NotificationManager.shared.schedule(for: updated)
                        NotificationManager.shared.updateBadge(store: store)
                    } else {
                        NotificationManager.shared.cancelAll(for: updated)
                        NotificationManager.shared.updateBadge(store: store)
                    }
                    refreshNotificationStatus()
                }, onDelete: {
                    if let idx = store.medications.firstIndex(where: { $0.id == med.id }) {
                        NotificationManager.shared.cancelAll(for: med)
                        removeMedImage(path: med.imagePath)
                        store.removeMedication(at: IndexSet(integer: idx))
                        NotificationManager.shared.updateBadge(store: store)
                        refreshNotificationStatus()
                    }
                })
            }
            .onAppear(perform: refreshNotificationStatus)
            .onChange(of: store.medications.count) { _ in refreshNotificationStatus() }
            .onChange(of: scrollToMedicationID) { target in
                if let id = target {
                    withAnimation { scrollProxy?.scrollTo(id, anchor: .top) }
                    scrollToMedicationID = nil
                }
            }
            .alert(isPresented: $showNotificationDeniedAlert) {
                let message = deniedMedName.map { String(format: NSLocalizedString("Enable notifications in Settings to get reminders for %@.", comment: ""), $0) } ?? NSLocalizedString("Enable notifications in Settings to get reminders.", comment: "")
                return Alert(
                    title: Text(NSLocalizedString("Notifications Disabled", comment: "")),
                    message: Text(message),
                    primaryButton: .default(Text(NSLocalizedString("Open Settings", comment: ""))) {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                    },
                    secondaryButton: .cancel()
                )
            }
        }
    }


    // MARK: - Extracted Sections

    @ViewBuilder
    private var medicationSections: some View {
        Section {
            VStack(alignment: .leading, spacing: 12) {
                summaryCard
                filterChips
            }
        }
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)

        if notificationStatus == .denied {
            Section {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "bell.slash.fill").foregroundStyle(.orange)
                    VStack(alignment: .leading, spacing: 6) {
                        Text(NSLocalizedString("Notifications Disabled", comment: "")).appFont(.subheadline)
                        Text(NSLocalizedString("Turn notifications on in Settings to receive medication reminders.", comment: "")).appFont(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            .listRowSeparator(.hidden)
        }

        if filteredMedications.isEmpty {
            Text(NSLocalizedString("No medications added", comment: ""))
                .foregroundStyle(.secondary)
        } else {
            ForEach(filteredMedications) { med in
                medicationCard(for: med)
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                    .id(med.id)
            }
        }
    }

    @ViewBuilder
    private var quickLinksSection: some View {
        Section {
            if store.medications.contains(where: { $0.remindersEnabled }) {
                NavigationLink {
                    AdherenceCalendarView()
                } label: {
                    Label(NSLocalizedString("Adherence Calendar", comment: ""), systemImage: "calendar")
                        .appFont(.subheadline)
                }
            }
            NavigationLink {
                EnhancedTrendsView()
                    .environmentObject(store)
            } label: {
                Label(NSLocalizedString("View Trends", comment: ""), systemImage: "chart.line.uptrend.xyaxis")
                    .appFont(.subheadline)
            }
        }
        .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
    }

    @ViewBuilder
    private var insightsSection: some View {
        let insights = MedicationInsightsEngine.generateInsights(
            medications: store.medications,
            intakeLogs: store.intakeLogs,
            measurements: store.measurements,
            store: store
        )
        if !insights.isEmpty {
            Section {
                ForEach(insights.prefix(2)) { insight in
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: insight.type.icon)
                            .font(.system(size: 16))
                            .foregroundStyle(insight.type.color)
                            .frame(width: 22)
                        Text(insight.message)
                            .appFont(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            } header: {
                Text(NSLocalizedString("Smart Insights", comment: ""))
            }
            .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
        }
    }

    @ViewBuilder
    private var measurementsSection: some View {
        if !store.measurements.isEmpty {
            Section {
                if let latest = store.measurements.first {
                    latestMeasurementRow(latest)
                }
            } header: {
                Text(NSLocalizedString("Measurements", comment: ""))
            }
            .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
        }
    }
}

// MARK: - Medication List Helpers

private extension HealthView {
    enum MedFilter: String, CaseIterable, Identifiable {
        case all, remindersOn, remindersOff
        var id: String { rawValue }
        var displayName: LocalizedStringKey {
            switch self {
            case .all: return LocalizedStringKey("All")
            case .remindersOn: return LocalizedStringKey("Active")
            case .remindersOff: return LocalizedStringKey("Paused")
            }
        }
    }

    var filteredMedications: [Medication] {
        store.medications.filter { med in
            let matchesFilter: Bool = {
                switch filter {
                case .all: return true
                case .remindersOn: return med.remindersEnabled
                case .remindersOff: return !med.remindersEnabled
                }
            }()
            let matchesSearch: Bool
            if searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                matchesSearch = true
            } else {
                let query = searchText.lowercased()
                matchesSearch = med.name.lowercased().contains(query) || med.dose.lowercased().contains(query)
            }
            return matchesFilter && matchesSearch
        }
    }

    var summaryCard: some View {
        let total = store.medications.count
        let active = store.medications.filter { $0.remindersEnabled }.count
        let paused = max(total - active, 0)
        return HStack(spacing: 0) {
            summaryStat(value: "\(total)", label: NSLocalizedString("Medications", comment: ""))
            summaryDivider
            summaryStat(value: "\(active)", label: NSLocalizedString("Active", comment: ""), color: .green)
            summaryDivider
            summaryStat(value: "\(paused)", label: NSLocalizedString("Paused", comment: ""), color: paused > 0 ? .orange : .secondary)
        }
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(.secondarySystemBackground))
        )
    }

    func summaryStat(value: String, label: String, color: Color = .primary) -> some View {
        VStack(spacing: 4) {
            Text(value).appFont(.headline).foregroundStyle(color)
            Text(label).appFont(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    var summaryDivider: some View {
        Rectangle().fill(Color.primary.opacity(0.08)).frame(width: 1, height: 32)
    }

    var filterChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(spacing: 10) {
                ForEach(MedFilter.allCases) { chipButton(for: $0) }
            }
            .padding(.horizontal, 4)
        }
        .accessibilityElement(children: .combine)
    }

    func chipButton(for option: MedFilter) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.18)) { filter = option }
        } label: {
            HStack(spacing: 6) {
                Text(option.displayName)
                countChip(for: option)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(Capsule().fill(filter == option ? Color.accentColor.opacity(0.2) : Color(.systemBackground)))
            .overlay(Capsule().stroke(filter == option ? Color.accentColor : Color.primary.opacity(0.1), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    func countText(for filter: MedFilter) -> Int {
        switch filter {
        case .all: return store.medications.count
        case .remindersOn: return store.medications.filter { $0.remindersEnabled }.count
        case .remindersOff: return store.medications.filter { !$0.remindersEnabled }.count
        }
    }

    func countChip(for filter: MedFilter) -> some View {
        Text("\(countText(for: filter))")
            .appFont(.caption)
            .foregroundStyle(.primary.opacity(0.6))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Capsule().fill(Color.primary.opacity(0.08)))
    }

    @ViewBuilder
    func medicationCard(for med: Medication) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 10) {
                medicationThumbnail(for: med)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(med.name).appFont(.headline).lineLimit(1)
                        if !med.remindersEnabled {
                            Text(NSLocalizedString("Paused", comment: ""))
                                .appFont(.caption).foregroundStyle(.orange)
                                .padding(.horizontal, 6).padding(.vertical, 2)
                                .background(Capsule().fill(Color.orange.opacity(0.12)))
                        }
                        if med.isAsNeeded == true {
                            Text(NSLocalizedString("PRN", comment: ""))
                                .appFont(.caption).foregroundStyle(.blue)
                                .padding(.horizontal, 6).padding(.vertical, 2)
                                .background(Capsule().fill(Color.blue.opacity(0.12)))
                        }
                    }
                    HStack(spacing: 4) {
                        Text(med.dose).appFont(.caption).foregroundStyle(.secondary)
                        if !med.timesOfDay.isEmpty {
                            Text("·").foregroundStyle(.secondary)
                            timesText(for: med)
                        }
                    }
                }
                Spacer(minLength: 4)
                reminderToggle(for: med)
            }

            HStack(spacing: 8) {
                if let remaining = med.pillsRemaining {
                    compactSupplyLabel(remaining: remaining, med: med)
                }
                if let (status, date) = latestTodayAction(for: med) {
                    inlineStatusLabel(status: status, date: date)
                }
                Spacer(minLength: 0)
                if med.remindersEnabled {
                    compactQuickTakeButton(for: med)
                }
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(.secondarySystemBackground))
        )
        .contentShape(Rectangle())
        .onTapGesture { editTarget = med }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    func compactSupplyLabel(remaining: Int, med: Medication) -> some View {
        let isLow = med.isLowSupply
        HStack(spacing: 4) {
            if isLow {
                Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 13)).foregroundStyle(.red)
            }
            if let days = med.daysOfSupplyRemaining, days > 0 {
                Text(String(format: NSLocalizedString("%lld pills · %lld d", comment: ""), remaining, days))
                    .appFont(.caption).foregroundStyle(isLow ? .red : .secondary)
            } else {
                Text(String(format: NSLocalizedString("%lld pills", comment: ""), remaining))
                    .appFont(.caption).foregroundStyle(isLow ? .red : .secondary)
            }
        }
    }

    func inlineStatusLabel(status: IntakeStatus, date: Date) -> some View {
        HStack(spacing: 5) {
            Image(systemName: latestStatusIcon(status)).font(.system(size: 14, weight: .semibold)).foregroundStyle(statusTint(for: status))
            Text(statusPrefix(for: status)).appFont(.caption).foregroundStyle(statusTint(for: status))
        }
    }

    @ViewBuilder
    func compactQuickTakeButton(for med: Medication) -> some View {
        if let dose = nextUntakenDose(for: med) {
            Button {
                let dupCheck = MedicationRules.checkDuplicateTaken(
                    medicationID: med.id, scheduleTime: dose.comps, intakeLogs: store.intakeLogs
                )
                if case .blocked = dupCheck {
                    Haptics.notification(.warning)
                    return
                }
                store.upsertIntake(medicationID: med.id, status: .taken, scheduleTime: dose.comps)
                store.decrementPills(for: med.id)
                NotificationManager.shared.suppressToday(for: med.id, timeComponents: dose.comps)
                NotificationManager.shared.cancelTodayInstance(for: med.id, timeComponents: dose.comps)
                NotificationManager.shared.cancelFollowUps(for: med.id, timeComponents: dose.comps)
                NotificationManager.shared.schedule(for: med)
                NotificationManager.shared.updateBadge(store: store)
                Haptics.success()
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "checkmark").font(.system(size: 13, weight: .bold))
                    Text(dose.timeStr).appFont(.caption)
                }
                .padding(.horizontal, 12).padding(.vertical, 8)
            }
            .buttonStyle(.borderedProminent)
            .tint(.green)
            .controlSize(.small)
        }
    }

    func nextUntakenDose(for med: Medication) -> (comps: DateComponents, timeStr: String)? {
        let cal = Calendar.current
        let now = Date()
        let dayStart = cal.startOfDay(for: now)
        guard let dayEnd = cal.date(byAdding: .day, value: 1, to: dayStart) else { return nil }
        let todayLogs = store.intakeLogs.filter { $0.medicationID == med.id && $0.date >= dayStart && $0.date < dayEnd }
        let sorted = med.timesOfDay.sorted { ($0.hour ?? 0) * 60 + ($0.minute ?? 0) < ($1.hour ?? 0) * 60 + ($1.minute ?? 0) }
        for comps in sorted {
            let key = String(format: "%02d:%02d", comps.hour ?? 0, comps.minute ?? 0)
            let taken = todayLogs.contains { $0.scheduleKey == key && $0.status == .taken }
            if !taken {
                let formatter = DateFormatter(); formatter.timeStyle = .short
                let timeStr = cal.date(bySettingHour: comps.hour ?? 0, minute: comps.minute ?? 0, second: 0, of: now)
                    .map { formatter.string(from: $0) } ?? ""
                return (comps, timeStr)
            }
        }
        return nil
    }

    @ViewBuilder
    func medicationThumbnail(for med: Medication) -> some View {
        if let path = med.imagePath, let ui = loadMedImage(path: path) {
            Image(uiImage: ui).resizable().scaledToFill()
                .frame(width: 40, height: 40)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        } else {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.accentColor.opacity(0.10))
                .frame(width: 40, height: 40)
                .overlay(
                    Image(systemName: "pills.fill").font(.system(size: 18, weight: .semibold)).foregroundStyle(Color.accentColor)
                )
        }
    }

    func timesText(for med: Medication) -> some View {
        let formatter: DateFormatter = { let f = DateFormatter(); f.timeStyle = .short; return f }()
        let cal = Calendar.current
        let times = med.timesOfDay.compactMap { comps -> String? in
            guard let h = comps.hour, let m = comps.minute,
                  let date = cal.date(bySettingHour: h, minute: m, second: 0, of: Date()) else { return nil }
            return formatter.string(from: date)
        }
        return Text(times.joined(separator: ", ")).appFont(.caption).foregroundStyle(.secondary).lineLimit(1)
    }

    func reminderToggle(for med: Medication) -> some View {
        Toggle(isOn: Binding(
            get: { med.remindersEnabled },
            set: { newVal in
                Task {
                    if newVal {
                        let granted = await NotificationManager.shared.ensureAuthorization()
                        await MainActor.run {
                            guard granted else {
                                deniedMedName = med.name
                                showNotificationDeniedAlert = true
                                var reverted = med; reverted.remindersEnabled = false
                                store.updateMedication(reverted)
                                refreshNotificationStatus()
                                return
                            }
                            var updated = med; updated.remindersEnabled = true
                            store.updateMedication(updated)
                            NotificationManager.shared.schedule(for: updated)
                            NotificationManager.shared.updateBadge(store: store)
                            Haptics.impact(.light)
                            refreshNotificationStatus()
                        }
                    } else {
                        await MainActor.run {
                            var updated = med; updated.remindersEnabled = false
                            store.updateMedication(updated)
                            NotificationManager.shared.cancelAll(for: updated)
                            NotificationManager.shared.updateBadge(store: store)
                            Haptics.impact(.light)
                            refreshNotificationStatus()
                        }
                    }
                }
            }
        )) { Text(NSLocalizedString("Remind", comment: "")) }
        .labelsHidden()
    }

    func latestStatusIcon(_ status: IntakeStatus) -> String {
        switch status {
        case .taken: return "checkmark.circle.fill"
        case .skipped: return "xmark.circle.fill"
        case .snoozed: return "zzz"
        }
    }

    func statusTint(for status: IntakeStatus) -> Color {
        switch status {
        case .taken: return .green
        case .skipped: return .orange
        case .snoozed: return .blue
        }
    }

    func statusPrefix(for status: IntakeStatus) -> LocalizedStringKey {
        switch status {
        case .taken: return "Taken"
        case .skipped: return "Skipped"
        case .snoozed: return "Snoozed"
        }
    }

    func latestTodayAction(for med: Medication) -> (IntakeStatus, Date)? {
        let cal = Calendar.current
        let start = cal.startOfDay(for: Date())
        let end = cal.date(byAdding: .day, value: 1, to: start)!
        let logs = store.intakeLogs
            .filter { $0.medicationID == med.id && $0.date >= start && $0.date < end }
            .sorted { $0.date > $1.date }
        guard let last = logs.first else { return nil }
        return (last.status, last.date)
    }

    func refreshNotificationStatus() {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            DispatchQueue.main.async { self.notificationStatus = settings.authorizationStatus }
        }
    }
}

// MARK: - Measurement Row

private extension HealthView {
    func latestMeasurementRow(_ m: Measurement) -> some View {
        HStack(spacing: 10) {
            Circle().fill(m.type.tint).frame(width: 8, height: 8)
            Text(m.type.rawValue).appFont(.subheadline)
            Spacer()
            Group {
                if m.type == .bloodPressure, let dia = m.diastolic {
                    Text("\(Int(m.value))/\(Int(dia)) \(m.type.unit)")
                } else if m.type == .bloodGlucose {
                    let v = UnitPreferences.mgdlToPreferred(m.value)
                    let formatted = UnitPreferences.glucoseUnit == .mgdL ? String(format: "%.0f", v) : String(format: "%.1f", v)
                    Text("\(formatted) \(UnitPreferences.glucoseUnit.rawValue)")
                } else {
                    Text("\(String(format: "%.1f", m.value)) \(m.type.unit)")
                }
            }
            .appFont(.subheadline)
            .fontWeight(.medium)

            Text(m.date, style: .relative).appFont(.caption).foregroundStyle(.secondary)
        }
    }
}
