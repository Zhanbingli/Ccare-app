import SwiftUI
import PhotosUI
import UIKit
import UserNotifications

struct MedicationsView: View {
    @EnvironmentObject var store: DataStore
    @State private var showAdd = false
    @State private var editTarget: Medication? = nil
    @State private var showNotificationDeniedAlert = false
    @State private var deniedMedName: String? = nil
    @State private var notificationStatus: UNAuthorizationStatus = .notDetermined
    @State private var searchText: String = ""
    @State private var filter: MedFilter = .all

    var body: some View {
        NavigationStack {
            List {
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
                    Text("No medications added")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(filteredMedications) { med in
                        medicationCard(for: med)
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.clear)
                    }
                }
            }
            .listStyle(.plain)
            .listRowSeparator(.hidden)
            .listSectionSeparator(.hidden)
            .navigationTitle("Medications")
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
}

struct AddMedicationView: View {
    var onSave: (Medication) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var name: String = ""
    @State private var dose: String = ""
    @State private var notes: String = ""
    @State private var times: [Date] = []
    @State private var remindersEnabled: Bool = true
    @State private var category: MedicationCategory = .unspecified
    @State private var customCategoryName: String = ""
    @State private var pickedItem: PhotosPickerItem? = nil
    @State private var pickedImage: UIImage? = nil

