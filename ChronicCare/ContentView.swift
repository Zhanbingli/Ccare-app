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

    var body: some View {
        ZStack {
            AppBackground()
            TabView {
                DashboardView()
                    .tabItem { Label("Home", systemImage: "house.fill") }
                MeasurementsView()
                    .tabItem { Label("Track", systemImage: "waveform.path.ecg") }
                TrendsView()
                    .tabItem { Label("Trends", systemImage: "chart.line.uptrend.xyaxis") }
                MedicationsView()
                    .tabItem { Label("Meds", systemImage: "pills.fill") }
                ProfileView()
                    .tabItem { Label("More", systemImage: "ellipsis.circle") }
            }
        }
        .environment(\.font, AppFontStyle.body.font)
        .dynamicTypeSize(.medium ... .accessibility5)
        .onChange(of: scenePhase) { newPhase in
            guard newPhase == .active else { return }
            let meds = store.medications.filter { $0.remindersEnabled }
            let now = Date()
            meds.forEach { NotificationManager.shared.schedule(for: $0, now: now) }
        }
    }
}

#Preview {
    ContentView().environmentObject(DataStore())
}
