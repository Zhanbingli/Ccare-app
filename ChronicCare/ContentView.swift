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
                HealthView()
                    .tag(1)
                    .tabItem { Label(NSLocalizedString("Health", comment: ""), systemImage: "heart.text.square") }
                ProfileView()
                    .tag(2)
                    .tabItem { Label(NSLocalizedString("Settings", comment: ""), systemImage: "gearshape") }
            }
        }
        .environment(\.font, AppFontStyle.body.font)
        .dynamicTypeSize(.medium ... .accessibility5)
        .onChange(of: scenePhase) { newPhase in
            guard newPhase == .active else { return }
            let meds = store.medications.filter { $0.remindersEnabled }
            let now = Date()
            NotificationManager.shared.cleanOrphanedRequests(validMedicationIDs: Set(meds.map { $0.id }))
            meds.forEach { NotificationManager.shared.schedule(for: $0, now: now) }
            NotificationManager.shared.checkRefillReminders(medications: store.medications)
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("openMedicationDetail"))) { _ in
            selectedTab = 1
        }
    }
}

#Preview {
    ContentView().environmentObject(DataStore())
}