    var body: some View {
        NavigationStack {
            Form {
                Section("Basic") {
                    TextField("Name", text: $name)
                    TextField("Dose", text: $dose)
                    TextField("Notes (optional)", text: $notes)
                    Picker("Category", selection: $category) {
                        ForEach(MedicationCategory.allCases) { c in Text(c.displayName).tag(c) }
                    }
                    if category == .custom {
                        TextField("Custom Category", text: $customCategoryName)
                    }
                    HStack {
                        if let img = pickedImage {
                            Image(uiImage: img)
                                .resizable()
                                .scaledToFill()
                                .frame(width: 56, height: 56)
                                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        } else {
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .strokeBorder(.secondary.opacity(0.3))
                                .frame(width: 56, height: 56)
                                .overlay(Image(systemName: "photo").foregroundStyle(.secondary))
                        }
                        PhotosPicker(selection: $pickedItem, matching: .images) {
                            Text("Choose Photo")
                        }
                        .onChange(of: pickedItem) { newItem in
                            Task { if let data = try? await newItem?.loadTransferable(type: Data.self), let ui = UIImage(data: data) { pickedImage = ui } }
                        }
                        if pickedImage != nil {
                            Button(role: .destructive) { pickedImage = nil } label: { Text("Remove") }
                        }
                    }
                }
                Section("Schedule") {
                    if times.isEmpty {
                        Text(NSLocalizedString("Tap Add Time to set a schedule", comment: ""))
                            .appFont(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(times.indices, id: \.self) { idx in
                            DatePicker("Time \(idx+1)", selection: $times[idx], displayedComponents: .hourAndMinute)
                        }
                        .onDelete { idx in times.remove(atOffsets: idx) }
                    }
                    Button { times.append(Date()) } label: { Label("Add Time", systemImage: "plus.circle") }
                    Toggle("Enable Reminder", isOn: $remindersEnabled)
                }
            }
            .navigationTitle("Add Medication")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let comps = times.map { Calendar.current.dateComponents([.hour, .minute], from: $0) }
                        // Prepare image path
                        var imagePath: String? = nil
                        let newID = UUID()
                        if let img = pickedImage, let path = saveMedImage(image: img, id: newID) { imagePath = path }
                        let med = Medication(
                            id: newID,
                            name: name,
                            dose: dose,
                            notes: notes.isEmpty ? nil : notes,
                            timesOfDay: comps,
                            remindersEnabled: remindersEnabled,
                            category: category,
                            customCategoryName: category == .custom ? customCategoryName.trimmingCharacters(in: .whitespacesAndNewlines) : nil,
                            imagePath: imagePath
                        )
                        onSave(med)
                        Haptics.success()
                        dismiss()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}

struct EditMedicationView: View {
    var medication: Medication
    var onSave: (Medication) -> Void
    var onDelete: (() -> Void)? = nil
    @Environment(\.dismiss) private var dismiss

    @State private var name: String = ""
    @State private var dose: String = ""
    @State private var notes: String = ""
    @State private var times: [Date] = []
    @State private var remindersEnabled: Bool = true
    @State private var category: MedicationCategory = .unspecified
    @State private var pickedItem: PhotosPickerItem? = nil
    @State private var pickedImage: UIImage? = nil
    @State private var removePhoto: Bool = false
    @State private var customCategoryName: String = ""

    init(medication: Medication, onSave: @escaping (Medication) -> Void, onDelete: (() -> Void)? = nil) {
        self.medication = medication
        self.onSave = onSave
        self.onDelete = onDelete
        // State will be initialized in .onAppear to avoid SwiftUI init warnings
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Basic") {
                    TextField("Name", text: $name)
                    TextField("Dose", text: $dose)
                    TextField("Notes (optional)", text: $notes)
                    Picker("Category", selection: $category) {
                        ForEach(MedicationCategory.allCases) { c in Text(c.displayName).tag(c) }
                    }
                    if category == .custom {
                        TextField("Custom Category", text: $customCategoryName)
                    }
                    HStack {
                        if let img = pickedImage {
                            Image(uiImage: img)
                                .resizable()
                                .scaledToFill()
                                .frame(width: 56, height: 56)
                                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        } else if !removePhoto, let existing = loadMedImage(path: medication.imagePath) {
                            Image(uiImage: existing)
                                .resizable()
                                .scaledToFill()
                                .frame(width: 56, height: 56)
                                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        } else {
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .strokeBorder(.secondary.opacity(0.3))
                                .frame(width: 56, height: 56)
                                .overlay(Image(systemName: "photo").foregroundStyle(.secondary))
                        }
                        PhotosPicker(selection: $pickedItem, matching: .images) { Text("Choose Photo") }
                            .onChange(of: pickedItem) { newItem in
                                Task { if let data = try? await newItem?.loadTransferable(type: Data.self), let ui = UIImage(data: data) { pickedImage = ui; removePhoto = false } }
                            }
                if pickedImage != nil || (medication.imagePath != nil && !removePhoto) {
                    Button(role: .destructive) { pickedImage = nil; removePhoto = true } label: { Text("Remove") }
                }
            }
        }
                Section("Schedule") {
                    ForEach(times.indices, id: \.self) { idx in
                        DatePicker("Time \(idx+1)", selection: $times[idx], displayedComponents: .hourAndMinute)
                    }
                    .onDelete { idx in times.remove(atOffsets: idx) }
                    Button { times.append(Date()) } label: { Label("Add Time", systemImage: "plus.circle") }
                    Toggle("Enable Reminder", isOn: $remindersEnabled)
                }
            }
            .navigationTitle("Edit Medication")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                name = medication.name
                dose = medication.dose
                notes = medication.notes ?? ""
                let cal = Calendar.current
                times = medication.timesOfDay.compactMap { comps in
                    guard let h = comps.hour, let m = comps.minute else { return nil }
                    return cal.date(bySettingHour: h, minute: m, second: 0, of: Date()) ?? Date()
                }
                if times.isEmpty { times = [Date()] }
                remindersEnabled = medication.remindersEnabled
                category = medication.category ?? .unspecified
                customCategoryName = medication.customCategoryName ?? ""
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let comps = times.map { Calendar.current.dateComponents([.hour, .minute], from: $0) }
                        var updated = medication
                        updated.name = name
                        updated.dose = dose
                        updated.notes = notes.isEmpty ? nil : notes
                        updated.timesOfDay = comps
                        updated.remindersEnabled = remindersEnabled
                        updated.category = category
                        updated.customCategoryName = category == .custom ? customCategoryName.trimmingCharacters(in: .whitespacesAndNewlines) : nil
                        if removePhoto {
                            removeMedImage(path: updated.imagePath)
                            updated.imagePath = nil
                        } else if let img = pickedImage {
                            updated.imagePath = saveMedImage(image: img, id: updated.id)
                        }
                        onSave(updated)
                        Haptics.success()
                        dismiss()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .safeAreaInset(edge: .bottom) {
                if onDelete != nil {
                    Button(role: .destructive) {
                        onDelete?()
                        dismiss()
                    } label: {
                        Label("Delete Medication", systemImage: "trash")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                    .padding()
                }
            }
        }
    }
}

private func effectLabel(for result: MedicationEffectResult) -> String {
    switch result.verdict {
    case .likelyEffective: return NSLocalizedString("Likely effective", comment: "")
    case .unclear: return NSLocalizedString("Unclear", comment: "")
    case .likelyIneffective: return NSLocalizedString("Likely ineffective", comment: "")
    case .notApplicable: return NSLocalizedString("N/A", comment: "")
    }
}

private func effectColor(for result: MedicationEffectResult) -> Color {
    switch result.verdict {
    case .likelyEffective: return .green
    case .unclear: return .secondary
    case .likelyIneffective: return .red
    case .notApplicable: return .secondary
    }
}

#Preview {
    MedicationsView().environmentObject(DataStore())
}

