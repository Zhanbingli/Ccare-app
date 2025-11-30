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
    @State private var deeplinkMedicationID: UUID? = nil

    var body: some View {
        ZStack {
            AppBackground()
            TabView(selection: $selectedTab) {
                DashboardView()
                    .tag(0)
                    .tabItem { Label("Home", systemImage: "house.fill") }
                MedicationsView()
                    .tag(1)
                    .tabItem { Label("Medications", systemImage: "pill.fill") }
                ProfileView()
                    .tag(2)
                    .tabItem { Label("More", systemImage: "ellipsis.circle") }
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
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("openMedicationDetail"))) { notif in
            if let id = notif.object as? UUID {
                deeplinkMedicationID = id
                selectedTab = 1
            }
        }
    }
}

#Preview {
    ContentView().environmentObject(DataStore())
}
