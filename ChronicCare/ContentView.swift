//
//  ContentView.swift
//  ChronicCare
//
//  Created by lizhanbing12 on 30/08/25.
//

import SwiftUI

struct ContentView: View {
    @EnvironmentObject var store: DataStore
    @Environment(\.scenePhase) private var scenePhase
    @State private var selectedTab = 0
    @State private var showOnboarding = !UserDefaults.standard.bool(forKey: "hasCompletedOnboarding")
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
            TabView(selection: $selectedTab) {
                DashboardView()
                    .tag(0)
                    .tabItem { Label(NSLocalizedString("Today", comment: ""), systemImage: "checklist") }
                MedicationsView(deepLinkMedicationID: $deepLinkMedicationID)
                    .tag(1)
                    .tabItem { Label(NSLocalizedString("Medications", comment: ""), systemImage: "pills") }
                InsightsView()
                    .tag(2)
                    .tabItem { Label(NSLocalizedString("Insights", comment: ""), systemImage: "chart.line.uptrend.xyaxis") }
            }
        }
        .dynamicTypeSize(.xSmall ... .accessibility5)
        .onChange(of: scenePhase) { newPhase in
            guard newPhase == .active else { return }
            let now = Date()
            store.syncNotifications(now: now)
            store.updateWidgetData()
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("openMedicationDetail"))) { notification in
            selectedTab = 1
            if let medID = notification.object as? UUID {
                deepLinkMedicationID = medID
            }
        }
        .onOpenURL { url in
            handleDeepLink(url)
        }
    }

    private func handleDeepLink(_ url: URL) {
        guard url.scheme?.lowercased() == "chroniccare" else { return }

        let host = url.host?.lowercased()
        let pathComponents = url.pathComponents.filter { $0 != "/" }

        switch host {
        case "today":
            selectedTab = 0
        case "medication":
            let candidate = pathComponents.first ?? url.lastPathComponent
            guard let medicationID = UUID(uuidString: candidate) else {
                selectedTab = 1
                return
            }
            selectedTab = 1
            deepLinkMedicationID = medicationID
        case "insights":
            selectedTab = 2
        default:
            selectedTab = 0
        }
    }
}

#Preview {
    ContentView().environmentObject(DataStore())
}