// MARK: - Image helpers
private extension MedicationsView {
    enum MedFilter: String, CaseIterable, Identifiable {
        case all
        case remindersOn
        case remindersOff
        case needsAttention // low confidence or paused reminders

        var id: String { rawValue }
        var displayName: LocalizedStringKey {
            switch self {
            case .all: return LocalizedStringKey("All")
            case .remindersOn: return LocalizedStringKey("Active")
            case .remindersOff: return LocalizedStringKey("Paused")
            case .needsAttention: return LocalizedStringKey("Attention")
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
                case .needsAttention:
                    let eff = store.effectiveness(for: med)
                    return !med.remindersEnabled || eff.confidence < 40 || eff.verdict == .likelyIneffective
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
        let attention = store.medications.filter { !$0.remindersEnabled || store.effectiveness(for: $0).confidence < 40 }.count
        return TintedCard(tint: .blue) {
            HStack(alignment: .center, spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(NSLocalizedString("Medication Overview", comment: "")).appFont(.headline)
                    Text(String(format: NSLocalizedString("%lld total", comment: ""), total))
                        .appFont(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                VStack(alignment: .leading, spacing: 4) {
                    summaryBadge(title: "Active", value: active, icon: "bell.fill", tint: .white.opacity(0.95))
                    summaryBadge(title: "Paused", value: paused, icon: "bell.slash", tint: .white.opacity(0.85))
                    summaryBadge(title: "Attention", value: attention, icon: "exclamationmark.triangle.fill", tint: .yellow.opacity(0.9))
                }
            }
        }
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

    private func chipButton(for option: MedFilter) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.18)) { filter = option }
        } label: {
            HStack(spacing: 6) {
                Text(option.displayName)
                countChip(for: option)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(
                Capsule().fill(filter == option ? Color.accentColor.opacity(0.2) : Color(.systemBackground))
            )
            .overlay(
                Capsule().stroke(filter == option ? Color.accentColor : Color.primary.opacity(0.1), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private func countText(for filter: MedFilter) -> Int {
        switch filter {
        case .all:
            return store.medications.count
        case .remindersOn:
            return store.medications.filter { $0.remindersEnabled }.count
        case .remindersOff:
            return store.medications.filter { !$0.remindersEnabled }.count
        case .needsAttention:
            return store.medications.filter { !$0.remindersEnabled || store.effectiveness(for: $0).confidence < 40 }.count
        }
    }

    private func countChip(for filter: MedFilter) -> some View {
        Text("\(countText(for: filter))")
            .appFont(.caption)
            .foregroundStyle(.primary.opacity(0.6))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Capsule().fill(Color.primary.opacity(0.08)))
    }

    private func reminderCapsule(isOn: Bool) -> some View {
        Capsule()
            .fill(isOn ? Color.green.opacity(0.18) : Color.orange.opacity(0.18))
            .frame(width: 72, height: 24)
            .overlay(
                Text(isOn ? String(localized: "Active") : String(localized: "Paused"))
                    .appFont(.caption)
                    .foregroundStyle(isOn ? Color.green : Color.orange)
            )
    }

    @ViewBuilder
    private func medicationCard(for med: Medication) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                medicationThumbnail(for: med)
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(med.name)
                            .appFont(.headline)
                        Spacer(minLength: 8)
                        reminderCapsule(isOn: med.remindersEnabled)
                    }
                    Text(med.dose)
                        .appFont(.subheadline)
                        .foregroundStyle(.secondary)
                    if let notes = med.notes, !notes.isEmpty {
                        Text(notes)
                            .appFont(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                reminderToggle(for: med)
            }
            timesRow(for: med)
            summaryRow(for: med)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(.secondarySystemBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.primary.opacity(0.05), lineWidth: 1)
        )
        .contentShape(Rectangle())
        .onTapGesture { editTarget = med }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private func medicationThumbnail(for med: Medication) -> some View {
        if let path = med.imagePath, let ui = loadMedImage(path: path) {
            Image(uiImage: ui)
                .resizable()
                .scaledToFill()
                .frame(width: 52, height: 52)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        } else {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.accentColor.opacity(0.12))
                .frame(width: 52, height: 52)
                .overlay(
                    Image(systemName: "pills.fill")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(Color.accentColor)
                )
        }
    }

    @ViewBuilder
    private func timesRow(for med: Medication) -> some View {
        let times = med.timesOfDay.compactMap { comps -> String? in
            guard let h = comps.hour, let m = comps.minute else { return nil }
            return String(format: "%02d:%02d", h, m)
        }
        if !times.isEmpty {
            HStack(alignment: .center, spacing: 8) {
                Image(systemName: "clock")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                ForEach(times, id: \.self) { time in
                    Text(time)
                        .appFont(.caption)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(Color.primary.opacity(0.06)))
                        .foregroundStyle(.primary)
                }
                Spacer(minLength: 0)
            }
        }
    }

