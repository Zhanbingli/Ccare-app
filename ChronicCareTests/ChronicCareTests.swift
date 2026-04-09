//
//  ChronicCareTests.swift
//  ChronicCareTests
//
//  Created by lizhanbing12 on 30/08/25.
//

import Foundation
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

    @Test func suppressionKeyHandlesSnoozeAndFollowUpIdentifiers() {
        let medID = UUID()
        let base = "\(medID.uuidString)_20260408_08_30"
        let snooze = "snooze_\(medID.uuidString)_08_30"
        let followUp = "followup_2_\(medID.uuidString)_20260408_08_30"

        #expect(NotificationManager.suppressionKey(for: base) == "\(medID.uuidString)_08_30")
        #expect(NotificationManager.suppressionKey(for: snooze) == "\(medID.uuidString)_08_30")
        #expect(NotificationManager.suppressionKey(for: followUp) == "\(medID.uuidString)_08_30")
    }

    @Test func orphanCleanupIgnoresNonMedicationScopedIdentifiers() {
        let validID = UUID()
        let invalidID = UUID()
        let validIDs = Set([validID.uuidString])

        #expect(NotificationManager.isMedicationScoped(identifier: "streak_7_2026-04-08") == false)
        #expect(NotificationManager.hasValidMedication(identifier: "streak_7_2026-04-08", validMedicationIDs: validIDs))
        #expect(NotificationManager.hasValidMedication(identifier: "refill_\(validID.uuidString)", validMedicationIDs: validIDs))
        #expect(NotificationManager.hasValidMedication(identifier: "refill_\(invalidID.uuidString)", validMedicationIDs: validIDs) == false)
        #expect(NotificationManager.hasValidMedication(identifier: "course_\(validID.uuidString)", validMedicationIDs: validIDs))
        #expect(NotificationManager.hasValidMedication(identifier: "course_\(invalidID.uuidString)", validMedicationIDs: validIDs) == false)
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

    @Test func measurementClampsFutureDateToNow() {
        let now = Date()
        let future = now.addingTimeInterval(60 * 60 * 24)
        let measurement = Measurement(type: .bloodPressure, value: 120, diastolic: 80, date: future, note: nil)

        let clamped = measurement.clampedToNow(now: now)

        #expect(clamped.date == now)
    }

    @Test func adaptiveReminderAddsLeadTimeForConsistentDelay() {
        let cal = Calendar.current
        let now = cal.date(from: DateComponents(year: 2026, month: 4, day: 8, hour: 10, minute: 0))!
        let comps = DateComponents(hour: 8, minute: 0)
        let med = Medication(name: "Amlodipine", dose: "5mg", timesOfDay: [comps], remindersEnabled: true)

        let logs = (0..<3).compactMap { offset -> IntakeLog? in
            guard let scheduled = cal.date(byAdding: .day, value: -offset, to: now).flatMap({ cal.date(bySettingHour: 8, minute: 0, second: 0, of: $0) }) else { return nil }
            let recorded = scheduled.addingTimeInterval(18 * 60)
            return IntakeLog(
                medicationID: med.id,
                date: scheduled,
                status: .taken,
                scheduleKey: "08:00",
                note: nil,
                scheduledDate: scheduled,
                recordedAt: recorded
            )
        }

        let strategy = AdaptiveReminderEngine.strategy(for: med, intakeLogs: logs, now: now)

        #expect(strategy.leadMinutes == 10)
        #expect(strategy.riskLevel == .medium)
    }

    @Test func adaptiveReminderReducesFollowUpsAfterStrongStreak() {
        let cal = Calendar.current
        let now = cal.date(from: DateComponents(year: 2026, month: 4, day: 8, hour: 10, minute: 0))!
        let comps = DateComponents(hour: 8, minute: 0)
        let med = Medication(name: "Metformin", dose: "500mg", timesOfDay: [comps], remindersEnabled: true)

        let logs = (0..<7).compactMap { offset -> IntakeLog? in
            guard let scheduled = cal.date(byAdding: .day, value: -offset, to: now).flatMap({ cal.date(bySettingHour: 8, minute: 0, second: 0, of: $0) }) else { return nil }
            let recorded = scheduled.addingTimeInterval(2 * 60)
            return IntakeLog(
                medicationID: med.id,
                date: scheduled,
                status: .taken,
                scheduleKey: "08:00",
                note: nil,
                scheduledDate: scheduled,
                recordedAt: recorded
            )
        }

        let strategy = AdaptiveReminderEngine.strategy(for: med, intakeLogs: logs, now: now)

        #expect(strategy.followUpIntervals == [20])
        #expect(strategy.riskLevel == .low)
    }

    @MainActor
    @Test func prnLogsDoNotOverwriteSameMinuteEntries() {
        let store = DataStore()
        store.clearAll()
        let med = Medication(name: "Ibuprofen", dose: "200mg", timesOfDay: [], remindersEnabled: false, isAsNeeded: true)
        store.addMedication(med)

        let cal = Calendar.current
        let first = cal.date(from: DateComponents(year: 2026, month: 4, day: 8, hour: 9, minute: 0, second: 5))!
        let second = cal.date(from: DateComponents(year: 2026, month: 4, day: 8, hour: 9, minute: 0, second: 45))!
        let comps = DateComponents(hour: 9, minute: 0)

        store.upsertIntake(
            medicationID: med.id,
            status: .taken,
            scheduleTime: comps,
            at: first,
            scheduledDate: first,
            scheduleKeyOverride: "prn_\(first.timeIntervalSince1970)"
        )
        store.upsertIntake(
            medicationID: med.id,
            status: .taken,
            scheduleTime: comps,
            at: second,
            scheduledDate: second,
            scheduleKeyOverride: "prn_\(second.timeIntervalSince1970)"
        )

        let sameDayLogs = store.intakeLogs.filter { $0.medicationID == med.id }
        #expect(sameDayLogs.count == 2)
    }

    @Test func medicationLabelParserExtractsNameDoseAndInstructions() {
        let result = MedicationLabelParser.parse(recognizedLines: [
            "AMLODIPINE BESYLATE 5 mg tablets",
            "Take once daily with food"
        ])

        #expect(result.name == "Amlodipine Besylate")
        #expect(result.dose == "5mg")
        #expect(result.notes == "Once daily, With food")
    }

    @Test func medicationLabelParserHandlesChineseDoseLine() {
        let result = MedicationLabelParser.parse(recognizedLines: [
            "苯磺酸氨氯地平片 5mg",
            "每日一次"
        ])

        #expect(result.name == "苯磺酸氨氯地平片")
        #expect(result.dose == "5mg")
    }

    @Test func reminderEligibilityRejectsPRNAndUntimedMeds() {
        let scheduled = Medication(name: "A", dose: "5mg", timesOfDay: [DateComponents(hour: 8, minute: 0)], remindersEnabled: true)
        let prn = Medication(name: "B", dose: "5mg", timesOfDay: [], remindersEnabled: true, isAsNeeded: true)
        let untimed = Medication(name: "C", dose: "5mg", timesOfDay: [], remindersEnabled: true)

        #expect(NotificationManager.shared.isReminderEligible(scheduled))
        #expect(NotificationManager.shared.isReminderEligible(prn) == false)
        #expect(NotificationManager.shared.isReminderEligible(untimed) == false)
    }

    @Test func outstandingCountIgnoresPRNMedicationWithoutSchedule() {
        let prn = Medication(name: "Ibuprofen", dose: "200mg", timesOfDay: [], remindersEnabled: true, isAsNeeded: true)
        let count = NotificationManager.computeOutstandingCount(medications: [prn], intakeLogs: [], graceMinutes: 0)
        #expect(count == 0)
    }

    @Test func medicationCourseStateTracksEndingSoonAndEnded() {
        let calendar = Calendar.current
        let now = calendar.date(from: DateComponents(year: 2026, month: 4, day: 9, hour: 10, minute: 0))!

        let endingSoon = Medication(
            name: "Antibiotic",
            dose: "250mg",
            timesOfDay: [DateComponents(hour: 8, minute: 0)],
            remindersEnabled: true,
            courseEndDate: calendar.date(byAdding: .day, value: 2, to: now)
        )
        let ended = Medication(
            name: "Steroid",
            dose: "5mg",
            timesOfDay: [DateComponents(hour: 8, minute: 0)],
            remindersEnabled: true,
            courseEndDate: calendar.date(byAdding: .day, value: -1, to: now)
        )

        #expect(endingSoon.courseState(thresholdDays: 3, reference: now) == .endingSoon(daysRemaining: 2))
        #expect(ended.courseState(thresholdDays: 3, reference: now) == .ended(daysPast: 1))
    }

    @Test func prnSupplyDaysRemainUnknownWithoutFixedSchedule() {
        let prn = Medication(
            name: "Ibuprofen",
            dose: "200mg",
            timesOfDay: [],
            remindersEnabled: false,
            pillsRemaining: 24,
            pillsPerDose: 2,
            isAsNeeded: true
        )

        #expect(prn.daysOfSupplyRemaining == nil)
        #expect(prn.isLowSupply == false)
    }

    @Test func upcomingFireDatesKeepsJustMissedDoseWithinCatchUpWindow() {
        let manager = NotificationManager.shared
        let calendar = Calendar.current
        let now = calendar.date(from: DateComponents(year: 2026, month: 4, day: 9, hour: 8, minute: 0, second: 30))!
        let comps = DateComponents(hour: 8, minute: 0)

        let dates = manager.upcomingFireDates(for: comps, horizonDays: 1, from: now, catchUpWindow: 90)

        #expect(dates.count == 1)
        #expect(calendar.component(.hour, from: dates[0]) == 8)
        #expect(calendar.component(.minute, from: dates[0]) == 0)
    }

}
