//
//  ChronicCareApp.swift
//  ChronicCare
//
//  Created by lizhanbing12 on 30/08/25.
//

import SwiftUI
import UserNotifications

@main
struct ChronicCareApp: App {
    @StateObject private var store = DataStore()
    private let notifHandler = NotificationHandler()
    init() {
        // Setup notification delegate early to catch action taps before UI appears
        let center = UNUserNotificationCenter.current()
        center.delegate = notifHandler
        // Default haptics ON if unset
        if UserDefaults.standard.object(forKey: "hapticsEnabled") == nil {
            Haptics.setEnabled(true)
        }
    }
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
                .onAppear {
                    notifHandler.store = store
                    NotificationManager.shared.registerCategories()
                    // Ensure all active medication reminders are scheduled on launch
                    for med in store.medications where med.remindersEnabled {
                        NotificationManager.shared.schedule(for: med)
                    }
                    // Start badge refresh observers and update once on launch
                    NotificationManager.shared.startBadgeAutoRefresh(store: store)
                    NotificationManager.shared.updateBadge(store: store)
                }
        }
    }
}