    @ViewBuilder
    private func summaryRow(for med: Medication) -> some View {
        let latest = latestTodayAction(for: med)
        let hasEffect = med.category != nil && med.category != .unspecified
        if latest != nil || hasEffect {
            HStack(alignment: .bottom, spacing: 12) {
                if let (status, date) = latest {
                    statusBadge(status: status, date: date)
                }
                Spacer()
                if hasEffect {
                    effectivenessRow(for: med)
                }
            }
        }
    }

    private func reminderToggle(for med: Medication) -> some View {
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
                                var reverted = med
                                reverted.remindersEnabled = false
                                store.updateMedication(reverted)
                                refreshNotificationStatus()
                                return
                            }
                            var updated = med
                            updated.remindersEnabled = true
                            store.updateMedication(updated)
                            NotificationManager.shared.schedule(for: updated)
                            NotificationManager.shared.updateBadge(store: store)
                            Haptics.impact(.light)
                            refreshNotificationStatus()
                        }
                    } else {
                        await MainActor.run {
                            var updated = med
                            updated.remindersEnabled = false
                            store.updateMedication(updated)
                            NotificationManager.shared.cancelAll(for: updated)
                            NotificationManager.shared.updateBadge(store: store)
                            Haptics.impact(.light)
                            refreshNotificationStatus()
                        }
                    }
                }
            }
        )) {
            Text("Remind")
        }
        .labelsHidden()
    }

    private func effectivenessRow(for med: Medication) -> some View {
        Group {
            if let category = med.category, category != .unspecified {
                let result = store.effectiveness(for: med)
                VStack(alignment: .trailing, spacing: 6) {
                    Text(med.displayCategoryName ?? category.displayName)
                        .appFont(.caption)
                        .foregroundStyle(.secondary)
                    HStack(spacing: 6) {
                        Text(effectLabel(for: result))
                            .appFont(.footnote)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(effectColor(for: result).opacity(0.15)))
                            .foregroundStyle(effectColor(for: result))
                        if result.confidence > 0 {
                            HStack(spacing: 4) {
                                Image(systemName: "shield.fill")
                                    .font(.system(size: 11, weight: .semibold))
                                Text("\(result.confidence)%")
                                    .appFont(.caption)
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.primary.opacity(0.06)))
                            .foregroundStyle(.secondary)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
    }

    private func statusBadge(status: IntakeStatus, date: Date) -> some View {
        HStack(spacing: 8) {
            Image(systemName: latestStatusIcon(status))
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(statusTint(for: status))
            VStack(alignment: .leading, spacing: 2) {
                Text(statusPrefix(for: status))
                    .appFont(.footnote)
                    .foregroundStyle(.primary)
                Text(date, style: .relative)
                    .appFont(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(statusTint(for: status).opacity(0.12))
        )
    }

    private func latestStatusIcon(_ status: IntakeStatus) -> String {
        switch status {
        case .taken: return "checkmark.circle.fill"
        case .skipped: return "xmark.circle.fill"
        case .snoozed: return "zzz"
        }
    }

    private func statusTint(for status: IntakeStatus) -> Color {
        switch status {
        case .taken: return .green
        case .skipped: return .orange
        case .snoozed: return .secondary
        }
    }

    private func statusPrefix(for status: IntakeStatus) -> LocalizedStringKey {
        switch status {
        case .taken: return "Taken"
        case .skipped: return "Skipped"
        case .snoozed: return "Snoozed"
        }
    }

    private func summaryBadge(title: String, value: Int, icon: String, tint: Color) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(tint)
            Text("\(title): \(value)")
                .appFont(.footnote)
                .foregroundStyle(.white.opacity(0.9))
        }
        .padding(.vertical, 2)
    }

    private func latestTodayAction(for med: Medication) -> (IntakeStatus, Date)? {
        let cal = Calendar.current
        let start = cal.startOfDay(for: Date())
        let end = cal.date(byAdding: .day, value: 1, to: start)!
        let logs = store.intakeLogs
            .filter { $0.medicationID == med.id && $0.date >= start && $0.date < end }
            .sorted { $0.date > $1.date }
        guard let last = logs.first else { return nil }
        return (last.status, last.date)
    }
}

private func medImagesDir() -> URL {
    let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
    let dir = docs.appendingPathComponent("med_images", conformingTo: .directory)
    if !FileManager.default.fileExists(atPath: dir.path) {
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }
    // Exclude directory from iCloud backups
    try? (dir as NSURL).setResourceValue(true, forKey: .isExcludedFromBackupKey)
    return dir
}

private func saveMedImage(image: UIImage, id: UUID) -> String? {
    let url = medImagesDir().appendingPathComponent("\(id.uuidString).jpg")
    guard let data = image.jpegData(compressionQuality: 0.9) else { return nil }
    do {
        try data.write(to: url, options: [.atomic, .completeFileProtection])
        try? (url as NSURL).setResourceValue(true, forKey: .isExcludedFromBackupKey)
        return "med_images/\(id.uuidString).jpg"
    } catch { return nil }
}

private func loadMedImage(path: String?) -> UIImage? {
    guard let path = path else { return nil }
    let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
    let url = docs.appendingPathComponent(path)
    return UIImage(contentsOfFile: url.path)
}

private func removeMedImage(path: String?) {
    guard let path = path else { return }
    let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
    let url = docs.appendingPathComponent(path)
    try? FileManager.default.removeItem(at: url)
}

private extension MedicationsView {
    func refreshNotificationStatus() {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            DispatchQueue.main.async {
                self.notificationStatus = settings.authorizationStatus
            }
        }
    }

    func delete(at offsets: IndexSet) {
        let ids = offsets.map { filteredMedications[$0].id }
        let items = store.medications.filter { ids.contains($0.id) }
        items.forEach {
            NotificationManager.shared.cancelAll(for: $0)
            removeMedImage(path: $0.imagePath)
        }
        let toRemove = IndexSet(store.medications.enumerated().compactMap { ids.contains($0.element.id) ? $0.offset : nil })
        store.removeMedication(at: toRemove)
    }
}
