//
//  ChronicCareTests.swift
//  ChronicCareTests
//
//  Created by lizhanbing12 on 30/08/25.
//

import Testing
@testable import ChronicCare

struct ChronicCareTests {

    @Test func example() async throws {
        // Write your test here and use APIs like `#expect(...)` to check expected conditions.
    }

    @Test func scheduleComponentsFromUserInfo() {
        let comps = NotificationManager.scheduleComponents(from: ["scheduleHour": 8, "scheduleMinute": 45])
        #expect(comps?.hour == 8)
        #expect(comps?.minute == 45)
    }

    @Test func snoozeIdentifierIncludesSchedule() {
        let medID = UUID()
        let comps = DateComponents(hour: 6, minute: 15)
        let id = NotificationManager.snoozeIdentifier(for: medID, scheduleTime: comps)
        #expect(id.contains(String(format: "%02d", comps.hour ?? -1)))
        #expect(id.contains(String(format: "%02d", comps.minute ?? -1)))
    }

    @Test func outstandingCountHonorsTakenLogPerSchedule() {
        let medID = UUID()
        let morning = DateComponents(hour: 8, minute: 0)
        let evening = DateComponents(hour: 20, minute: 0)
        let med = Medication(id: medID, name: "Example", dose: "5mg", timesOfDay: [morning, evening], remindersEnabled: true)

        let cal = Calendar.current
        let takenDate = cal.date(bySettingHour: 8, minute: 5, second: 0, of: Date()) ?? Date()
        let log = IntakeLog(medicationID: medID, date: takenDate, status: .taken, scheduleKey: "08:00")

        let count = NotificationManager.computeOutstandingCount(medications: [med], intakeLogs: [log], graceMinutes: 0)
        #expect(count == 1)
    }

}
