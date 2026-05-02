import SwiftUI
import PhotosUI
import UIKit
import UserNotifications
import Charts

struct MedicationsView: View {
    @EnvironmentObject var store: DataStore
    @Binding var deepLinkMedicationID: UUID?
    @State private var scrollProxy: ScrollViewProxy?
    @State private var showAdd = false
    @State private var detailTarget: Medication? = nil
    @State private var editTarget: Medication? = nil
    @State private var showNotificationDeniedAlert = false
    @State private var deniedMedName: String? = nil
    @State private var notificationStatus: UNAuthorizationStatus = .notDetermined
    @State private var searchText: String = ""
    @State private var scrollToMedicationID: UUID? = nil

    init(deepLinkMedicationID: Binding<UUID?> = .constant(nil)) {
        self._deepLinkMedicationID = deepLinkMedicationID
    }

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                List {
                    if notificationStatus == .denied {
                        Section {
                            warningRow
                        }
                    }

                    if let visit = recentPostVisitMedicationReview {
                        Section {
                            postVisitMedicationReviewRow(for: visit)
                        } footer: {
                            Text(NSLocalizedString("Edit, pause, or add medications here. These records drive daily reminders and the next visit summary.", comment: "Post visit medication review footer"))
                        }
                    }

                    if store.medications.isEmpty {
                        Section {
                            EmptyStateView(
                                systemImage: "pills.circle.fill",
                                title: NSLocalizedString("No medications added", comment: ""),
                                subtitle: NSLocalizedString("Add your first medication to build your daily schedule.", comment: ""),
                                actionTitle: NSLocalizedString("Add Medication", comment: ""),
                                action: { showAdd = true }
                            )
                        }
                    } else if filteredMedications.isEmpty {
                        Section {
                            Text(NSLocalizedString("No medications match your search.", comment: ""))
                                .appFont(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        if !setupMedications.isEmpty {
                            Section(NSLocalizedString("Needs Setup", comment: "")) {
                                ForEach(setupMedications) { med in
                                    medicationManagementRow(for: med)
                                        .id(med.id)
                                }
                            }
                        }

                        if !activeScheduledMedications.isEmpty {
                            Section(NSLocalizedString("Active Medications", comment: "")) {
                                ForEach(activeScheduledMedications) { med in
                                    medicationManagementRow(for: med)
                                        .id(med.id)
                                }
                            }
                        }

                        if !asNeededMedications.isEmpty {
                            Section(NSLocalizedString("As Needed", comment: "")) {
                                ForEach(asNeededMedications) { med in
                                    medicationManagementRow(for: med)
                                        .id(med.id)
                                }
                            }
                        }

                        if !pausedMedications.isEmpty {
                            Section(NSLocalizedString("Paused", comment: "")) {
                                ForEach(pausedMedications) { med in
                                    medicationManagementRow(for: med)
                                        .id(med.id)
                                }
                            }
                        }

                    }
                }
                .listStyle(.insetGrouped)
                .scrollContentBackground(.hidden)
                .background(AppColor.background)
                .onAppear { scrollProxy = proxy }
                .onChange(of: store.medications.count) { _ in scrollProxy = proxy }
            }
            .navigationTitle(NSLocalizedString("Medications", comment: ""))
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    if !store.medications.isEmpty {
                        Button { showAdd = true } label: { Image(systemName: "plus") }
                            .accessibilityLabel(NSLocalizedString("Add Medication", comment: ""))
                    }
                }
            }
            .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always), prompt: NSLocalizedString("Search medications", comment: ""))
            .sheet(isPresented: $showAdd) {
                MedicationFormView(editing: nil, onSave: { med in
                    let result = store.addMedication(med)
                    if result == nil {
                        store.syncNotifications()
                        refreshNotificationStatus()
                    }
                    return result
                })
            }
            .sheet(item: $detailTarget) { med in
                MedicationDetailView(medication: med) { selected in
                    detailTarget = nil
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                        editTarget = selected
                    }
                }
                .environmentObject(store)
            }
            .sheet(item: $editTarget) { med in
                MedicationFormView(editing: med, onSave: { updated in
                    let result = store.updateMedication(updated)
                    if result == nil {
                        store.syncNotifications()
                        refreshNotificationStatus()
                    }
                    return result
                }, onDelete: {
                    if let idx = store.medications.firstIndex(where: { $0.id == med.id }) {
                        NotificationManager.shared.cancelAll(for: med)
                        deleteMedicationImage(path: med.imagePath)
                        store.removeMedication(at: IndexSet(integer: idx))
                        store.syncNotifications()
                        refreshNotificationStatus()
                    }
                })
            }
            .onAppear(perform: refreshNotificationStatus)
            .onChange(of: store.medications.count) { _ in refreshNotificationStatus() }
            .onChange(of: scrollToMedicationID) { target in
                if let id = target {
                    withAnimation {
                        scrollProxy?.scrollTo(id, anchor: .top)
                    }
                    scrollToMedicationID = nil
                }
            }
            .onChange(of: deepLinkMedicationID) { target in
                if let id = target {
                    scrollToMedicationID = id
                    if let med = store.medications.first(where: { $0.id == id }) {
                        detailTarget = med
                    }
                    deepLinkMedicationID = nil
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
}

// Old AddMedicationView and EditMedicationView removed — replaced by MedicationFormView.swift

#Preview {
    MedicationsView().environmentObject(DataStore())
}

