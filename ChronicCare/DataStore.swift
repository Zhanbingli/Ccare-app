import Foundation
import Combine
import WidgetKit
import os

private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "ChronicCare", category: "DataStore")

@MainActor
final class DataStore: ObservableObject {
    @Published private(set) var measurements: [Measurement] = []
    @Published private(set) var medications: [Medication] = []
    @Published private(set) var intakeLogs: [IntakeLog] = []
    @Published private(set) var emergencyInfo: EmergencyInfo?
    @Published private(set) var caregivers: [CaregiverContact] = []
    @Published private(set) var symptomEntries: [SymptomEntry] = []
    @Published private(set) var symptomClarifications: [SymptomClarification] = []
    @Published private(set) var doctorVisits: [DoctorVisit] = []
    @Published private(set) var followUpAgentTasks: [FollowUpAgentTask] = []
    @Published private(set) var hypertensionAIDrafts: [HypertensionFollowUpAIDraftRecord] = []
    @Published private(set) var reportDataRevision: Int = 0

    private var cancellables: Set<AnyCancellable> = []

    private let measurementsURL: URL
    private let medicationsURL: URL
    private let intakeLogsURL: URL
    private let emergencyInfoURL: URL
    private let caregiversURL: URL
    private let symptomEntriesURL: URL
    private let symptomClarificationsURL: URL
    private let doctorVisitsURL: URL
    private let followUpAgentTasksURL: URL
    private let hypertensionAIDraftsURL: URL
    private let goalsDefaults = UserDefaults.standard

    init() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        self.measurementsURL = docs.appendingPathComponent("measurements.json")
        self.medicationsURL = docs.appendingPathComponent("medications.json")
        self.intakeLogsURL = docs.appendingPathComponent("intake_logs.json")
        self.emergencyInfoURL = docs.appendingPathComponent("emergency_info.json")
        self.caregiversURL = docs.appendingPathComponent("caregivers.json")
        self.symptomEntriesURL = docs.appendingPathComponent("symptom_entries.json")
        self.symptomClarificationsURL = docs.appendingPathComponent("symptom_clarifications.json")
        self.doctorVisitsURL = docs.appendingPathComponent("doctor_visits.json")
        // Keep the legacy filename so existing task state is loaded after the rename.
        self.followUpAgentTasksURL = docs.appendingPathComponent("agent_inbox_items.json")
        self.hypertensionAIDraftsURL = docs.appendingPathComponent("hypertension_ai_drafts.json")

        load()

        // Coalesce rapid changes to reduce disk I/O
        $measurements
            .dropFirst()
            .debounce(for: .milliseconds(300), scheduler: RunLoop.main)
            .sink { [weak self] _ in self?.saveMeasurements() }
            .store(in: &cancellables)

        $medications
            .dropFirst()
            .debounce(for: .milliseconds(300), scheduler: RunLoop.main)
            .sink { [weak self] _ in self?.saveMedications() }
            .store(in: &cancellables)

        $intakeLogs
            .dropFirst()
            .debounce(for: .milliseconds(300), scheduler: RunLoop.main)
            .sink { [weak self] _ in self?.saveIntakeLogs() }
            .store(in: &cancellables)

        // Update widget whenever medications or intake logs change
        Publishers.CombineLatest($medications, $intakeLogs)
            .dropFirst()
            .debounce(for: .milliseconds(500), scheduler: RunLoop.main)
            .sink { [weak self] _ in self?.updateWidgetData() }
            .store(in: &cancellables)

        $caregivers
            .dropFirst()
            .debounce(for: .milliseconds(300), scheduler: RunLoop.main)
            .sink { [weak self] _ in self?.saveCaregivers() }
            .store(in: &cancellables)

        $symptomEntries
            .dropFirst()
            .debounce(for: .milliseconds(300), scheduler: RunLoop.main)
            .sink { [weak self] _ in self?.saveSymptomEntries() }
            .store(in: &cancellables)

        $symptomClarifications
            .dropFirst()
            .debounce(for: .milliseconds(300), scheduler: RunLoop.main)
            .sink { [weak self] _ in self?.saveSymptomClarifications() }
            .store(in: &cancellables)

        $doctorVisits
            .dropFirst()
            .debounce(for: .milliseconds(300), scheduler: RunLoop.main)
            .sink { [weak self] _ in self?.saveDoctorVisits() }
            .store(in: &cancellables)

