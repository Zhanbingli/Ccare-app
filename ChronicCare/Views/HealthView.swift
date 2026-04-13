import SwiftUI
import UserNotifications

// MARK: - HealthView

struct HealthView: View {
    @EnvironmentObject var store: DataStore
    @Binding var deepLinkMedicationID: UUID?

    @State private var scrollProxy: ScrollViewProxy?
    @State private var showAdd = false
    @State private var showAddMeasurement = false
    @State private var showSettings = false
    @State private var detailTarget: Medication? = nil
    @State private var editTarget: Medication? = nil
    @State private var showNotificationDeniedAlert = false
    @State private var deniedMedName: String? = nil
    @State private var notificationStatus: UNAuthorizationStatus = .notDetermined

    // MARK: Derived counts (used by HealthOverviewCard)

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

    private var courseReminderThresholdDays: Int {
        UserDefaults.standard.object(forKey: "prefs.courseEndThresholdDays") as? Int ?? 3
    }

    private var reviewCount: Int {
        store.medications.filter { $0.isLowSupply || needsCourseAttention($0) }.count
    }

    // MARK: Body

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 18) {
                        if notificationStatus == .denied {
                            notificationWarningCard
                        }

                        HealthOverviewCard(
                            notificationStatus: notificationStatus,
                            scheduledWithoutRemindersCount: scheduledWithoutRemindersCount,
                            untimedScheduledCount: untimedScheduledCount,
                            reviewCount: reviewCount
                        )
                        .environmentObject(store)

                        MedicationLibrarySection(
                            showAdd: $showAdd,
                            detailTarget: $detailTarget,
                            editTarget: $editTarget,
                            onNotificationStatusChanged: refreshNotificationStatus,
                            onShowNotificationDenied: { name in
                                deniedMedName = name
                                showNotificationDeniedAlert = true
                            }
                        )
                        .environmentObject(store)

                        LatestMeasurementCard(
                            measurement: store.measurements.first,
                            onLogMeasurement: { showAddMeasurement = true }
                        )

                        HealthQuickLinksCard()
                            .environmentObject(store)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                    .padding(.bottom, 24)
                }
                .scrollDismissesKeyboard(.interactively)
                .onAppear { scrollProxy = proxy }
                .onChange(of: store.medications.count) { _ in scrollProxy = proxy }
            }
            .navigationTitle(NSLocalizedString("Health", comment: ""))
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Menu {
                        Button {
                            showAddMeasurement = true
                        } label: {
                            Label(NSLocalizedString("Log Measurement", comment: ""), systemImage: "waveform.path.ecg")
                        }

                        Button {
                            showSettings = true
                        } label: {
                            Label(NSLocalizedString("Settings", comment: ""), systemImage: "gearshape")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showAdd = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $showAdd) {
                MedicationFormView(editing: nil, onSave: { med in
                    store.addMedication(med)
                    store.syncNotifications()
                    refreshNotificationStatus()
                })
            }
            .sheet(isPresented: $showAddMeasurement) {
                AddMeasurementView { measurement in
                    store.addMeasurement(measurement)
                    Haptics.success()
                }
                .presentationDetents([.medium, .large])
            }
            .sheet(isPresented: $showSettings) {
                ProfileView()
                    .environmentObject(store)
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
                    store.updateMedication(updated)
                    store.syncNotifications()
                    refreshNotificationStatus()
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
            .onChange(of: deepLinkMedicationID) { target in
                if let id = target {
                    withAnimation { scrollProxy?.scrollTo(id, anchor: .top) }
                    if let med = store.medications.first(where: { $0.id == id }) {
                        detailTarget = med
                    }
                    deepLinkMedicationID = nil
                }
            }
            .alert(isPresented: $showNotificationDeniedAlert) {
                let message = deniedMedName.map {
                    String(format: NSLocalizedString("Enable notifications in Settings to get reminders for %@.", comment: ""), $0)
                } ?? NSLocalizedString("Enable notifications in Settings to get reminders.", comment: "")
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

    // MARK: - Helpers

    private var notificationWarningCard: some View {
        TintedCard(tint: .orange) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "bell.slash.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.orange)
                VStack(alignment: .leading, spacing: 6) {
                    Text(NSLocalizedString("Notifications Disabled", comment: ""))
                        .appFont(.headline)
                    Text(NSLocalizedString("Turn notifications on in Settings to receive medication reminders.", comment: ""))
                        .appFont(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button(NSLocalizedString("Open", comment: "")) {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
    }

    private func needsCourseAttention(_ med: Medication) -> Bool {
        switch med.courseState(thresholdDays: courseReminderThresholdDays) {
        case .endingSoon, .endsToday, .ended:
            return true
        default:
            return false
        }
    }

    private func refreshNotificationStatus() {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            DispatchQueue.main.async { self.notificationStatus = settings.authorizationStatus }
        }
    }
}
