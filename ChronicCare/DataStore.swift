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
    func logIntake(medicationID: UUID, status: IntakeStatus, at date: Date = Date()) {
        intakeLogs.append(IntakeLog(medicationID: medicationID, date: date, status: status))
    }

    func clearAll() {
        measurements.removeAll()
        medications.removeAll()
        intakeLogs.removeAll()
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
        do {
            let encoder = JSONEncoder()
            let data = try encoder.encode(measurements)
            try data.write(to: measurementsURL, options: [.atomic, .completeFileProtection])
        } catch {
            print("Failed to save measurements: \(error)")
        }
    }

    private func saveMedications() {
        do {
            let encoder = JSONEncoder()
            let data = try encoder.encode(medications)
            try data.write(to: medicationsURL, options: [.atomic, .completeFileProtection])
        } catch {
            print("Failed to save medications: \(error)")
        }
    }

    private func saveIntakeLogs() {
        do {
            let encoder = JSONEncoder()
            let data = try encoder.encode(intakeLogs)
            try data.write(to: intakeLogsURL, options: [.atomic, .completeFileProtection])
        } catch {
            print("Failed to save intake logs: \(error)")
        }
    }

    // MARK: - Stats
    func weeklyAdherence(for medicationID: UUID? = nil, endingOn endDate: Date = Date()) -> [(Date, Double)] {
        let cal = Calendar.current
        let start = cal.date(byAdding: .day, value: -6, to: cal.startOfDay(for: endDate))!
        let filtered = intakeLogs.filter { log in
            (medicationID == nil || log.medicationID == medicationID!) && log.date >= start && log.date <= endDate
        }
        var byDay: [Date: (taken: Int, total: Int)] = [:]
        for i in 0..<7 {
            let day = cal.date(byAdding: .day, value: i, to: start)!
            byDay[cal.startOfDay(for: day)] = (0, 0)
        }
        for log in filtered {
            let key = cal.startOfDay(for: log.date)
            var entry = byDay[key] ?? (0,0)
            entry.total += 1
            if log.status == .taken { entry.taken += 1 }
            byDay[key] = entry
        }
        return byDay.keys.sorted().map { day in
            let v = byDay[day]!
            let pct = v.total > 0 ? Double(v.taken) / Double(v.total) : 0
            return (day, pct)
        }
    }
}
