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
        .environment(\.font, AppFontStyle.body.font)
        .dynamicTypeSize(.medium ... .accessibility5)
        .onChange(of: scenePhase) { newPhase in
            guard newPhase == .active else { return }
            let now = Date()
            NotificationManager.shared.syncAll(medications: store.medications, intakeLogs: store.intakeLogs, now: now)
            NotificationManager.shared.updateBadge(store: store)
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("openMedicationDetail"))) { notification in
            selectedTab = 1
            if let medID = notification.object as? UUID {
                deepLinkMedicationID = medID
            }
        }
    }
}

#Preview {
    ContentView().environmentObject(DataStore())
}
