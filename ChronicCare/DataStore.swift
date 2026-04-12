import Foundation
import Combine

@MainActor
final class DataStore: ObservableObject {
    @Published private(set) var measurements: [Measurement] = []
    @Published private(set) var medications: [Medication] = []
    @Published private(set) var intakeLogs: [IntakeLog] = []
    @Published private(set) var emergencyInfo: EmergencyInfo?
    @Published private(set) var caregivers: [CaregiverContact] = []

    private var cancellables: Set<AnyCancellable> = []

    private let measurementsURL: URL
    private let medicationsURL: URL
    private let intakeLogsURL: URL
    private let emergencyInfoURL: URL
    private let caregiversURL: URL
    private let goalsDefaults = UserDefaults.standard

    init() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        self.measurementsURL = docs.appendingPathComponent("measurements.json")
        self.medicationsURL = docs.appendingPathComponent("medications.json")
        self.intakeLogsURL = docs.appendingPathComponent("intake_logs.json")
        self.emergencyInfoURL = docs.appendingPathComponent("emergency_info.json")
        self.caregiversURL = docs.appendingPathComponent("caregivers.json")

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

        $caregivers
            .dropFirst()
            .debounce(for: .milliseconds(300), scheduler: RunLoop.main)
            .sink { [weak self] _ in self?.saveCaregivers() }
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
    }
    func removeMeasurement(at offsets: IndexSet) { measurements.remove(atOffsets: offsets) }

    /// Returns nil on success, or a validation error message.
    @discardableResult
    func addMedication(_ item: Medication) -> String? {
        if let error = validateMedication(item) { return error }
        medications.append(item)
        return nil
    }
    func removeMedication(at offsets: IndexSet) {
        let removedIDs = offsets.map { medications[$0].id }
        medications.remove(atOffsets: offsets)
        for id in removedIDs {
            MedicationRuleStore.shared.removeOverride(for: id)
        }
    }
    @discardableResult
    func updateMedication(_ item: Medication) -> String? {
        if let error = validateMedication(item) { return error }
        if let idx = medications.firstIndex(where: { $0.id == item.id }) {
            medications[idx] = item
        }
        return nil
    }

    private func validateMedication(_ item: Medication) -> String? {
        if case .error(let msg) = DataValidator.validateMedicationName(item.name) { return msg }
        if item.remindersEnabled && item.isAsNeeded != true {
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
        let dayEnd = cal.date(byAdding: .day, value: 1, to: dayStart)!
        intakeLogs.removeAll { log in
            log.medicationID == medicationID && log.date >= dayStart && log.date < dayEnd && log.scheduleKey == key
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

    private func resolvedScheduleKey(from scheduleTime: DateComponents?, override: String?) -> String? {
        if let override, !override.isEmpty { return override }
        guard let h = scheduleTime?.hour, let m = scheduleTime?.minute else { return nil }
        return String(format: "%02d:%02d", h, m)
    }

    /// Decrement pill supply when a dose is taken
    func decrementPills(for medicationID: UUID) {
        guard let idx = medications.firstIndex(where: { $0.id == medicationID }),
              let remaining = medications[idx].pillsRemaining else { return }
        let perDose = medications[idx].pillsPerDose ?? 1
        medications[idx].pillsRemaining = max(0, remaining - perDose)
        NotificationManager.shared.scheduleRefillReminder(for: medications[idx])
    }

    func clearAll() {
        medications.forEach {
            removeMedImage(path: $0.imagePath)
            MedicationRuleStore.shared.removeOverride(for: $0.id)
        }
        measurements.removeAll()
        medications.removeAll()
        intakeLogs.removeAll()
        emergencyInfo = nil
        caregivers.removeAll()
        saveEmergencyInfo()
    }

    // MARK: - Emergency Info
    func updateEmergencyInfo(_ info: EmergencyInfo) {
        emergencyInfo = info
        saveEmergencyInfo()
    }

    // MARK: - Caregivers
    func addCaregiver(_ c: CaregiverContact) { caregivers.append(c) }
    func removeCaregiver(at offsets: IndexSet) { caregivers.remove(atOffsets: offsets) }
    func updateCaregiver(_ c: CaregiverContact) {
        if let idx = caregivers.firstIndex(where: { $0.id == c.id }) {
            caregivers[idx] = c
        }
    }

    // MARK: - Import Backup
    func importBackup(_ backup: AppBackup) {
        medications.forEach { removeMedImage(path: $0.imagePath) }
        let restoredMedications = backup.medications.map { medication -> Medication in
            guard let path = medication.imagePath else { return medication }
            guard let data = backup.medicationImagesByPath?[path] else {
                var sanitized = medication
                sanitized.imagePath = nil
                return sanitized
            }
            restoreMedImageData(data, path: path)
            return medication
        }
        measurements = backup.measurements.sorted(by: { $0.date > $1.date })
        medications = restoredMedications
        intakeLogs = backup.intakeLogs
        emergencyInfo = backup.emergencyInfo
        saveEmergencyInfo()
        caregivers = backup.caregivers ?? []
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
            #if DEBUG
            print("Load \(label): file is not a JSON array, starting empty")
            #endif
            return []
        }
        var results: [T] = []
        for (index, element) in jsonArray.enumerated() {
            do {
                let elementData = try JSONSerialization.data(withJSONObject: element)
                let decoded = try JSONDecoder().decode(T.self, from: elementData)
                results.append(decoded)
            } catch {
                #if DEBUG
                print("Load \(label): skipped corrupt record at index \(index): \(error)")
                #endif
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