// MARK: - Image helpers
private extension MedicationsView {
    var filteredMedications: [Medication] {
        store.medications.filter { med in
            let matchesSearch: Bool
            if searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                matchesSearch = true
            } else {
                let query = searchText.lowercased()
                matchesSearch = med.name.lowercased().contains(query) || med.dose.lowercased().contains(query)
            }
            return matchesSearch
        }
    }

    var setupMedications: [Medication] {
        filteredMedications.filter { $0.isAsNeeded != true && $0.timesOfDay.isEmpty }
    }

    var activeScheduledMedications: [Medication] {
        filteredMedications.filter {
            $0.isAsNeeded != true && !$0.timesOfDay.isEmpty && $0.remindersEnabled
        }
    }

    var asNeededMedications: [Medication] {
        filteredMedications.filter { $0.isAsNeeded == true }
    }

    var pausedMedications: [Medication] {
        filteredMedications.filter {
            $0.isAsNeeded != true && !$0.timesOfDay.isEmpty && !$0.remindersEnabled
        }
    }

    var recentPostVisitMedicationReview: DoctorVisit? {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        return store.completedDoctorVisits.first { visit in
            let completedDay = calendar.startOfDay(for: visit.completedDate ?? visit.scheduledDate)
            let days = calendar.dateComponents([.day], from: completedDay, to: today).day ?? Int.max
            return days >= 0 && days <= 14 && (visit.needsPostVisitCapture || visit.hasMedicationPlan)
        }
    }

    var warningRow: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "bell.slash.fill")
                .font(.system(size: 14, weight: .regular))
                .foregroundStyle(AppColor.warning)
            VStack(alignment: .leading, spacing: 6) {
                Text(NSLocalizedString("Notifications Disabled", comment: ""))
                    .appFont(.subheadline)
                    .foregroundStyle(AppColor.textPrimary)
                Text(NSLocalizedString("Turn notifications on in Settings to receive medication reminders.", comment: ""))
                    .appFont(.caption)
                    .foregroundStyle(AppColor.textSecondary)
            }
        }
    }

    private func postVisitMedicationReviewRow(for visit: DoctorVisit) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(NSLocalizedString("After Last Visit", comment: "Post visit medication review title"), systemImage: "stethoscope")
                .appFont(.subheadline)
                .fontWeight(.semibold)
                .foregroundStyle(AppColor.textPrimary)

            Text(postVisitMedicationReviewText(for: visit))
                .appFont(.caption)
                .foregroundStyle(AppColor.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 4)
    }

    private func postVisitMedicationReviewText(for visit: DoctorVisit) -> String {
        if let summary = visit.medicationChangesSummary?.trimmingCharacters(in: .whitespacesAndNewlines), !summary.isEmpty {
            return String(format: NSLocalizedString("Medication plan from the visit: %@", comment: "Post visit medication review summary"), summary)
        }
        return NSLocalizedString("Check whether the doctor added, stopped, or changed any medication at the last visit.", comment: "Post visit medication review prompt")
    }

    /// Single condensed row per medication. The surrounding section header
    /// already conveys state (Active / Paused / As Needed / Needs Setup), so
    /// the row stays to two lines: name + one concise context line. A supply
    /// warning badge surfaces on the right only when it's actionable.
    @ViewBuilder
    private func medicationManagementRow(for med: Medication) -> some View {
        Button {
            Haptics.impact(.light)
            detailTarget = med
        } label: {
            HStack(alignment: .center, spacing: 12) {
                medicationThumbnail(for: med)
                VStack(alignment: .leading, spacing: 3) {
                    Text(med.name)
                        .appFont(.subheadline)
                        .foregroundStyle(AppColor.textPrimary)
                    Text(rowSubtitle(for: med))
                        .appFont(.caption)
                        .foregroundStyle(AppColor.textSecondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                Spacer(minLength: 8)
                supplyBadge(for: med)
            }
            .padding(.vertical, 4)
        }
        .buttonStyle(EditorialRowButtonStyle())
    }

    @ViewBuilder
    private func supplyBadge(for med: Medication) -> some View {
        if med.isLowSupply, let days = med.daysOfSupplyRemaining {
            AppBadge(
                text: String(format: NSLocalizedString("%lld days left", comment: "supply badge"), days),
                tint: AppColor.warning
            )
        } else if med.isLowSupply {
            AppBadge(text: NSLocalizedString("Low supply", comment: ""), tint: AppColor.warning)
        }
    }

    private func rowSubtitle(for med: Medication) -> String {
        if med.isAsNeeded == true {
            return med.dose
        }
        if med.timesOfDay.isEmpty {
            return String(format: NSLocalizedString("%@ · Tap to set times", comment: ""), med.dose)
        }
        if !med.remindersEnabled {
            return "\(med.dose) · \(timesJoined(for: med))"
        }
        return String(format: NSLocalizedString("%@ · Next %@", comment: ""), med.dose, nextDoseText(for: med))
    }

    private func timesJoined(for med: Medication) -> String {
        let formatter: DateFormatter = {
            let f = DateFormatter()
            f.timeStyle = .short
            return f
        }()
        let cal = Calendar.current
        let times = med.timesOfDay.compactMap { comps -> String? in
            guard let h = comps.hour, let m = comps.minute,
                  let date = cal.date(bySettingHour: h, minute: m, second: 0, of: Date()) else { return nil }
            return formatter.string(from: date)
        }
        return times.joined(separator: ", ")
    }

    private func nextDoseText(for med: Medication) -> String {
        let calendar = Calendar.current
        let now = Date()
        let sorted = med.timesOfDay.sorted { ($0.hour ?? 0, $0.minute ?? 0) < ($1.hour ?? 0, $1.minute ?? 0) }
        for offset in 0..<2 {
            guard let day = calendar.date(byAdding: .day, value: offset, to: calendar.startOfDay(for: now)) else { continue }
            for comps in sorted {
                guard let hour = comps.hour,
                      let minute = comps.minute,
                      let scheduled = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day),
                      med.isDoseActive(on: scheduled),
                      scheduled >= now else { continue }
                return scheduled.formatted(offset == 0 ? .dateTime.hour().minute() : .dateTime.weekday(.abbreviated).hour().minute())
            }
        }
        return NSLocalizedString("Not scheduled", comment: "")
    }

    @ViewBuilder
    private func medicationThumbnail(for med: Medication) -> some View {
        if let path = med.imagePath, let ui = loadMedicationImage(path: path) {
            Image(uiImage: ui)
                .resizable()
                .scaledToFill()
                .frame(width: 40, height: 40)
                .clipShape(RoundedRectangle(cornerRadius: AppRadius.small, style: .continuous))
                .accessibilityLabel(String(format: NSLocalizedString("%@ photo", comment: "Medication thumbnail accessibility"), med.name))
        } else {
            RoundedRectangle(cornerRadius: AppRadius.small, style: .continuous)
                .fill(AppColor.surface)
                .frame(width: 40, height: 40)
                .overlay(
                    RoundedRectangle(cornerRadius: AppRadius.small, style: .continuous)
                        .stroke(AppColor.divider, lineWidth: 1)
                )
                .overlay(
                    Image(systemName: "pills")
                        .font(.system(size: 16, weight: .regular))
                        .foregroundStyle(AppColor.textSecondary)
                )
                .accessibilityHidden(true)
        }
    }

}

private extension MedicationsView {
    func refreshNotificationStatus() {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            DispatchQueue.main.async {
                self.notificationStatus = settings.authorizationStatus
            }
        }
    }
}
