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
    @State private var visitReportRoute: VisitReportRoute?
    @State private var pendingMeasurementType: MeasurementType = .bloodPressure
    @State private var deepLinkMedicationID: UUID? = nil

    private struct VisitReportRoute: Identifiable {
        enum Kind: String {
            case hypertension
            case diabetes
        }

        let kind: Kind
        let visitID: UUID?

        var id: String {
            "\(kind.rawValue).\(visitID?.uuidString ?? "current")"
        }
    }

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
                onLogMeasurement: { type in
                    pendingMeasurementType = type
                    showLogSheet = true
                },
                onOpenProfile: { showProfileDrawer = true },
                onOpenMedications: { showMedicationSheet = true }
            )
        }
        .dynamicTypeSize(.xSmall ... .accessibility5)
        .sheet(isPresented: $showProfileDrawer) {
            ProfileDrawerV2(onLogMeasurement: {
                showProfileDrawer = false
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                    pendingMeasurementType = .bloodPressure
                    showLogSheet = true
                }
            })
            .environmentObject(store)
        }
        .sheet(isPresented: $showLogSheet) {
            AddMeasurementView(initialType: pendingMeasurementType) { measurement in
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
        .sheet(item: $visitReportRoute) { route in
            NavigationStack {
                visitReportDestination(route)
                    .environmentObject(store)
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button(NSLocalizedString("Done", comment: "")) {
                                visitReportRoute = nil
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
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("openVisitSnapshot"))) { notification in
            if let visitID = notification.object as? UUID {
                openVisitReport(visitID: visitID)
            }
        }
        .onOpenURL { url in
            handleDeepLink(url)
        }
    }

    @ViewBuilder
    private func visitReportDestination(_ route: VisitReportRoute) -> some View {
        switch route.kind {
        case .hypertension:
            HypertensionFollowUpReportView(visit: visit(for: route.visitID))
        case .diabetes:
            DiabetesFollowUpReportView(visit: visit(for: route.visitID))
        }
    }

    private func visit(for id: UUID?) -> DoctorVisit? {
        guard let id else { return store.nextDoctorVisit }
        return store.doctorVisits.first { $0.id == id } ?? store.nextDoctorVisit
    }

    private func openVisitReport(visitID: UUID?) {
        showProfileDrawer = false
        showMedicationSheet = false
        showAdherenceCalendar = false
        showInsightsSheet = false
        visitReportRoute = VisitReportRoute(kind: primaryReportKind(), visitID: visitID)
    }

    private func primaryReportKind() -> VisitReportRoute.Kind {
        let hasHypertensionContext = store.medications.contains { $0.category == .antihypertensive }
            || store.measurements.contains { $0.type == .bloodPressure }
        if hasHypertensionContext {
            return .hypertension
        }

        let hasDiabetesContext = store.medications.contains { $0.category == .antidiabetic }
            || store.measurements.contains { $0.type == .bloodGlucose }
        if hasDiabetesContext {
            return .diabetes
        }

        return .hypertension
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
        case "visit", "snapshot":
            let candidate = pathComponents.first ?? url.lastPathComponent
            openVisitReport(visitID: UUID(uuidString: candidate))
        default:
            break
        }
    }
}

#Preview {
    RootViewV2().environmentObject(DataStore())
}
