//
//  ContentView.swift
//  ChronicCare
//
//  Created by lizhanbing12 on 30/08/25.
//

import SwiftUI

struct ContentView: View {
    var body: some View {
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
}

#Preview {
    ContentView().environmentObject(DataStore())
}
