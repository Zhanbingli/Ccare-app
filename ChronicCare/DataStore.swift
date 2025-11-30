import Foundation
import Combine

@MainActor
final class DataStore: ObservableObject {
    @Published private(set) var measurements: [Measurement] = []
    @Published private(set) var medications: [Medication] = []
    @Published private(set) var intakeLogs: [IntakeLog] = []

    private var cancellables: Set<AnyCancellable> = []

    private let measurementsURL: URL
    private let medicationsURL: URL
    private let intakeLogsURL: URL
    private let goalsDefaults = UserDefaults.standard

    init() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        self.measurementsURL = docs.appendingPathComponent("measurements.json")
        self.medicationsURL = docs.appendingPathComponent("medications.json")
        self.intakeLogsURL = docs.appendingPathComponent("intake_logs.json")

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
    func removeMedication(at offsets: IndexSet) { medications.remove(atOffsets: offsets) }
    func updateMedication(_ item: Medication) {
        if let idx = medications.firstIndex(where: { $0.id == item.id }) {
            medications[idx] = item
        }
    }
    // Ensure one final status per day per medication per scheduleKey
    func upsertIntake(medicationID: UUID, status: IntakeStatus, scheduleTime: DateComponents?, at date: Date = Date()) {
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
        intakeLogs.append(IntakeLog(medicationID: medicationID, date: date, status: status, scheduleKey: key))
    }

    func clearAll() {
        measurements.removeAll()
        medications.removeAll()
        intakeLogs.removeAll()
    }

    // MARK: - Import Backup
    func importBackup(_ backup: AppBackup) {
        measurements = backup.measurements.sorted(by: { $0.date > $1.date })
        medications = backup.medications
        intakeLogs = backup.intakeLogs
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
    }

    private func saveMeasurements() {
        let snapshot = measurements
        persist(snapshot, to: measurementsURL, label: "measurements")
    }

    private func saveMedications() {
        let snapshot = medications
        persist(snapshot, to: medicationsURL, label: "medications")
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

        var byDay: [Date: (taken: Int, total: Int)] = [:]
        for i in 0..<7 {
            let day = cal.date(byAdding: .day, value: i, to: startDay)!
            let dayKey = cal.startOfDay(for: day)
            var taken = 0
            var total = 0
            for med in meds {
                let times = med.timesOfDay.compactMap { comps -> (Int, Int)? in
                    guard let h = comps.hour, let m = comps.minute else { return nil }
                    return (h, m)
                }
                for (h, m) in times {
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
