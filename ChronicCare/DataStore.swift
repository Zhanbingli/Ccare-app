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
        // Keep measurements sorted by date desc to avoid resorting in views
        if let idx = measurements.firstIndex(where: { item.date > $0.date }) {
            measurements.insert(item, at: idx)
        } else {
            measurements.append(item)
        }
    }
    func removeMeasurement(at offsets: IndexSet) { measurements.remove(atOffsets: offsets) }

    func addMedication(_ item: Medication) { medications.append(item) }
    func removeMedication(at offsets: IndexSet) {
        let removedIDs = offsets.map { medications[$0].id }
        medications.remove(atOffsets: offsets)
        for id in removedIDs {
            MedicationRuleStore.shared.removeOverride(for: id)
        }
    }
    func updateMedication(_ item: Medication) {
        if let idx = medications.firstIndex(where: { $0.id == item.id }) {
            medications[idx] = item
        }
    }
    // Ensure one final status per day per medication per scheduleKey
    func upsertIntake(medicationID: UUID, status: IntakeStatus, scheduleTime: DateComponents?, at date: Date = Date(), note: String? = nil) {
        var key: String? = nil
        if let h = scheduleTime?.hour, let m = scheduleTime?.minute {
            key = String(format: "%02d:%02d", h, m)
        }
        let cal = Calendar.current
        let dayStart = cal.startOfDay(for: date)
        let dayEnd = cal.date(byAdding: .day, value: 1, to: dayStart)!
        intakeLogs.removeAll { log in
            log.medicationID == medicationID && log.date >= dayStart && log.date < dayEnd && log.scheduleKey == key
        }
        let trimmedNote = note?.trimmingCharacters(in: .whitespacesAndNewlines)
        intakeLogs.append(IntakeLog(medicationID: medicationID, date: date, status: status, scheduleKey: key, note: trimmedNote?.isEmpty == true ? nil : trimmedNote))

        // Behavioral feedback — fire after state is committed
        let medName = medications.first(where: { $0.id == medicationID })?.name ?? ""
        if status == .taken {
            NotificationManager.shared.resetSnoozeCount(for: medicationID, scheduleTime: scheduleTime)
            let streak = currentStreak(for: medicationID)
            NotificationManager.shared.sendStreakMilestone(streak: streak, medicationName: medName)
        } else if status == .skipped {
            let missed = consecutiveMissedDays(for: medicationID)
            NotificationManager.shared.sendMissWarning(for: medicationID, missedDays: missed, medicationName: medName)
        }
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
        measurements.removeAll()
        medications.removeAll()
        intakeLogs.removeAll()
        emergencyInfo = nil
        caregivers.removeAll()
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
        measurements = backup.measurements.sorted(by: { $0.date > $1.date })
        medications = backup.medications
        intakeLogs = backup.intakeLogs
        if let info = backup.emergencyInfo { emergencyInfo = info; saveEmergencyInfo() }
        if let cg = backup.caregivers { caregivers = cg }
    }

    // MARK: - Load/Save
    private func load() {
        do {
            let data = try Data(contentsOf: measurementsURL)
            let decoded = try JSONDecoder().decode([Measurement].self, from: data)
            self.measurements = decoded.sorted(by: { $0.date > $1.date })
        } catch {
            // First launch or decode error; start empty but log
            if (error as NSError).domain != NSCocoaErrorDomain { print("Load measurements error: \(error)") }
        }
        do {
            let data = try Data(contentsOf: medicationsURL)
            let decoded = try JSONDecoder().decode([Medication].self, from: data)
            self.medications = decoded
        } catch {
            if (error as NSError).domain != NSCocoaErrorDomain { print("Load medications error: \(error)") }
        }
        do {
            let data = try Data(contentsOf: intakeLogsURL)
            let decoded = try JSONDecoder().decode([IntakeLog].self, from: data)
            self.intakeLogs = decoded
        } catch {
            if (error as NSError).domain != NSCocoaErrorDomain { print("Load intake logs error: \(error)") }
        }
        do {
            let data = try Data(contentsOf: emergencyInfoURL)
            self.emergencyInfo = try JSONDecoder().decode(EmergencyInfo.self, from: data)
        } catch { /* first launch or no data */ }
        do {
            let data = try Data(contentsOf: caregiversURL)
            self.caregivers = try JSONDecoder().decode([CaregiverContact].self, from: data)
        } catch { /* first launch or no data */ }
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

    // Background persistence to avoid blocking the main thread
    private func persist<T: Encodable>(_ value: T, to url: URL, label: String) {
        let payload = value
        Task.detached(priority: .utility) {
            do {
                let encoder = JSONEncoder()
                let data = try encoder.encode(payload)
                do {
                    try data.write(to: url, options: [.atomic, .completeFileProtection])
                } catch {
                    // Fallback when file protection blocks writes (e.g., device locked)
                    try data.write(to: url, options: [.atomic])
                }
                try? (url as NSURL).setResourceValue(true, forKey: .isExcludedFromBackupKey)
            } catch {
                print("Failed to save \(label): \(error)")
            }
        }
    }

    // MARK: - Stats
    func weeklyAdherence(for medicationID: UUID? = nil, endingOn endDate: Date = Date()) -> [(Date, Double)] {
        let cal = Calendar.current
        let endDay = cal.startOfDay(for: endDate)
        let startDay = cal.date(byAdding: .day, value: -6, to: endDay)!

        // Pre-slice logs to last 7 days and (optionally) specific medication
        let logsWindow = intakeLogs.filter { log in
            let day = cal.startOfDay(for: log.date)
            guard day >= startDay && day <= endDay else { return false }
            if let mid = medicationID { return log.medicationID == mid }
            return true
        }

        // Helper: latest log status for a given day/med/scheduleKey
        func latestStatus(on day: Date, medID: UUID, scheduleKey: String?, medTimesCount: Int) -> IntakeStatus? {
            // Prefer exact scheduleKey match; if med has only one time, allow nil as fallback
            let dayStart = day
            let dayEnd = cal.date(byAdding: .day, value: 1, to: dayStart)!
            let candidates = logsWindow.filter { log in
                guard log.medicationID == medID && log.date >= dayStart && log.date < dayEnd else { return false }
                if let key = scheduleKey {
                    return log.scheduleKey == key || (medTimesCount == 1 && log.scheduleKey == nil)
                } else {
                    // No schedule key provided: only accept nil logs (rare)
                    return log.scheduleKey == nil
                }
            }.sorted(by: { $0.date > $1.date })
            return candidates.first?.status
        }

        // Enumerate expected schedules per day based on medication times
        let meds: [Medication] = {
            if let mid = medicationID { return medications.filter { $0.id == mid } }
            return medications
        }()

        let now = Date()
        var byDay: [Date: (taken: Int, total: Int)] = [:]
        for i in 0..<7 {
            let day = cal.date(byAdding: .day, value: i, to: startDay)!
            let dayKey = cal.startOfDay(for: day)
            let isToday = cal.isDateInToday(dayKey)
            var taken = 0
            var total = 0
            for med in meds {
                let times = med.timesOfDay.compactMap { comps -> (Int, Int)? in
                    guard let h = comps.hour, let m = comps.minute else { return nil }
                    return (h, m)
                }
                for (h, m) in times {
                    // Skip future doses today — they haven't come due yet
                    if isToday, let scheduled = cal.date(bySettingHour: h, minute: m, second: 0, of: now), scheduled > now {
                        continue
                    }
                    total += 1
                    let key = String(format: "%02d:%02d", h, m)
                    if latestStatus(on: dayKey, medID: med.id, scheduleKey: key, medTimesCount: times.count) == .taken {
                        taken += 1
                    }
                }
            }
            byDay[dayKey] = (taken, total)
        }

        return byDay.keys.sorted().map { day in
            let v = byDay[day] ?? (0,0)
            let pct = v.total > 0 ? Double(v.taken) / Double(v.total) : 0
            return (day, pct)
        }
    }

    /// Adherence data for a full month. Returns dictionary: startOfDay -> (taken, total) counts.
    func monthlyAdherence(for medicationID: UUID? = nil, year: Int, month: Int) -> [Date: (taken: Int, total: Int)] {
        let cal = Calendar.current
        guard let monthStart = cal.date(from: DateComponents(year: year, month: month, day: 1)),
              let monthRange = cal.range(of: .day, in: .month, for: monthStart) else { return [:] }
        let now = Date()
        let today = cal.startOfDay(for: now)

        let logsWindow = intakeLogs.filter { log in
            let day = cal.startOfDay(for: log.date)
            guard let monthEnd = cal.date(byAdding: .month, value: 1, to: monthStart) else { return false }
            guard day >= monthStart && day < monthEnd else { return false }
            if let mid = medicationID { return log.medicationID == mid }
            return true
        }

        let meds: [Medication] = {
            if let mid = medicationID { return medications.filter { $0.id == mid } }
            return medications
        }()

        var result: [Date: (taken: Int, total: Int)] = [:]
        for dayNum in monthRange {
            guard let day = cal.date(from: DateComponents(year: year, month: month, day: dayNum)) else { continue }
            let dayKey = cal.startOfDay(for: day)
            if dayKey > today { continue } // skip future days
            let isToday = cal.isDateInToday(dayKey)
            var taken = 0, total = 0
            for med in meds {
                let times = med.timesOfDay.compactMap { c -> (Int, Int)? in
                    guard let h = c.hour, let m = c.minute else { return nil }
                    return (h, m)
                }
                for (h, m) in times {
                    if isToday, let sched = cal.date(bySettingHour: h, minute: m, second: 0, of: now), sched > now { continue }
                    total += 1
                    let key = String(format: "%02d:%02d", h, m)
                    let dayEnd = cal.date(byAdding: .day, value: 1, to: dayKey)!
                    let match = logsWindow.filter { log in
                        guard log.medicationID == med.id && log.date >= dayKey && log.date < dayEnd else { return false }
                        return log.scheduleKey == key || (times.count == 1 && log.scheduleKey == nil)
                    }.sorted(by: { $0.date > $1.date }).first
                    if match?.status == .taken { taken += 1 }
                }
            }
            result[dayKey] = (taken, total)
        }
        return result
    }

    /// Intake logs for a specific day, optionally filtered by medication
    func intakeLogs(for date: Date, medicationID: UUID? = nil) -> [IntakeLog] {
        let cal = Calendar.current
        let dayStart = cal.startOfDay(for: date)
        let dayEnd = cal.date(byAdding: .day, value: 1, to: dayStart)!
        return intakeLogs.filter { log in
            guard log.date >= dayStart && log.date < dayEnd else { return false }
            if let mid = medicationID { return log.medicationID == mid }
            return true
        }.sorted(by: { $0.date < $1.date })
    }

    /// Adherence percentage over N days for a specific (or all) medication(s)
    func adherencePercent(for medicationID: UUID? = nil, days: Int = 30) -> Double {
        let cal = Calendar.current
        let endDay = cal.startOfDay(for: Date())
        let startDay = cal.date(byAdding: .day, value: -(days - 1), to: endDay)!
        var taken = 0, total = 0
        let now = Date()
        let meds: [Medication] = {
            if let mid = medicationID { return medications.filter { $0.id == mid } }
            return medications
        }()
        for i in 0..<days {
            let day = cal.date(byAdding: .day, value: i, to: startDay)!
            let dayKey = cal.startOfDay(for: day)
            if dayKey > endDay { continue }
            let isToday = cal.isDateInToday(dayKey)
            let dayEnd = cal.date(byAdding: .day, value: 1, to: dayKey)!
            for med in meds {
                let times = med.timesOfDay.compactMap { c -> (Int, Int)? in
                    guard let h = c.hour, let m = c.minute else { return nil }
                    return (h, m)
                }
                for (h, m) in times {
                    if isToday, let sched = cal.date(bySettingHour: h, minute: m, second: 0, of: now), sched > now { continue }
                    total += 1
                    let key = String(format: "%02d:%02d", h, m)
                    let match = intakeLogs.filter { log in
                        guard log.medicationID == med.id && log.date >= dayKey && log.date < dayEnd else { return false }
                        return log.scheduleKey == key || (times.count == 1 && log.scheduleKey == nil)
                    }.sorted(by: { $0.date > $1.date }).first
                    if match?.status == .taken { taken += 1 }
                }
            }
        }
        return total > 0 ? Double(taken) / Double(total) : 0
    }

    /// Current streak: consecutive days (ending today/yesterday) with all doses taken
    func currentStreak(for medicationID: UUID) -> Int {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        var streak = 0
        for offset in 0..<365 {
            let day = cal.date(byAdding: .day, value: -offset, to: today)!
            let dayKey = cal.startOfDay(for: day)
            let dayEnd = cal.date(byAdding: .day, value: 1, to: dayKey)!
            guard let med = medications.first(where: { $0.id == medicationID }) else { break }
            let times = med.timesOfDay.compactMap { c -> (Int, Int)? in
                guard let h = c.hour, let m = c.minute else { return nil }
                return (h, m)
            }
            if times.isEmpty { break }
            let now = Date()
            let isToday = cal.isDateInToday(dayKey)
            var allTaken = true
            var hasDue = false
            for (h, m) in times {
                if isToday, let sched = cal.date(bySettingHour: h, minute: m, second: 0, of: now), sched > now { continue }
                hasDue = true
                let key = String(format: "%02d:%02d", h, m)
                let match = intakeLogs.filter { log in
                    guard log.medicationID == medicationID && log.date >= dayKey && log.date < dayEnd else { return false }
                    return log.scheduleKey == key || (times.count == 1 && log.scheduleKey == nil)
                }.sorted(by: { $0.date > $1.date }).first
                if match?.status != .taken { allTaken = false; break }
            }
            if !hasDue && offset == 0 { continue } // no doses due yet today, look at yesterday
            if !hasDue || !allTaken { break }
            streak += 1
        }
        return streak
    }

    /// Consecutive days (ending yesterday) where the medication had zero taken doses.
    /// Only looks back to the earliest log for this medication (avoids false positives for newly added meds).
    func consecutiveMissedDays(for medicationID: UUID) -> Int {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())

        // Don't count days before the medication had any activity
        let medLogs = intakeLogs.filter { $0.medicationID == medicationID }
        guard let earliest = medLogs.min(by: { $0.date < $1.date }) else { return 0 }
        let earliestDay = cal.startOfDay(for: earliest.date)

        guard let med = medications.first(where: { $0.id == medicationID }) else { return 0 }
        let times = med.timesOfDay.compactMap { c -> (Int, Int)? in
            guard let h = c.hour, let m = c.minute else { return nil }
            return (h, m)
        }
        if times.isEmpty { return 0 }

        var missed = 0
        for offset in 1..<60 {
            guard let day = cal.date(byAdding: .day, value: -offset, to: today) else { break }
            if day < earliestDay { break }
            let dayEnd = cal.date(byAdding: .day, value: 1, to: day)!
            let dayLogs = intakeLogs.filter { $0.medicationID == medicationID && $0.date >= day && $0.date < dayEnd }
            let hasTaken = dayLogs.contains { $0.status == .taken }
            if hasTaken { break }
            missed += 1
        }
        return missed
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
