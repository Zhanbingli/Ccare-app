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

    @Test func doseReminderScopeDoesNotIncludeLifecycleReminders() {
        let medID = UUID()
        let base = "\(medID.uuidString)_20260410_08_00"
        let followUp = "followup_1_\(base)"
        let snooze = "snooze_\(medID.uuidString)_08_00"

        #expect(NotificationManager.isDoseReminder(identifier: base, medicationID: medID))
        #expect(NotificationManager.isDoseReminder(identifier: followUp, medicationID: medID))
        #expect(NotificationManager.isDoseReminder(identifier: snooze, medicationID: medID))
        #expect(NotificationManager.isDoseReminder(identifier: "refill_\(medID.uuidString)", medicationID: medID) == false)
        #expect(NotificationManager.isDoseReminder(identifier: "course_\(medID.uuidString)", medicationID: medID) == false)
        #expect(NotificationManager.isDoseReminder(identifier: "miss_warn_\(medID.uuidString)_2026-04-10", medicationID: medID) == false)
    }

    @Test func outstandingCountHonorsTakenLogPerSchedule() {
        let medID = UUID()
        let morning = DateComponents(hour: 8, minute: 0)
        let evening = DateComponents(hour: 20, minute: 0)
        let med = Medication(id: medID, name: "Example", dose: "5mg", timesOfDay: [morning, evening], remindersEnabled: true)

        let cal = Calendar.current
        // Use a fixed reference time (23:00) so both morning and evening doses have passed
        let referenceDate = cal.date(bySettingHour: 23, minute: 0, second: 0, of: Date()) ?? Date()
        let takenDate = cal.date(bySettingHour: 8, minute: 5, second: 0, of: referenceDate) ?? referenceDate
        let log = IntakeLog(medicationID: medID, date: takenDate, status: .taken, scheduleKey: "08:00")

        let count = NotificationManager.computeOutstandingCount(medications: [med], intakeLogs: [log], graceMinutes: 0, now: referenceDate)
        #expect(count == 1)
    }

    @Test func doseSchedulingSkipsLoggedOutcomeForSameScheduleAndDay() {
        let medID = UUID()
        let morning = DateComponents(hour: 8, minute: 0)
        let evening = DateComponents(hour: 20, minute: 0)
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 0)!
        let day = cal.date(from: DateComponents(year: 2026, month: 4, day: 8))!
        let morningDate = cal.date(bySettingHour: 8, minute: 0, second: 0, of: day)!
        let eveningDate = cal.date(bySettingHour: 20, minute: 0, second: 0, of: day)!
        let log = IntakeLog(
            medicationID: medID,
            date: morningDate,
            status: .taken,
            scheduleKey: "08:00",
            scheduledDate: morningDate,
            recordedAt: morningDate.addingTimeInterval(60)
        )

        #expect(NotificationManager.shouldScheduleDoseReminder(
            medicationID: medID,
            scheduleTime: morning,
            doseDate: morningDate,
            intakeLogs: [log],
            allowNilScheduleKey: false,
            calendar: cal
        ) == false)

        #expect(NotificationManager.shouldScheduleDoseReminder(
            medicationID: medID,
            scheduleTime: evening,
            doseDate: eveningDate,
            intakeLogs: [log],
            allowNilScheduleKey: false,
            calendar: cal
        ))
    }

    @Test func doseSchedulingSkipsSnoozedOutcomeForSameScheduleAndDay() {
        let medID = UUID()
        let morning = DateComponents(hour: 8, minute: 0)
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 0)!
        let day = cal.date(from: DateComponents(year: 2026, month: 4, day: 8))!
        let morningDate = cal.date(bySettingHour: 8, minute: 0, second: 0, of: day)!
        let log = IntakeLog(
            medicationID: medID,
            date: morningDate,
            status: .snoozed,
            scheduleKey: "08:00",
            scheduledDate: morningDate,
            recordedAt: morningDate.addingTimeInterval(120)
        )

        #expect(NotificationManager.shouldScheduleDoseReminder(
            medicationID: medID,
            scheduleTime: morning,
            doseDate: morningDate,
            intakeLogs: [log],
            allowNilScheduleKey: false,
            calendar: cal
        ) == false)
    }

    @MainActor
    @Test func makeupDoseAllowsLateDoseBeforeMidpointToNextDose() {
        let cal = Calendar.current
        let now = cal.date(from: DateComponents(year: 2026, month: 4, day: 8, hour: 10, minute: 0))!
        let med = Medication(
            name: "Metformin",
            dose: "500mg",
            timesOfDay: [DateComponents(hour: 8, minute: 0), DateComponents(hour: 20, minute: 0)],
            remindersEnabled: true
        )

        let result = MedicationRules.checkMakeupDose(
            medication: med,
            missedTime: DateComponents(hour: 8, minute: 0),
            now: now
        )

        if case .canTakeLate = result {
            #expect(true)
        } else {
            #expect(Bool(false), "Expected late dose to remain in the recovery window")
        }
    }

    @MainActor
    @Test func makeupDoseBlocksLateDoseWhenTooCloseToNextDose() {
        let cal = Calendar.current
        let now = cal.date(from: DateComponents(year: 2026, month: 4, day: 8, hour: 16, minute: 0))!
        let med = Medication(
            name: "Metformin",
            dose: "500mg",
            timesOfDay: [DateComponents(hour: 8, minute: 0), DateComponents(hour: 20, minute: 0)],
            remindersEnabled: true
        )

        let result = MedicationRules.checkMakeupDose(
            medication: med,
            missedTime: DateComponents(hour: 8, minute: 0),
            now: now
        )

        if case .tooCloseToNext(let next) = result {
            #expect(cal.component(.hour, from: next) == 20)
        } else {
            #expect(Bool(false), "Expected missed dose to be too close to the next scheduled dose")
        }
    }

    @MainActor
    @Test func dailySafetyCheckDoesNotWarnForCloseMedicationSchedules() {
        let first = Medication(
            name: "Amlodipine",
            dose: "5mg",
            timesOfDay: [DateComponents(hour: 8, minute: 0)],
            remindersEnabled: true
        )
        let second = Medication(
            name: "Metformin",
            dose: "500mg",
            timesOfDay: [DateComponents(hour: 8, minute: 15)],
            remindersEnabled: true
        )
        var rule = MedicationRuleConfig.defaults
        rule.timingConflictMinutes = 60
        MedicationRuleStore.shared.setOverride(rule, for: first.id)
        MedicationRuleStore.shared.setOverride(rule, for: second.id)
        defer {
            MedicationRuleStore.shared.removeOverride(for: first.id)
            MedicationRuleStore.shared.removeOverride(for: second.id)
        }

        let rawConflicts = MedicationRules.checkTimingConflicts(medications: [first, second])
        let dailySummary = MedicationRules.dailySafetyCheck(
            medications: [first, second],
            intakeLogs: [],
            consecutiveMissedDaysProvider: { _ in 0 }
        )

        #expect(rawConflicts.isEmpty == false)
        #expect(dailySummary.timingConflicts.isEmpty)
        #expect(dailySummary.hasIssues == false)
    }

    @Test func consecutiveMissedDaysClearsAfterTakenDoseToday() {
        let cal = Calendar(identifier: .gregorian)
        let now = DateComponents(calendar: cal, year: 2026, month: 5, day: 7, hour: 12).date!
        let medID = UUID()
        let med = Medication(
            id: medID,
            name: "Amlodipine",
            dose: "5mg",
            timesOfDay: [DateComponents(hour: 8, minute: 0)],
            remindersEnabled: true
        )
        let fiveDaysAgo = cal.date(byAdding: .day, value: -5, to: now)!
        let oldTaken = IntakeLog(
            medicationID: medID,
            date: cal.date(bySettingHour: 8, minute: 0, second: 0, of: fiveDaysAgo)!,
            status: .taken,
            scheduleKey: "08:00"
        )
        let todayTaken = IntakeLog(
            medicationID: medID,
            date: cal.date(bySettingHour: 8, minute: 0, second: 0, of: now)!,
            status: .taken,
            scheduleKey: "08:00"
        )

        let missedBeforeTodayLog = AdherenceCalculator.consecutiveMissedDays(
            for: medID,
            medications: [med],
            intakeLogs: [oldTaken],
            now: now,
            calendar: cal
        )
        let missedAfterTodayLog = AdherenceCalculator.consecutiveMissedDays(
            for: medID,
            medications: [med],
            intakeLogs: [oldTaken, todayTaken],
            now: now,
            calendar: cal
        )

        #expect(missedBeforeTodayLog == 4)
        #expect(missedAfterTodayLog == 0)
    }

    @Test func measurementClampsFutureDateToNow() {
        let now = Date()
        let future = now.addingTimeInterval(60 * 60 * 24)
        let measurement = Measurement(type: .bloodPressure, value: 120, diastolic: 80, date: future, note: nil)

        let clamped = measurement.clampedToNow(now: now)

        #expect(clamped.date == now)
    }

    @Test func doctorVisitClassifiesUpcomingAndOverdueByCalendarDay() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = cal.date(from: DateComponents(year: 2026, month: 4, day: 24, hour: 10))!
        let future = cal.date(from: DateComponents(year: 2026, month: 4, day: 27, hour: 9))!
        let past = cal.date(from: DateComponents(year: 2026, month: 4, day: 23, hour: 9))!

        let upcoming = DoctorVisit(scheduledDate: future)
        let overdue = DoctorVisit(scheduledDate: past)

        #expect(upcoming.isUpcoming(now: now, calendar: cal))
        #expect(upcoming.daysUntil(now: now, calendar: cal) == 3)
        #expect(overdue.isOverdue(now: now, calendar: cal))
        #expect(overdue.daysUntil(now: now, calendar: cal) == -1)
    }

    @Test func visitPrepReminderUsesThreeDayLeadOrNextMorning() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = cal.date(from: DateComponents(year: 2026, month: 4, day: 24, hour: 10))!
        let laterVisitDate = cal.date(from: DateComponents(year: 2026, month: 4, day: 30, hour: 9))!
        let nearVisitDate = cal.date(from: DateComponents(year: 2026, month: 4, day: 27, hour: 9))!

        let laterFire = NotificationManager.shared.visitPrepFireDate(
            for: DoctorVisit(scheduledDate: laterVisitDate),
            now: now,
            calendar: cal
        )
        let nearFire = NotificationManager.shared.visitPrepFireDate(
            for: DoctorVisit(scheduledDate: nearVisitDate),
            now: now,
            calendar: cal
        )

        #expect(laterFire == cal.date(from: DateComponents(year: 2026, month: 4, day: 27, hour: 9)))
        #expect(nearFire == cal.date(from: DateComponents(year: 2026, month: 4, day: 25, hour: 9)))
    }

    @Test func adaptiveReminderAddsLeadTimeForConsistentDelay() {
        let cal = Calendar.current
        let now = cal.date(from: DateComponents(year: 2026, month: 4, day: 8, hour: 10, minute: 0))!
        let comps = DateComponents(hour: 8, minute: 0)
        let medStart = cal.date(byAdding: .day, value: -6, to: now)!
        let med = Medication(name: "Amlodipine", dose: "5mg", startDate: medStart, timesOfDay: [comps], remindersEnabled: true)

        let logs = (0..<6).compactMap { offset -> IntakeLog? in
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
        let medStart = cal.startOfDay(for: cal.date(byAdding: .day, value: -6, to: now)!)
        let med = Medication(name: "Metformin", dose: "500mg", startDate: medStart, timesOfDay: [comps], remindersEnabled: true)

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

        #expect(strategy.followUpIntervals == [15, 45])
        #expect(strategy.riskLevel == .low)
    }

    @Test func adaptiveSchedulingUsesStandardUntilUserConfirms() {
        let cal = Calendar.current
        let now = cal.date(from: DateComponents(year: 2026, month: 4, day: 8, hour: 10, minute: 0))!
        let comps = DateComponents(hour: 8, minute: 0)
        let medStart = cal.date(byAdding: .day, value: -6, to: now)!
        let med = Medication(name: "Amlodipine", dose: "5mg", startDate: medStart, timesOfDay: [comps], remindersEnabled: true)
        defer { AdaptiveReminderPreferenceStore.clearAll(for: med.id) }

        let logs = (0..<6).compactMap { offset -> IntakeLog? in
            guard let scheduled = cal.date(byAdding: .day, value: -offset, to: now).flatMap({ cal.date(bySettingHour: 8, minute: 0, second: 0, of: $0) }) else { return nil }
            return IntakeLog(
                medicationID: med.id,
                date: scheduled,
                status: .taken,
                scheduleKey: "08:00",
                scheduledDate: scheduled,
                recordedAt: scheduled.addingTimeInterval(18 * 60)
            )
        }

        let standard = AdaptiveReminderEngine.schedulingStrategy(for: med, intakeLogs: logs, now: now)
        #expect(standard == AdaptiveReminderEngine.standardStrategy)

        AdaptiveReminderPreferenceStore.setAdaptiveSchedulingEnabled(true, for: med.id)
        let confirmed = AdaptiveReminderEngine.schedulingStrategy(for: med, intakeLogs: logs, now: now)
        #expect(confirmed.leadMinutes == 10)
    }

    @Test func adaptiveReminderSuggestsHigherSupportForMissPattern() {
        let cal = Calendar.current
        let now = cal.date(from: DateComponents(year: 2026, month: 4, day: 8, hour: 10, minute: 0))!
        let comps = DateComponents(hour: 8, minute: 0)
        let medStart = cal.date(byAdding: .day, value: -7, to: now)!
        let med = Medication(name: "Amlodipine", dose: "5mg", startDate: medStart, timesOfDay: [comps], remindersEnabled: true)
        defer { AdaptiveReminderPreferenceStore.clearAll(for: med.id) }

        let suggestion = AdaptiveReminderEngine.suggestion(for: med, intakeLogs: [], now: now)

        #expect(suggestion?.kind == .increaseSupport)
        #expect(suggestion?.proposedStrategy.riskLevel == .high)
    }

    @Test func adaptiveReminderDismissalSuppressesSuggestion() {
        let cal = Calendar.current
        let now = cal.date(from: DateComponents(year: 2026, month: 4, day: 8, hour: 10, minute: 0))!
        let comps = DateComponents(hour: 8, minute: 0)
        let medStart = cal.date(byAdding: .day, value: -7, to: now)!
        let med = Medication(name: "Amlodipine", dose: "5mg", startDate: medStart, timesOfDay: [comps], remindersEnabled: true)
        defer { AdaptiveReminderPreferenceStore.clearAll(for: med.id) }

        AdaptiveReminderPreferenceStore.dismissSuggestion(
            .increaseSupport,
            for: med.id,
            until: now.addingTimeInterval(24 * 60 * 60)
        )

        let suggestion = AdaptiveReminderEngine.suggestion(for: med, intakeLogs: [], now: now)
        #expect(suggestion == nil)
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

    @Test func medicationLabelParserDoesNotUsePharmacyNoiseAsName() {
        let result = MedicationLabelParser.parse(recognizedLines: [
            "Main Street Pharmacy",
            "Patient: Jane Smith",
            "NDC 12345-6789",
            "Take 1 tablet by mouth daily",
            "METFORMIN 500 mg tablets"
        ])

        #expect(result.name == "Metformin")
        #expect(result.dose == "500mg")
    }

    @Test func medicationLabelParserLeavesNameEmptyWhenOnlyInstructionsAreVisible() {
        let result = MedicationLabelParser.parse(recognizedLines: [
            "Take 1 tablet by mouth daily",
            "Qty 30",
            "Refill before 04/30/2026"
        ])

        #expect(result.name == nil)
        #expect(result.dose == nil)
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

    @Test func duplicateMedicationScheduleIsValidationError() {
        let duplicateTimes = [
            DateComponents(hour: 8, minute: 0),
            DateComponents(hour: 8, minute: 0)
        ]

        let result = DataValidator.validateMedicationSchedule(duplicateTimes)

        guard case .error(let message) = result else {
            Issue.record("Expected duplicate schedule times to be rejected.")
            return
        }
        #expect(message == "Reminder times must be unique.")
    }

    @MainActor
    @Test func dataStoreRejectsMedicationWithDuplicateScheduleTimes() {
        let store = DataStore()
        store.clearAll()
        let medication = Medication(
            name: "Metformin",
            dose: "500mg",
            timesOfDay: [
                DateComponents(hour: 8, minute: 0),
                DateComponents(hour: 8, minute: 0)
            ],
            remindersEnabled: false
        )

        let error = store.addMedication(medication)

        #expect(error == "Reminder times must be unique.")
        #expect(store.medications.isEmpty)
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

    // MARK: - DataStore Mutation Tests

    @MainActor
    @Test func addMedicationRejectsEmptyName() {
        let store = DataStore()
        store.clearAll()
        let med = Medication(name: "", dose: "5mg", timesOfDay: [DateComponents(hour: 8, minute: 0)], remindersEnabled: true)
        let error = store.addMedication(med)
        #expect(error != nil)
        #expect(store.medications.isEmpty)
    }

    @MainActor
    @Test func addMedicationAcceptsValidInput() {
        let store = DataStore()
        store.clearAll()
        let med = Medication(name: "Amlodipine", dose: "5mg", timesOfDay: [DateComponents(hour: 8, minute: 0)], remindersEnabled: true)
        let error = store.addMedication(med)
        #expect(error == nil)
        #expect(store.medications.count == 1)
    }

    @MainActor
    @Test func updateMedicationRejectsEmptyName() {
        let store = DataStore()
        store.clearAll()
        var med = Medication(name: "Amlodipine", dose: "5mg", timesOfDay: [DateComponents(hour: 8, minute: 0)], remindersEnabled: true)
        store.addMedication(med)
        med.name = ""
        let error = store.updateMedication(med)
        #expect(error != nil)
        #expect(store.medications.first?.name == "Amlodipine")
    }

    @MainActor
    @Test func addMedicationRejectsNegativePills() {
        let store = DataStore()
        store.clearAll()
        let med = Medication(name: "Test", dose: "5mg", timesOfDay: [], remindersEnabled: false, pillsRemaining: -5)
        let error = store.addMedication(med)
        #expect(error != nil)
        #expect(store.medications.isEmpty)
    }

    @MainActor
    @Test func decrementPillsStopsAtZero() {
        let store = DataStore()
        store.clearAll()
        let med = Medication(name: "Test", dose: "5mg", timesOfDay: [DateComponents(hour: 8, minute: 0)], remindersEnabled: false, pillsRemaining: 1, pillsPerDose: 1)
        store.addMedication(med)
        store.decrementPills(for: med.id)
        #expect(store.medications.first?.pillsRemaining == 0)
        store.decrementPills(for: med.id)
        #expect(store.medications.first?.pillsRemaining == 0)
    }

    @MainActor
    @Test func recordTakenDoseDoesNotDoubleDecrementSameScheduledDose() {
        let store = DataStore()
        store.clearAll()
        let comps = DateComponents(hour: 8, minute: 0)
        let scheduled = Calendar.current.date(from: DateComponents(year: 2026, month: 4, day: 10, hour: 8, minute: 0))!
        let med = Medication(name: "Test", dose: "5mg", timesOfDay: [comps], remindersEnabled: true, pillsRemaining: 10, pillsPerDose: 2)
        store.addMedication(med)

        store.recordTakenDose(medicationID: med.id, scheduleTime: comps, at: scheduled, scheduledDate: scheduled)
        store.recordTakenDose(medicationID: med.id, scheduleTime: comps, at: scheduled, scheduledDate: scheduled)

        #expect(store.intakeLogs.count == 1)
        #expect(store.intakeLogs.first?.status == .taken)
        #expect(store.medications.first?.pillsRemaining == 8)
    }

    @MainActor
    @Test func deletingTakenIntakeRestoresPillSupply() {
        let store = DataStore()
        store.clearAll()
        let comps = DateComponents(hour: 8, minute: 0)
        let scheduled = Calendar.current.date(from: DateComponents(year: 2026, month: 4, day: 10, hour: 8, minute: 0))!
        let med = Medication(name: "Test", dose: "5mg", timesOfDay: [comps], remindersEnabled: true, pillsRemaining: 10, pillsPerDose: 2)
        store.addMedication(med)

        store.recordTakenDose(medicationID: med.id, scheduleTime: comps, at: scheduled, scheduledDate: scheduled)
        let log = store.intakeLogs.first!
        store.removeIntakeLog(log)

        #expect(store.intakeLogs.isEmpty)
        #expect(store.medications.first?.pillsRemaining == 10)
    }

    @MainActor
    @Test func replacingTakenWithSkippedRestoresPillSupply() {
        let store = DataStore()
        store.clearAll()
        let comps = DateComponents(hour: 8, minute: 0)
        let scheduled = Calendar.current.date(from: DateComponents(year: 2026, month: 4, day: 10, hour: 8, minute: 0))!
        let med = Medication(name: "Test", dose: "5mg", timesOfDay: [comps], remindersEnabled: true, pillsRemaining: 10, pillsPerDose: 2)
        store.addMedication(med)

        store.recordTakenDose(medicationID: med.id, scheduleTime: comps, at: scheduled, scheduledDate: scheduled)
        store.upsertIntake(medicationID: med.id, status: .skipped, scheduleTime: comps, at: scheduled, scheduledDate: scheduled)

        #expect(store.intakeLogs.count == 1)
        #expect(store.intakeLogs.first?.status == .skipped)
        #expect(store.medications.first?.pillsRemaining == 10)
    }

    @MainActor
    @Test func upsertIntakeReplacesExistingLogForSameScheduleKey() {
        let store = DataStore()
        store.clearAll()
        let med = Medication(name: "Test", dose: "5mg", timesOfDay: [DateComponents(hour: 8, minute: 0)], remindersEnabled: true)
        store.addMedication(med)

        let comps = DateComponents(hour: 8, minute: 0)
        store.upsertIntake(medicationID: med.id, status: .snoozed, scheduleTime: comps)
        #expect(store.intakeLogs.count == 1)
        #expect(store.intakeLogs.first?.status == .snoozed)

        store.upsertIntake(medicationID: med.id, status: .taken, scheduleTime: comps)
        #expect(store.intakeLogs.count == 1)
        #expect(store.intakeLogs.first?.status == .taken)
    }

    @MainActor
    @Test func clearAllRemovesEverything() {
        let store = DataStore()
        store.clearAll()
        let med = Medication(name: "Test", dose: "5mg", timesOfDay: [], remindersEnabled: false)
        store.addMedication(med)
        store.addMeasurement(Measurement(type: .weight, value: 70, date: Date()))
        store.upsertIntake(medicationID: med.id, status: .taken, scheduleTime: nil)
        #expect(!store.medications.isEmpty)
        store.clearAll()
        #expect(store.medications.isEmpty)
        #expect(store.measurements.isEmpty)
        #expect(store.intakeLogs.isEmpty)
    }

    // MARK: - AdherenceCalculator Tests

    @Test func adherencePercentWithNoMedsReturnsZero() {
        let pct = AdherenceCalculator.adherencePercent(medications: [], intakeLogs: [])
        #expect(pct == 0)
    }

    @Test func adherencePercentCountsTakenDoses() {
        let cal = Calendar.current
        let now = cal.date(from: DateComponents(year: 2026, month: 4, day: 10, hour: 20, minute: 0))!
        let med = Medication(name: "Test", dose: "5mg", startDate: cal.date(byAdding: .day, value: -3, to: now)!, timesOfDay: [DateComponents(hour: 8, minute: 0)], remindersEnabled: true)

        var logs: [IntakeLog] = []
        for offset in 0..<3 {
            let day = cal.date(byAdding: .day, value: -offset, to: now)!
            let dayStart = cal.startOfDay(for: day)
            let scheduled = cal.date(bySettingHour: 8, minute: 0, second: 0, of: dayStart)!
            logs.append(IntakeLog(medicationID: med.id, date: scheduled, status: .taken, scheduleKey: "08:00"))
        }

        let pct = AdherenceCalculator.adherencePercent(for: med.id, days: 3, medications: [med], intakeLogs: logs, now: now, calendar: cal)
        #expect(pct > 0.99)
    }

    @Test func currentStreakCountsConsecutiveTakenDays() {
        let cal = Calendar.current
        let now = cal.date(from: DateComponents(year: 2026, month: 4, day: 10, hour: 20, minute: 0))!
        let med = Medication(name: "Test", dose: "5mg", startDate: cal.date(byAdding: .day, value: -10, to: now)!, timesOfDay: [DateComponents(hour: 8, minute: 0)], remindersEnabled: true)

        var logs: [IntakeLog] = []
        for offset in 0..<5 {
            let day = cal.date(byAdding: .day, value: -offset, to: now)!
            let dayStart = cal.startOfDay(for: day)
            let scheduled = cal.date(bySettingHour: 8, minute: 0, second: 0, of: dayStart)!
            logs.append(IntakeLog(medicationID: med.id, date: scheduled, status: .taken, scheduleKey: "08:00"))
        }

        let streak = AdherenceCalculator.currentStreak(for: med.id, medications: [med], intakeLogs: logs, now: now, calendar: cal)
        #expect(streak == 5)
    }

    @Test func consecutiveMissedDaysCountsCorrectly() {
        let cal = Calendar.current
        let now = cal.date(from: DateComponents(year: 2026, month: 4, day: 10, hour: 20, minute: 0))!
        let med = Medication(name: "Test", dose: "5mg", startDate: cal.date(byAdding: .day, value: -10, to: now)!, timesOfDay: [DateComponents(hour: 8, minute: 0)], remindersEnabled: true)

        // Taken 5 days ago, then missed 4 days (yesterday through 4 days ago... wait, let me think)
        // taken 5 days ago, skipped days -4, -3, -2, -1
        let fiveDaysAgo = cal.date(byAdding: .day, value: -5, to: now)!
        let dayStart = cal.startOfDay(for: fiveDaysAgo)
        let scheduled = cal.date(bySettingHour: 8, minute: 0, second: 0, of: dayStart)!
        let logs = [
            IntakeLog(medicationID: med.id, date: scheduled, status: .taken, scheduleKey: "08:00")
        ]

        let missed = AdherenceCalculator.consecutiveMissedDays(for: med.id, medications: [med], intakeLogs: logs, now: now, calendar: cal)
        #expect(missed == 4)
    }

    @Test func adherenceSkipsPRNMedications() {
        let prn = Medication(name: "Ibuprofen", dose: "200mg", timesOfDay: [], remindersEnabled: false, isAsNeeded: true)
        let pct = AdherenceCalculator.adherencePercent(medications: [prn], intakeLogs: [])
        #expect(pct == 0) // no scheduled doses, so 0 expected
    }

    @Test func monthlyAdherenceReturnsCorrectDays() {
        let cal = Calendar.current
        let now = cal.date(from: DateComponents(year: 2026, month: 4, day: 10, hour: 20, minute: 0))!
        let med = Medication(name: "Test", dose: "5mg", startDate: cal.date(from: DateComponents(year: 2026, month: 4, day: 1))!, timesOfDay: [DateComponents(hour: 8, minute: 0)], remindersEnabled: true)

        let result = AdherenceCalculator.monthlyAdherence(for: med.id, year: 2026, month: 4, medications: [med], intakeLogs: [], now: now, calendar: cal)
        // Should have entries for April 1-10 (today), not future days
        #expect(result.count == 10)
        // All totals should be 1 (one dose per day), taken should be 0
        for (_, counts) in result {
            #expect(counts.total == 1)
            #expect(counts.taken == 0)
        }
    }

    @Test func hypertensionDraftParserAcceptsArraySummaryJSON() throws {
        let response = """
        ```JSON
        {
          "patientSummary": [
            "Morning readings may be worth discussing with your doctor.",
            "Medication decisions should be made with a licensed clinician."
          ],
          "doctorSummary": [
            "Period reviewed: last 30 days.",
            "Home BP pattern: morning values were higher than evening values."
          ],
          "questions": [
            { "question": "Should we review my morning blood pressure pattern?" },
            { "question": "Could my missed doses explain some high readings?" },
            { "question": "What should I track before the next visit?" }
          ]
        }
        ```
        """

        let draft = try HypertensionFollowUpDraftParser.parse(response)

        #expect(draft.patientSummary?.contains("Morning readings") == true)
        #expect(draft.doctorSummary?.contains("Home BP pattern") == true)
        #expect(draft.questions.count == 3)
    }

    @Test func hypertensionDraftParserAcceptsWrappedSnakeCaseJSON() throws {
        let response = """
        Here is the structured draft:
        {
          "result": {
            "patient_summary": "Your recent readings may be worth discussing with your doctor.",
            "doctor_summary": "Reviewed patient-entered home BP and adherence context.",
            "doctor_questions": [
              "Should we review the morning readings?",
              "Are the symptom notes relevant to medication timing?",
              "What readings should I bring next time?"
            ]
          }
        }
        """

        let draft = try HypertensionFollowUpDraftParser.parse(response)

        #expect(draft.patientSummary?.hasPrefix("Your recent readings") == true)
        #expect(draft.doctorSummary?.contains("home BP") == true)
        #expect(draft.questions.first == "Should we review the morning readings?")
    }

    @Test func hypertensionDraftParserFallsBackToPlainTextSections() throws {
        let response = """
        Patient summary: Morning blood pressure was higher than evening readings.
        This pattern may be worth discussing with your doctor.

        Doctor summary: Period reviewed: last 30 days.
        Patient-entered records show missed doses and symptom notes.

        Questions: Should we review my morning blood pressure pattern?
        2. Are the dizziness notes important for follow-up?
        3. What should I record before the next visit?
        """

        let draft = try HypertensionFollowUpDraftParser.parse(response)

        #expect(draft.patientSummary?.contains("Morning blood pressure") == true)
        #expect(draft.doctorSummary?.contains("Period reviewed") == true)
        #expect(draft.doctorSummary?.contains("Patient-entered records") == true)
        #expect(draft.questions.count == 3)
    }

    @Test func diabetesRuleEngineFlagsSeverelyLowGlucose() {
        let now = Date()
        let reading = Measurement(
            type: .bloodGlucose,
            value: 54,
            date: now,
            note: nil
        )

        let flags = DiabetesRuleEngine.evaluate(glucoseReadings: [reading], symptoms: [], now: now)

        #expect(flags.count == 1)
        #expect(flags.first?.sourceRule == "glucose_very_low_54")
        #expect(flags.first?.severity == .urgent)
    }

    @Test func diabetesRuleEngineFlagsHighGlucoseWithConcerningSymptoms() {
        let now = Date()
        let reading = Measurement(
            type: .bloodGlucose,
            value: 260,
            date: now,
            note: nil
        )
        let symptom = SymptomEntry(
            date: now,
            tags: ["vomiting"],
            severity: .severe,
            note: "abdominal pain"
        )

        let flags = DiabetesRuleEngine.evaluate(glucoseReadings: [reading], symptoms: [symptom], now: now)

        #expect(flags.count == 1)
        #expect(flags.first?.sourceRule == "glucose_high_240")
        #expect(flags.first?.severity == .urgent)
    }

    @MainActor
    @Test func followUpAgentCreatesBloodPressureGapTaskForHypertensionContext() {
        let store = DataStore()
        store.clearAll()
        let medication = Medication(
            name: "Amlodipine",
            dose: "5mg",
            timesOfDay: [DateComponents(hour: 8, minute: 0)],
            remindersEnabled: true,
            category: .antihypertensive
        )
        #expect(store.addMedication(medication) == nil)

        store.refreshFollowUpAgentTasks(now: Date())

        #expect(store.openFollowUpAgentTasks.contains { $0.stableKey == "measurement_gap.bp" })
    }

    @MainActor
    @Test func followUpAgentPlannerSurfacesBloodPressureGapDuringQuietStage() {
        let store = DataStore()
        store.clearAll()
        let medication = Medication(
            name: "Amlodipine",
            dose: "5mg",
            timesOfDay: [DateComponents(hour: 8, minute: 0)],
            remindersEnabled: true,
            category: .antihypertensive
        )
        #expect(store.addMedication(medication) == nil)

        let action = FollowUpAgentPlanner.nextAction(
            store: store,
            stage: .quietAccumulation,
            now: Date()
        )

        #expect(action?.target == .logMeasurement(.bloodPressure))
    }

    @MainActor
    @Test func followUpAgentPlannerHonorsDismissedStableKeys() {
        let store = DataStore()
        store.clearAll()
        let medication = Medication(
            name: "Amlodipine",
            dose: "5mg",
            timesOfDay: [DateComponents(hour: 8, minute: 0)],
            remindersEnabled: true,
            category: .antihypertensive
        )
        #expect(store.addMedication(medication) == nil)
        let now = Date()

        store.refreshFollowUpAgentTasks(now: now)
        if let item = store.openFollowUpAgentTasks.first(where: { $0.stableKey == "measurement_gap.bp" }) {
            store.dismissFollowUpAgentTask(item)
        }

        let action = FollowUpAgentPlanner.nextAction(
            store: store,
            stage: .quietAccumulation,
            now: now
        )

        #expect(action == nil)
    }

    @MainActor
    @Test func followUpAgentPlannerPrioritizesReportOnVisitDay() {
        let store = DataStore()
        store.clearAll()
        let medication = Medication(
            name: "Amlodipine",
            dose: "5mg",
            timesOfDay: [DateComponents(hour: 8, minute: 0)],
            remindersEnabled: true,
            category: .antihypertensive
        )
        let now = Date()
        let visit = DoctorVisit(scheduledDate: now)
        #expect(store.addMedication(medication) == nil)
        store.addDoctorVisit(visit)

        let action = FollowUpAgentPlanner.nextAction(
            store: store,
            stage: .visitDay(visitID: visit.id),
            now: now
        )

        #expect(action?.target == .openHypertensionReport(visit.id))
    }

    @MainActor
    @Test func followUpAgentPlannerStrengthensSparseHypertensionReportBeforeVisit() {
        let store = DataStore()
        store.clearAll()
        let now = Date()
        let visitDate = Calendar.current.date(byAdding: .day, value: 2, to: now) ?? now
        let visit = DoctorVisit(scheduledDate: visitDate)
        let medication = Medication(
            name: "Amlodipine",
            dose: "5mg",
            timesOfDay: [DateComponents(hour: 8, minute: 0)],
            remindersEnabled: true,
            category: .antihypertensive
        )
        #expect(store.addMedication(medication) == nil)
        store.addDoctorVisit(visit)
        store.addMeasurement(Measurement(
            type: .bloodPressure,
            value: 142,
            diastolic: 88,
            date: now,
            note: nil
        ))

        let readiness = FollowUpAgentPlanner.reportReadiness(
            store: store,
            domain: .hypertension,
            visitID: visit.id,
            now: now
        )
        let action = FollowUpAgentPlanner.nextAction(
            store: store,
            stage: .activePrep(visitID: visit.id, daysUntil: 2),
            now: now
        )

        #expect(readiness.missingItems.contains { $0.target == .logMeasurement(.bloodPressure) })
        #expect(action?.target == .logMeasurement(.bloodPressure))
    }

    @Test func followUpAgentTaskMergePreservesDismissedStateForStableKey() {
        let now = Date()
        let previous = FollowUpAgentTask(
            stableKey: "measurement_gap.bp",
            title: "Old",
            detail: "Old detail",
            category: .missingData,
            severity: .information,
            source: .localSummary,
            action: .logBloodPressure,
            relatedID: nil,
            generatedAt: now,
            updatedAt: now,
            status: .dismissed
        )
        let generated = FollowUpAgentTask(
            stableKey: "measurement_gap.bp",
            title: "New",
            detail: "New detail",
            category: .missingData,
            severity: .caution,
            source: .localSummary,
            action: .logBloodPressure,
            relatedID: nil,
            generatedAt: now.addingTimeInterval(60),
            updatedAt: now.addingTimeInterval(60)
        )

        let merged = FollowUpAgentTaskGenerator.merge(generated: [generated], existing: [previous], now: now.addingTimeInterval(120))

        #expect(merged.count == 1)
        #expect(merged.first?.id == previous.id)
        #expect(merged.first?.status == .dismissed)
        #expect(merged.first?.title == "New")
    }

    @Test func backupDecodesLegacyFollowUpAgentTaskKey() throws {
        struct LegacyBackup: Codable {
            let version: Int
            let date: Date
            let measurements: [ChronicCare.Measurement]
            let medications: [Medication]
            let intakeLogs: [IntakeLog]
            let agentInboxItems: [FollowUpAgentTask]
        }

        let now = Date()
        let task = FollowUpAgentTask(
            stableKey: "measurement_gap.bp",
            title: "Blood pressure record is stale",
            detail: "No recent BP readings",
            category: .missingData,
            severity: .information,
            source: .localSummary,
            action: .logBloodPressure,
            relatedID: nil,
            generatedAt: now,
            updatedAt: now
        )
        let legacy = LegacyBackup(
            version: 6,
            date: now,
            measurements: [],
            medications: [],
            intakeLogs: [],
            agentInboxItems: [task]
        )

        let data = try JSONEncoder().encode(legacy)
        let decoded = try JSONDecoder().decode(AppBackup.self, from: data)

        #expect(decoded.followUpAgentTasks?.first?.stableKey == "measurement_gap.bp")
    }

    @MainActor
    @Test func followUpAgentDoesNotAskClarificationAfterSymptomClarified() {
        let store = DataStore()
        store.clearAll()
        let now = Date()
        let symptom = SymptomEntry(
            date: now,
            tags: ["dizziness"],
            severity: .moderate,
            note: nil
        )
        store.addSymptomEntry(symptom)

        store.refreshFollowUpAgentTasks(now: now)

        let stableKey = "clarification.symptom.\(symptom.id.uuidString)"
        #expect(store.openFollowUpAgentTasks.contains {
            $0.stableKey == stableKey && $0.action == .clarifySymptom
        })

        store.upsertSymptomClarification(SymptomClarification(
            symptomEntryID: symptom.id,
            onsetDescription: "Started after breakfast",
            relationToMedication: .afterMedication,
            happenedAfterStanding: false,
            nearbyMeasurementNote: "BP 142/88",
            redFlagSigns: [],
            followUpRelevanceNote: nil
        ))
        store.refreshFollowUpAgentTasks(now: now)

        #expect(store.openFollowUpAgentTasks.contains { $0.stableKey == stableKey } == false)
    }

    @MainActor
    @Test func followUpAgentDoesNotClarifyBenignQuickFeeling() {
        let store = DataStore()
        store.clearAll()
        let now = Date()
        let symptom = SymptomEntry(
            date: now,
            tags: ["Felt okay"],
            severity: .mild,
            note: nil
        )
        store.addSymptomEntry(symptom)

        store.refreshFollowUpAgentTasks(now: now)

        #expect(store.openFollowUpAgentTasks.contains {
            $0.stableKey == "clarification.symptom.\(symptom.id.uuidString)"
        } == false)
    }

    @MainActor
    @Test func symptomClarificationUpsertReplacesSameSymptom() {
        let store = DataStore()
        store.clearAll()
        let symptomID = UUID()
        store.upsertSymptomClarification(SymptomClarification(
            symptomEntryID: symptomID,
            onsetDescription: "First",
            relationToMedication: .unknown,
            happenedAfterStanding: false,
            nearbyMeasurementNote: nil,
            redFlagSigns: [],
            followUpRelevanceNote: nil
        ))
        store.upsertSymptomClarification(SymptomClarification(
            symptomEntryID: symptomID,
            onsetDescription: "Second",
            relationToMedication: .beforeMedication,
            happenedAfterStanding: true,
            nearbyMeasurementNote: "BP 150/90",
            redFlagSigns: [.palpitations],
            followUpRelevanceNote: "Ask whether timing matters"
        ))

        #expect(store.symptomClarifications.count == 1)
        #expect(store.clarification(for: symptomID)?.onsetDescription == "Second")
        #expect(store.clarification(for: symptomID)?.relationToMedication == .beforeMedication)
        #expect(store.clarification(for: symptomID)?.happenedAfterStanding == true)
    }

    @MainActor
    @Test func hypertensionAIDraftStoreReplacesSameReportContext() {
        let store = DataStore()
        store.clearAll()
        let first = HypertensionFollowUpLLMDraft(
            patientSummary: "First patient summary",
            doctorSummary: "First doctor summary",
            questions: ["First question"]
        )
        let second = HypertensionFollowUpLLMDraft(
            patientSummary: "Second patient summary",
            doctorSummary: "Second doctor summary",
            questions: ["Second question"]
        )

        store.saveHypertensionAIDraft(
            first,
            contextKey: "hypertension.current",
            days: 30,
            dataRevision: 1
        )
        store.saveHypertensionAIDraft(
            second,
            contextKey: "hypertension.current",
            days: 30,
            dataRevision: 1
        )

        let record = store.hypertensionAIDraft(
            contextKey: "hypertension.current",
            days: 30,
            dataRevision: 1
        )

        #expect(store.hypertensionAIDrafts.count == 1)
        #expect(record?.draft == second)
    }

    @Test func hypertensionDoctorOnePageExportOmitsRawAppendix() {
        let now = Date()
        let report = HypertensionFollowUpReport(
            id: UUID(),
            generatedAt: now,
            periodStart: now.addingTimeInterval(-29 * 24 * 60 * 60),
            periodEnd: now,
            visitTitle: "Cardiology",
            bloodPressure: HypertensionFollowUpReport.BloodPressureSummary(
                totalReadings: 8,
                averageSystolic: 138,
                averageDiastolic: 86,
                morningAverageSystolic: 145,
                morningAverageDiastolic: 90,
                eveningAverageSystolic: 130,
                eveningAverageDiastolic: 82,
                aboveTargetCount: 3,
                measurementGapDays: 2,
                latestReading: "136/84 mmHg"
            ),
            adherence: HypertensionFollowUpReport.AdherenceSummary(
                medicationCount: 1,
                scheduledDoseCount: 30,
                takenDoseCount: 27,
                missedDoseCount: 3,
                adherenceRate: 0.9,
                worstMissedTimeLabel: "08:00"
            ),
            symptoms: HypertensionFollowUpReport.SymptomSummary(
                count: 1,
                severeCount: 0,
                summaries: ["Moderate: dizziness; clarified: after medication"]
            ),
            redFlags: [],
            patientInsights: [],
            doctorSummaryLines: [],
            doctorQuestions: [
                AgentQuestion(
                    prompt: "Should we review medication timing?",
                    reason: nil
                )
            ],
            rawBloodPressureRows: [
                HypertensionFollowUpReport.RawBloodPressureRow(
                    date: now,
                    systolic: 136,
                    diastolic: 84,
                    note: "raw appendix note"
                )
            ],
            disclaimer: "Safety disclaimer"
        )

        let text = HypertensionFollowUpReportTextExporter.doctorOnePageText(report)

        #expect(text.contains("Clinical snapshot"))
        #expect(text.contains("Should we review medication timing?"))
        #expect(text.contains("raw appendix note") == false)
        #expect(text.contains("Blood Pressure Appendix") == false)
    }

    @Test func diabetesDoctorOnePageExportOmitsRawAppendix() {
        let now = Date()
        let report = DiabetesFollowUpReport(
            id: UUID(),
            generatedAt: now,
            periodStart: now.addingTimeInterval(-29 * 24 * 60 * 60),
            periodEnd: now,
            visitTitle: "Endocrinology",
            glucose: DiabetesFollowUpReport.GlucoseSummary(
                totalReadings: 10,
                averageGlucose: 142,
                morningAverageGlucose: 150,
                eveningAverageGlucose: 132,
                lowReadingsCount: 1,
                veryLowReadingsCount: 0,
                highReadingsCount: 2,
                measurementGapDays: 1,
                latestReading: "138 mg/dL"
            ),
            adherence: DiabetesFollowUpReport.AdherenceSummary(
                medicationCount: 1,
                scheduledDoseCount: 30,
                takenDoseCount: 26,
                missedDoseCount: 4,
                adherenceRate: 0.86,
                worstMissedTimeLabel: "20:00"
            ),
            symptoms: DiabetesFollowUpReport.SymptomSummary(
                count: 1,
                severeCount: 0,
                summaries: ["May 6, 2026: dizziness (Moderate); clarified: nearby measurement: 68 mg/dL"]
            ),
            redFlags: [],
            patientInsights: [],
            doctorSummaryLines: [],
            doctorQuestions: [
                AgentQuestion(
                    prompt: "What glucose target range should I use at home?",
                    reason: nil
                )
            ],
            rawGlucoseRows: [
                DiabetesFollowUpReport.RawGlucoseRow(
                    date: now,
                    glucose: 138,
                    note: "raw glucose appendix note"
                )
            ],
            disclaimer: "Safety disclaimer"
        )

        let text = DiabetesFollowUpReportTextExporter.doctorOnePageText(report)

        #expect(text.contains("Clinical snapshot"))
        #expect(text.contains("What glucose target range should I use at home?"))
        #expect(text.contains("raw glucose appendix note") == false)
        #expect(text.contains("Glucose Appendix") == false)
    }

}
