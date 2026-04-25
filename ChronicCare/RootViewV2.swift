import SwiftUI

/// App root: single Home (DashboardView) + a Profile drawer that houses
/// Medications / Emergency / Caregivers / Settings. The weekly reflection
/// card on Home opens the adherence calendar directly — the natural
/// deepening of "how am I doing this week".
struct RootViewV2: View {
    @EnvironmentObject var store: DataStore
    @Environment(\.scenePhase) private var scenePhase
    @State private var showOnboarding = !UserDefaults.standard.bool(forKey: "hasCompletedOnboarding")
    @State private var showProfileDrawer = false
    @State private var showLogSheet = false
    @State private var showAdherenceCalendar = false
    @State private var showInsightsSheet = false
    @State private var showMedicationSheet = false
    @State private var deepLinkMedicationID: UUID? = nil

    var body: some View {
        if showOnboarding {
            OnboardingView {
                UserDefaults.standard.set(true, forKey: "hasCompletedOnboarding")
                showOnboarding = false
            }
            .environmentObject(store)
        } else {
            mainContent
        }
    }

    private var mainContent: some View {
        ZStack {
            AppBackground()
            DashboardView(
                onOpenCalendar: { showAdherenceCalendar = true },
                onLogMeasurement: { showLogSheet = true }
            )
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            homeHeader
        }
        .dynamicTypeSize(.xSmall ... .accessibility5)
        .sheet(isPresented: $showProfileDrawer) {
            ProfileDrawerV2(onLogMeasurement: {
                showProfileDrawer = false
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                    showLogSheet = true
                }
            })
            .environmentObject(store)
        }
        .sheet(isPresented: $showLogSheet) {
            AddMeasurementView { measurement in
                store.addMeasurement(measurement)
                Haptics.success()
            }
            .presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $showAdherenceCalendar) {
            NavigationStack {
                AdherenceCalendarView()
                    .environmentObject(store)
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button(NSLocalizedString("Done", comment: "")) {
                                showAdherenceCalendar = false
                            }
                        }
                }
            }
        }
        .sheet(isPresented: $showInsightsSheet) {
            NavigationStack {
                EnhancedTrendsView()
                    .environmentObject(store)
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button(NSLocalizedString("Done", comment: "")) {
                                showInsightsSheet = false
                            }
                        }
                    }
            }
        }
        .sheet(isPresented: $showMedicationSheet, onDismiss: {
            deepLinkMedicationID = nil
        }) {
            NavigationStack {
                MedicationsView(deepLinkMedicationID: $deepLinkMedicationID)
                    .environmentObject(store)
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button(NSLocalizedString("Done", comment: "")) {
                                showMedicationSheet = false
                            }
                        }
                    }
            }
        }
        .onChange(of: scenePhase) { newPhase in
            guard newPhase == .active else { return }
            let now = Date()
            store.syncNotifications(now: now)
            store.updateWidgetData()
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("openMedicationDetail"))) { notification in
            if let medID = notification.object as? UUID {
                deepLinkMedicationID = medID
                showMedicationSheet = true
            }
        }
        .onOpenURL { url in
            handleDeepLink(url)
        }
    }

    private var homeHeader: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(NSLocalizedString("Today", comment: "Home header eyebrow"))
                    .appFont(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                    .tracking(0.8)
                Text(homeDateText)
                    .appFont(.headline)
                    .fontWeight(.semibold)
                    .foregroundStyle(.primary)
            }

            Spacer()

            profileButton
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 8)
    }

    private var homeDateText: String {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("MMMEd")
        return formatter.string(from: Date())
    }

    private var profileButton: some View {
        circularActionButton(
            systemName: "person.crop.circle",
            accessibilityLabel: NSLocalizedString("Profile", comment: "")
        ) {
            showProfileDrawer = true
        }
    }

    private func circularActionButton(
        systemName: String,
        accessibilityLabel: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(.primary)
                .frame(width: 42, height: 42)
                .background(
                    Circle().fill(Color.primary.opacity(0.06))
                )
        }
        .accessibilityLabel(accessibilityLabel)
    }

    private func handleDeepLink(_ url: URL) {
        guard url.scheme?.lowercased() == "chroniccare" else { return }
        let host = url.host?.lowercased()
        let pathComponents = url.pathComponents.filter { $0 != "/" }

        switch host {
        case "today":
            showProfileDrawer = false
            showAdherenceCalendar = false
            showInsightsSheet = false
            showMedicationSheet = false
        case "medication":
            let candidate = pathComponents.first ?? url.lastPathComponent
            if let medicationID = UUID(uuidString: candidate) {
                deepLinkMedicationID = medicationID
                showMedicationSheet = true
            } else {
                showMedicationSheet = true
            }
        case "insights":
            showProfileDrawer = false
            showAdherenceCalendar = false
            showMedicationSheet = false
            showInsightsSheet = true
        default:
            break
        }
    }
}

#Preview {
    RootViewV2().environmentObject(DataStore())
}