        $followUpAgentTasks
            .dropFirst()
            .debounce(for: .milliseconds(300), scheduler: RunLoop.main)
            .sink { [weak self] _ in self?.saveFollowUpAgentTasks() }
            .store(in: &cancellables)

        $hypertensionAIDrafts
            .dropFirst()
            .debounce(for: .milliseconds(300), scheduler: RunLoop.main)
            .sink { [weak self] _ in self?.saveHypertensionAIDrafts() }
            .store(in: &cancellables)
    }

    // MARK: - Public Mutations
    func addMeasurement(_ item: Measurement) {
        let item = item.clampedToNow()
        // Keep measurements sorted by date desc to avoid resorting in views
        if let idx = measurements.firstIndex(where: { item.date > $0.date }) {
            measurements.insert(item, at: idx)
        } else {
            measurements.append(item)
        }
        markReportDataChanged()
    }
    func removeMeasurement(at offsets: IndexSet) {
        measurements.remove(atOffsets: offsets)
        markReportDataChanged()
    }
    func removeMeasurement(_ item: Measurement) {
        measurements.removeAll { $0.id == item.id }
        markReportDataChanged()
    }
    func updateMeasurement(_ item: Measurement) {
        let updated = item.clampedToNow()
        measurements.removeAll { $0.id == updated.id }
        if let idx = measurements.firstIndex(where: { updated.date > $0.date }) {
            measurements.insert(updated, at: idx)
        } else {
            measurements.append(updated)
        }
        markReportDataChanged()
    }

    /// Returns nil on success, or a validation error message.
    @discardableResult
    func addMedication(_ item: Medication) -> String? {
        if let error = validateMedication(item) { return error }
        medications.append(item)
        markReportDataChanged()
        return nil
    }
    func removeMedication(at offsets: IndexSet) {
        let removedIDs = offsets.map { medications[$0].id }
        medications.remove(atOffsets: offsets)
        for id in removedIDs {
            MedicationRuleStore.shared.removeOverride(for: id)
            AdaptiveReminderPreferenceStore.clearAll(for: id)
        }
        markReportDataChanged()
    }
    @discardableResult
    func updateMedication(_ item: Medication) -> String? {
        if let error = validateMedication(item) { return error }
        if let idx = medications.firstIndex(where: { $0.id == item.id }) {
            let oldTimes = Set(medications[idx].timesOfDay.compactMap { comps -> String? in
                guard let h = comps.hour, let m = comps.minute else { return nil }
                return String(format: "%02d:%02d", h, m)
            })
            let newTimes = Set(item.timesOfDay.compactMap { comps -> String? in
                guard let h = comps.hour, let m = comps.minute else { return nil }
                return String(format: "%02d:%02d", h, m)
            })
            // Reset snooze counts for removed schedule times
            for removed in oldTimes.subtracting(newTimes) {
                let parts = removed.split(separator: ":")
                if parts.count == 2, let h = Int(parts[0]), let m = Int(parts[1]) {
                    var comps = DateComponents(); comps.hour = h; comps.minute = m
                    NotificationManager.shared.resetSnoozeCount(for: item.id, scheduleTime: comps)
                }
            }
            medications[idx] = item
            markReportDataChanged()
        }
        return nil
    }

    private func validateMedication(_ item: Medication) -> String? {
        if case .error(let msg) = DataValidator.validateMedicationName(item.name) { return msg }
        if item.isAsNeeded != true {
            if case .error(let msg) = DataValidator.validateMedicationSchedule(item.timesOfDay) { return msg }
        }
        if let remaining = item.pillsRemaining, remaining < 0 { return NSLocalizedString("Pills remaining cannot be negative.", comment: "") }
        return nil
    }
    // Ensure one final status per day per medication per scheduleKey.
    // Callers can override the key for PRN logging where multiple same-day entries are valid.
    func upsertIntake(
        medicationID: UUID,
        status: IntakeStatus,
        scheduleTime: DateComponents?,
        at date: Date = Date(),
        scheduledDate: Date? = nil,
        recordedAt: Date = Date(),
        scheduleKeyOverride: String? = nil,
        note: String? = nil
    ) {
        let key = resolvedScheduleKey(from: scheduleTime, override: scheduleKeyOverride)
        let effectiveScheduledDate = scheduledDate ?? inferredScheduledDate(from: scheduleTime, relativeTo: date)
        let effectiveDate = effectiveScheduledDate ?? date
        let cal = Calendar.current
        let dayStart = cal.startOfDay(for: effectiveDate)
        guard let dayEnd = cal.date(byAdding: .day, value: 1, to: dayStart) else { return }
        let replacedLogs = intakeLogs.filter {
            isMatchingIntakeLog($0, medicationID: medicationID, dayStart: dayStart, dayEnd: dayEnd, scheduleKey: key)
        }
        let hadTakenLog = replacedLogs.contains { $0.status == .taken }
        intakeLogs.removeAll {
            isMatchingIntakeLog($0, medicationID: medicationID, dayStart: dayStart, dayEnd: dayEnd, scheduleKey: key)
        }
        let trimmedNote = note?.trimmingCharacters(in: .whitespacesAndNewlines)
        intakeLogs.append(
            IntakeLog(
                medicationID: medicationID,
                date: effectiveDate,
                status: status,
                scheduleKey: key,
                note: trimmedNote?.isEmpty == true ? nil : trimmedNote,
                scheduledDate: effectiveScheduledDate,
                recordedAt: recordedAt
            )
        )
        reconcilePillSupplyAfterIntakeChange(medicationID: medicationID, oldHadTakenLog: hadTakenLog, newStatus: status)
        markReportDataChanged()

        // Behavioral feedback — fire after state is committed
        let medName = medications.first(where: { $0.id == medicationID })?.name ?? ""
        if status == .taken {
            NotificationManager.shared.resetSnoozeCount(for: medicationID, scheduleTime: scheduleTime)
            let streak = currentStreak(for: medicationID)
            NotificationManager.shared.sendStreakMilestone(streak: streak, medicationName: medName)
        } else if status == .skipped {
            let missed = consecutiveMissedDays(for: medicationID)
            NotificationManager.shared.sendMissWarning(for: medicationID, missedDays: missed, medicationName: medName)
            // Caregiver notification when missed 2+ days and caregivers have notifyOnMiss
            if missed >= 2 {
                let notifyCaregivers = caregivers.filter { $0.notifyOnMiss }
                for cg in notifyCaregivers {
                    NotificationManager.shared.sendCaregiverReminder(caregiverID: cg.id, caregiverName: cg.name, medicationName: medName, missedDays: missed)
                }
            }
        }
    }

    func removeIntakeLog(_ log: IntakeLog) {
        let removedLogs = intakeLogs.filter { $0.id == log.id }
        guard !removedLogs.isEmpty else { return }
        intakeLogs.removeAll { $0.id == log.id }
        if removedLogs.contains(where: { $0.status == .taken }) {
            restorePills(for: log.medicationID)
        }
        markReportDataChanged()
    }

    private func isMatchingIntakeLog(
        _ log: IntakeLog,
        medicationID: UUID,
        dayStart: Date,
        dayEnd: Date,
        scheduleKey: String?
    ) -> Bool {
        log.medicationID == medicationID && log.date >= dayStart && log.date < dayEnd && log.scheduleKey == scheduleKey
    }

    private func reconcilePillSupplyAfterIntakeChange(
        medicationID: UUID,
        oldHadTakenLog: Bool,
        newStatus: IntakeStatus
    ) {
        if oldHadTakenLog && newStatus != .taken {
            restorePills(for: medicationID)
        } else if !oldHadTakenLog && newStatus == .taken {
            decrementPills(for: medicationID)
        }
    }

    private func resolvedScheduleKey(from scheduleTime: DateComponents?, override: String?) -> String? {
        if let override, !override.isEmpty { return override }
        guard let h = scheduleTime?.hour, let m = scheduleTime?.minute else { return nil }
        return String(format: "%02d:%02d", h, m)
    }

    /// Record a taken dose: logs intake and decrements pill supply atomically.
    func recordTakenDose(
        medicationID: UUID,
        scheduleTime: DateComponents?,
        at date: Date = Date(),
        scheduledDate: Date? = nil,
        recordedAt: Date = Date(),
        scheduleKeyOverride: String? = nil,
        note: String? = nil
    ) {
        upsertIntake(
            medicationID: medicationID,
            status: .taken,
            scheduleTime: scheduleTime,
            at: date,
            scheduledDate: scheduledDate,
            recordedAt: recordedAt,
            scheduleKeyOverride: scheduleKeyOverride,
            note: note
        )
    }

    /// Captures what a single "taken" log replaced, so it can be reversed
    /// exactly — restoring any prior log and pill supply.
    struct IntakeUndoToken: Identifiable {
        let id = UUID()
        let medicationName: String
        let wasDuplicate: Bool
        let newLogID: UUID
        let replacedLogs: [IntakeLog]
    }

    /// Records a taken dose and returns a token to undo it. The token snapshots
    /// the logs `upsertIntake` removed (one final status per med/day/key) so a
    /// later revert can put them back rather than just deleting.
    func recordTakenDoseUndoable(
        medicationID: UUID,
        scheduleTime: DateComponents?,
        scheduledDate: Date? = nil,
        note: String? = nil
    ) -> IntakeUndoToken? {
        let priorLogs = intakeLogs
        let priorIDs = Set(priorLogs.map(\.id))
        recordTakenDose(
            medicationID: medicationID,
            scheduleTime: scheduleTime,
            scheduledDate: scheduledDate,
            note: note
        )
        let afterIDs = Set(intakeLogs.map(\.id))
        guard let newLog = intakeLogs.first(where: { !priorIDs.contains($0.id) }) else { return nil }
        let replaced = priorLogs.filter { !afterIDs.contains($0.id) }
        let name = medications.first(where: { $0.id == medicationID })?.name ?? ""
        return IntakeUndoToken(
            medicationName: name,
            wasDuplicate: replaced.contains { $0.status == .taken },
            newLogID: newLog.id,
            replacedLogs: replaced
        )
    }

    /// Reverses a `recordTakenDoseUndoable`: drops the new log (restoring pills
    /// via removeIntakeLog) and re-applies whatever it replaced.
    func revertIntake(_ token: IntakeUndoToken) {
        if let newLog = intakeLogs.first(where: { $0.id == token.newLogID }) {
            removeIntakeLog(newLog)
        }
        for log in token.replacedLogs {
            intakeLogs.append(log)
            if log.status == .taken { decrementPills(for: log.medicationID) }
        }
        markReportDataChanged()
    }

    /// Decrement pill supply when a dose is taken
    func decrementPills(for medicationID: UUID) {
        guard let idx = medications.firstIndex(where: { $0.id == medicationID }),
              let remaining = medications[idx].pillsRemaining else { return }
        let perDose = medications[idx].pillsPerDose ?? 1
        medications[idx].pillsRemaining = max(0, remaining - perDose)
        NotificationManager.shared.scheduleRefillReminder(for: medications[idx])
    }

    func restorePills(for medicationID: UUID) {
        guard let idx = medications.firstIndex(where: { $0.id == medicationID }),
              let remaining = medications[idx].pillsRemaining else { return }
        let perDose = medications[idx].pillsPerDose ?? 1
        medications[idx].pillsRemaining = max(0, remaining + perDose)
        NotificationManager.shared.scheduleRefillReminder(for: medications[idx])
    }

    // MARK: - Widget

    func updateWidgetData() {
        let now = Date()
        let cal = Calendar.current
        let todayStart = cal.startOfDay(for: now)
        guard let todayEnd = cal.date(byAdding: .day, value: 1, to: todayStart) else { return }

        let scheduled = medications.filter { $0.remindersEnabled && $0.isAsNeeded != true }
        var allDoses: [WidgetDoseEntry] = []
        var takenCount = 0
        var totalCount = 0

        for med in scheduled {
            for comps in med.timesOfDay {
                guard let h = comps.hour, let m = comps.minute,
                      let schedDate = cal.date(bySettingHour: h, minute: m, second: 0, of: now),
                      med.isDoseActive(on: schedDate) else { continue }

                totalCount += 1

                let key = String(format: "%02d:%02d", h, m)
                let log = intakeLogs.first { log in
                    log.medicationID == med.id
                        && log.date >= todayStart
                        && log.date < todayEnd
                        && log.scheduleKey == key
                }

                if log?.status == .taken {
                    takenCount += 1
                    continue
                }
                if log?.status == .skipped { continue }

                allDoses.append(WidgetDoseEntry(
                    medicationName: med.name,
                    dose: med.dose,
                    scheduledTime: schedDate,
                    medicationID: med.id
                ))
            }
        }

        allDoses.sort { $0.scheduledTime < $1.scheduledTime }

        // If no remaining doses today, look at tomorrow
        if allDoses.isEmpty {
            if let tomorrow = cal.date(byAdding: .day, value: 1, to: todayStart) {
                for med in scheduled {
                    for comps in med.timesOfDay {
                        guard let h = comps.hour, let m = comps.minute,
                              let schedDate = cal.date(bySettingHour: h, minute: m, second: 0, of: tomorrow),
                              med.isDoseActive(on: schedDate) else { continue }
                        allDoses.append(WidgetDoseEntry(
                            medicationName: med.name,
                            dose: med.dose,
                            scheduledTime: schedDate,
                            medicationID: med.id
                        ))
                    }
                }
                allDoses.sort { $0.scheduledTime < $1.scheduledTime }
            }
        }

        let data = WidgetData(
            nextDose: allDoses.first,
            upcomingDoses: Array(allDoses.prefix(5)),
            todayTaken: takenCount,
            todayTotal: totalCount,
            lastUpdated: now
        )
        WidgetDataProvider.write(data)
        WidgetCenter.shared.reloadAllTimelines()
    }

    /// Sync all notification schedules and update the badge in one call.
    func syncNotifications(now: Date = Date()) {
        NotificationManager.shared.syncAll(medications: medications, intakeLogs: intakeLogs, now: now)
        NotificationManager.shared.syncVisitPrepReminders(visits: doctorVisits, now: now)
        NotificationManager.shared.updateBadge(store: self)
    }

    func clearAll() {
        medications.forEach {
            deleteMedicationImage(path: $0.imagePath)
            MedicationRuleStore.shared.removeOverride(for: $0.id)
            AdaptiveReminderPreferenceStore.clearAll(for: $0.id)
        }
        measurements.removeAll()
        medications.removeAll()
        intakeLogs.removeAll()
        emergencyInfo = nil
        caregivers.removeAll()
        symptomEntries.removeAll()
        symptomClarifications.removeAll()
        doctorVisits.removeAll()
        followUpAgentTasks.removeAll()
        hypertensionAIDrafts.removeAll()
        saveEmergencyInfo()
        saveSymptomClarifications()
        saveDoctorVisits()
        saveFollowUpAgentTasks()
        saveHypertensionAIDrafts()
        markReportDataChanged()
    }

    // MARK: - Emergency Info
    func updateEmergencyInfo(_ info: EmergencyInfo) {
        emergencyInfo = info
        saveEmergencyInfo()
        markReportDataChanged()
    }

    // MARK: - Caregivers
    func addCaregiver(_ c: CaregiverContact) { caregivers.append(c) }
    func removeCaregiver(at offsets: IndexSet) { caregivers.remove(atOffsets: offsets) }
    func updateCaregiver(_ c: CaregiverContact) {
        if let idx = caregivers.firstIndex(where: { $0.id == c.id }) {
            caregivers[idx] = c
        }
    }

    // MARK: - Symptom Entries
    func addSymptomEntry(_ entry: SymptomEntry) {
        // Keep sorted by date desc so the consultation view doesn't need to resort.
        if let idx = symptomEntries.firstIndex(where: { entry.date > $0.date }) {
            symptomEntries.insert(entry, at: idx)
        } else {
            symptomEntries.append(entry)
        }
        markReportDataChanged()
    }
    func removeSymptomEntry(at offsets: IndexSet) {
        let removedIDs = offsets.map { symptomEntries[$0].id }
        symptomEntries.remove(atOffsets: offsets)
        symptomClarifications.removeAll { removedIDs.contains($0.symptomEntryID) }
        markReportDataChanged()
    }
    func removeSymptomEntry(_ entry: SymptomEntry) {
        symptomEntries.removeAll { $0.id == entry.id }
        symptomClarifications.removeAll { $0.symptomEntryID == entry.id }
        markReportDataChanged()
    }
    func updateSymptomEntry(_ entry: SymptomEntry) {
        if let idx = symptomEntries.firstIndex(where: { $0.id == entry.id }) {
            symptomEntries[idx] = entry
            markReportDataChanged()
        }
    }

    // MARK: - Symptom Clarifications
    func clarification(for symptomEntryID: UUID) -> SymptomClarification? {
        symptomClarifications
            .filter { $0.symptomEntryID == symptomEntryID }
            .sorted { $0.updatedAt > $1.updatedAt }
            .first
    }

    func upsertSymptomClarification(_ clarification: SymptomClarification) {
        var updated = clarification
        updated.updatedAt = Date()
        symptomClarifications.removeAll { $0.symptomEntryID == updated.symptomEntryID }
        symptomClarifications.insert(updated, at: 0)
        markReportDataChanged()
    }

    // MARK: - Doctor Visits
    var upcomingDoctorVisits: [DoctorVisit] {
        doctorVisits
            .filter { $0.isUpcoming() }
            .sorted { $0.scheduledDate < $1.scheduledDate }
    }

    var overdueDoctorVisits: [DoctorVisit] {
        doctorVisits
            .filter { $0.isOverdue() }
            .sorted { $0.scheduledDate > $1.scheduledDate }
    }

    var completedDoctorVisits: [DoctorVisit] {
        doctorVisits
            .filter(\.isCompleted)
            .sorted { ($0.completedDate ?? $0.scheduledDate) > ($1.completedDate ?? $1.scheduledDate) }
    }

    var nextDoctorVisit: DoctorVisit? {
        upcomingDoctorVisits.first ?? overdueDoctorVisits.first
    }

    func addDoctorVisit(_ visit: DoctorVisit) {
        doctorVisits.append(visit)
        sortDoctorVisits()
        NotificationManager.shared.syncVisitPrepReminders(visits: doctorVisits)
        markReportDataChanged()
    }

    func updateDoctorVisit(_ visit: DoctorVisit) {
        if let idx = doctorVisits.firstIndex(where: { $0.id == visit.id }) {
            doctorVisits[idx] = visit
            sortDoctorVisits()
            NotificationManager.shared.syncVisitPrepReminders(visits: doctorVisits)
            markReportDataChanged()
        }
    }

    func removeDoctorVisit(at offsets: IndexSet) {
        let removedIDs = offsets.map { doctorVisits[$0].id }
        doctorVisits.remove(atOffsets: offsets)
        for id in removedIDs {
            NotificationManager.shared.cancelVisitPrepReminder(for: id)
        }
        NotificationManager.shared.syncVisitPrepReminders(visits: doctorVisits)
        markReportDataChanged()
    }

    func removeDoctorVisit(_ visit: DoctorVisit) {
        doctorVisits.removeAll { $0.id == visit.id }
        NotificationManager.shared.cancelVisitPrepReminder(for: visit.id)
        NotificationManager.shared.syncVisitPrepReminders(visits: doctorVisits)
        markReportDataChanged()
    }

    func completeDoctorVisit(_ visit: DoctorVisit, completedDate: Date = Date()) {
        var updated = visit
        updated.completedDate = completedDate
        updateDoctorVisit(updated)
    }

    func hasDoctorVisit(on date: Date, calendar: Calendar = .current) -> Bool {
        let day = calendar.startOfDay(for: date)
        return doctorVisits.contains { calendar.startOfDay(for: $0.scheduledDate) == day }
    }

    private func sortDoctorVisits() {
        doctorVisits.sort { lhs, rhs in
            if lhs.isCompleted != rhs.isCompleted { return !lhs.isCompleted }
            return lhs.scheduledDate < rhs.scheduledDate
        }
    }

    // MARK: - AI Follow-up Agent
    var openFollowUpAgentTasks: [FollowUpAgentTask] {
        followUpAgentTasks.filter(\.isOpen)
    }

    func refreshFollowUpAgentTasks(now: Date = Date()) {
        let generated = FollowUpAgentTaskGenerator.generate(store: self, now: now)
        followUpAgentTasks = FollowUpAgentTaskGenerator.merge(generated: generated, existing: followUpAgentTasks, now: now)
    }

    func dismissFollowUpAgentTask(_ item: FollowUpAgentTask) {
        guard let idx = followUpAgentTasks.firstIndex(where: { $0.id == item.id }) else { return }
        followUpAgentTasks[idx].status = .dismissed
    }

    func reopenFollowUpAgentTask(_ item: FollowUpAgentTask) {
        guard let idx = followUpAgentTasks.firstIndex(where: { $0.id == item.id }) else { return }
        followUpAgentTasks[idx].status = .open
    }

    // MARK: - AI Drafts
    func hypertensionAIDraft(contextKey: String, days: Int, dataRevision: Int) -> HypertensionFollowUpAIDraftRecord? {
        let key = HypertensionFollowUpAIDraftRecord.stableKey(
            contextKey: contextKey,
            days: days,
            dataRevision: dataRevision
        )
        return hypertensionAIDrafts.first { $0.stableKey == key }
    }

    func saveHypertensionAIDraft(
        _ draft: HypertensionFollowUpLLMDraft,
        contextKey: String,
        days: Int,
        dataRevision: Int,
        generatedAt: Date = Date()
    ) {
        let record = HypertensionFollowUpAIDraftRecord(
            contextKey: contextKey,
            days: days,
            dataRevision: dataRevision,
            draft: draft,
            generatedAt: generatedAt
        )
        hypertensionAIDrafts.removeAll { $0.stableKey == record.stableKey }
        hypertensionAIDrafts.insert(record, at: 0)
        if hypertensionAIDrafts.count > 20 {
            hypertensionAIDrafts = Array(hypertensionAIDrafts.prefix(20))
        }
    }

    // MARK: - Import Backup
    func importBackup(_ backup: AppBackup) {
        medications.forEach { deleteMedicationImage(path: $0.imagePath) }
        let restoredMedications = backup.medications.map { medication -> Medication in
            guard let path = medication.imagePath else { return medication }
            guard let data = backup.medicationImagesByPath?[path] else {
                var sanitized = medication
                sanitized.imagePath = nil
                return sanitized
            }
            let restored = restoreMedicationImageData(data, path: path)
            if !restored {
                var sanitized = medication
                sanitized.imagePath = nil
                return sanitized
            }
            return medication
        }
        measurements = backup.measurements.sorted(by: { $0.date > $1.date })
        medications = restoredMedications
        intakeLogs = backup.intakeLogs
        emergencyInfo = backup.emergencyInfo
        saveEmergencyInfo()
        caregivers = backup.caregivers ?? []
        symptomEntries = (backup.symptomEntries ?? []).sorted(by: { $0.date > $1.date })
        symptomClarifications = backup.symptomClarifications ?? []
        doctorVisits = (backup.doctorVisits ?? []).sorted(by: { $0.scheduledDate < $1.scheduledDate })
        followUpAgentTasks = backup.followUpAgentTasks ?? []
        hypertensionAIDrafts = backup.hypertensionAIDrafts ?? []
        markReportDataChanged()
    }

    // MARK: - Load/Save
    private func load() {
        self.measurements = loadResilient(from: measurementsURL, label: "measurements").sorted(by: { $0.date > $1.date })
        self.medications = loadResilient(from: medicationsURL, label: "medications")
        self.intakeLogs = loadResilient(from: intakeLogsURL, label: "intake logs")
        do {
            let data = try Data(contentsOf: emergencyInfoURL)
            self.emergencyInfo = try JSONDecoder().decode(EmergencyInfo.self, from: data)
        } catch { /* first launch or no data */ }
        self.caregivers = loadResilient(from: caregiversURL, label: "caregivers")
        self.symptomEntries = loadResilient(from: symptomEntriesURL, label: "symptom entries").sorted(by: { $0.date > $1.date })
        self.symptomClarifications = loadResilient(from: symptomClarificationsURL, label: "symptom clarifications")
        self.doctorVisits = loadResilient(from: doctorVisitsURL, label: "doctor visits").sorted(by: { $0.scheduledDate < $1.scheduledDate })
        self.followUpAgentTasks = loadResilient(from: followUpAgentTasksURL, label: "follow-up agent tasks")
        self.hypertensionAIDrafts = loadResilient(from: hypertensionAIDraftsURL, label: "hypertension AI drafts")
        updateWidgetData()
    }

    /// Decode an array resiliently: skip individual bad records instead of losing all data.
    private func loadResilient<T: Decodable>(from url: URL, label: String) -> [T] {
        guard let data = try? Data(contentsOf: url) else { return [] }
        // Fast path: try decoding the full array first
        if let decoded = try? JSONDecoder().decode([T].self, from: data) {
            return decoded
        }
        // Slow path: decode element-by-element, skipping corrupt records
        guard let jsonArray = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            logger.warning("Load \(label): file is not a JSON array, starting empty")
            return []
        }
        var results: [T] = []
        for (index, element) in jsonArray.enumerated() {
            do {
                let elementData = try JSONSerialization.data(withJSONObject: element)
                let decoded = try JSONDecoder().decode(T.self, from: elementData)
                results.append(decoded)
            } catch {
                logger.warning("Load \(label): skipped corrupt record at index \(index): \(error.localizedDescription)")
            }
        }
        return results
    }

    private func saveMeasurements() {
        let snapshot = measurements
        persist(snapshot, to: measurementsURL, label: "measurements")
    }

    private func saveMedications() {
        let snapshot = medications
        persist(snapshot, to: medicationsURL, label: "medications")
    }

    private func saveEmergencyInfo() {
        if let info = emergencyInfo {
            persist(info, to: emergencyInfoURL, label: "emergency info")
        } else {
            try? FileManager.default.removeItem(at: emergencyInfoURL)
        }
    }

    private func saveCaregivers() {
        let snapshot = caregivers
        persist(snapshot, to: caregiversURL, label: "caregivers")
    }

    private func saveSymptomEntries() {
        let snapshot = symptomEntries
        persist(snapshot, to: symptomEntriesURL, label: "symptom entries")
    }

    private func saveSymptomClarifications() {
        let snapshot = symptomClarifications
        persist(snapshot, to: symptomClarificationsURL, label: "symptom clarifications")
    }

    private func saveDoctorVisits() {
        let snapshot = doctorVisits
        persist(snapshot, to: doctorVisitsURL, label: "doctor visits")
    }

    private func saveFollowUpAgentTasks() {
        let snapshot = followUpAgentTasks
        persist(snapshot, to: followUpAgentTasksURL, label: "follow-up agent tasks")
    }

    private func saveHypertensionAIDrafts() {
        let snapshot = hypertensionAIDrafts
        persist(snapshot, to: hypertensionAIDraftsURL, label: "hypertension AI drafts")
    }

    private func saveIntakeLogs() {
        let snapshot = intakeLogs
        persist(snapshot, to: intakeLogsURL, label: "intake logs")
    }

    // Serial writer ensures writes for the same URL are ordered correctly
    private static let writer = SerialFileWriter()

    private func persist<T: Encodable>(_ value: T, to url: URL, label: String) {
        let payload = value
        Task {
            await Self.writer.write(payload, to: url, label: label)
        }
    }

    private func markReportDataChanged() {
        reportDataRevision &+= 1
    }

    private func inferredScheduledDate(from scheduleTime: DateComponents?, relativeTo date: Date) -> Date? {
        guard let hour = scheduleTime?.hour, let minute = scheduleTime?.minute else { return nil }
        return Calendar.current.date(bySettingHour: hour, minute: minute, second: 0, of: date)
    }

    // MARK: - Stats (delegated to AdherenceCalculator)

    func weeklyAdherence(for medicationID: UUID? = nil, endingOn endDate: Date = Date()) -> [(Date, Double)] {
        AdherenceCalculator.weeklyAdherence(for: medicationID, endingOn: endDate, medications: medications, intakeLogs: intakeLogs)
    }

    func monthlyAdherence(for medicationID: UUID? = nil, year: Int, month: Int) -> [Date: (taken: Int, total: Int)] {
        AdherenceCalculator.monthlyAdherence(for: medicationID, year: year, month: month, medications: medications, intakeLogs: intakeLogs)
    }

    func intakeLogs(for date: Date, medicationID: UUID? = nil) -> [IntakeLog] {
        AdherenceCalculator.intakeLogs(for: date, medicationID: medicationID, intakeLogs: intakeLogs)
    }

    func adherencePercent(for medicationID: UUID? = nil, days: Int = 30) -> Double {
        AdherenceCalculator.adherencePercent(for: medicationID, days: days, medications: medications, intakeLogs: intakeLogs)
    }

    func currentStreak(for medicationID: UUID) -> Int {
        AdherenceCalculator.currentStreak(for: medicationID, medications: medications, intakeLogs: intakeLogs)
    }

    func consecutiveMissedDays(for medicationID: UUID) -> Int {
        AdherenceCalculator.consecutiveMissedDays(for: medicationID, medications: medications, intakeLogs: intakeLogs)
    }

    // MARK: - Goal Ranges (UserDefaults-backed)
    private func readDouble(_ key: String) -> Double? {
        if goalsDefaults.object(forKey: key) == nil { return nil }
        return goalsDefaults.double(forKey: key)
    }

    func customGoalRange(for type: MeasurementType) -> ClosedRange<Double>? {
        switch type {
        case .bloodGlucose:
            let low = readDouble("goals.glucose.low") ?? 70
            let high = readDouble("goals.glucose.high") ?? 180
            return low...high
        case .heartRate:
            let low = readDouble("goals.hr.low") ?? 50
            let high = readDouble("goals.hr.high") ?? 110
            return low...high
        case .weight:
            return nil
        case .bloodPressure:
            return nil
        }
    }

    func bpThresholds() -> (systolicHigh: Double, diastolicHigh: Double) {
        let s = readDouble("goals.bp.sysHigh") ?? 140
        let d = readDouble("goals.bp.diaHigh") ?? 90
        return (s, d)
    }
}
