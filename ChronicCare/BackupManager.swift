import Foundation

struct AppBackup: Codable {
    let version: Int
    let date: Date
    let measurements: [Measurement]
    let medications: [Medication]
    let intakeLogs: [IntakeLog]
    var emergencyInfo: EmergencyInfo?
    var caregivers: [CaregiverContact]?
}

enum BackupManager {
    @MainActor
    static func makeBackup(store: DataStore) throws -> URL {
        let backup = AppBackup(version: 1, date: Date(), measurements: store.measurements, medications: store.medications, intakeLogs: store.intakeLogs, emergencyInfo: store.emergencyInfo, caregivers: store.caregivers)
        let data = try JSONEncoder().encode(backup)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("Ccare_Backup_\(Int(Date().timeIntervalSince1970)).json")
        try data.write(to: url, options: .atomic)
        return url
    }

    static func loadBackup(from url: URL) throws -> AppBackup {
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(AppBackup.self, from: data)
    }

    // MARK: - CSV Export

    private static func csvEscape(_ value: String) -> String {
        let escaped = value.replacingOccurrences(of: "\"", with: "\"\"")
        return "\"\(escaped)\""
    }

    @MainActor
    static func generateIntakeCSV(store: DataStore, startDate: Date, endDate: Date) throws -> URL {
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd HH:mm"
        let medMap = Dictionary(uniqueKeysWithValues: store.medications.map { ($0.id, $0) })

        var csv = "Date,Medication,Dose,Status,ScheduleKey\n"
        let filtered = store.intakeLogs.filter { $0.date >= startDate && $0.date < endDate }
            .sorted { $0.date < $1.date }
        for log in filtered {
            let med = medMap[log.medicationID]
            let dateStr = df.string(from: log.date)
            let name = csvEscape(med?.name ?? "Unknown")
            let dose = csvEscape(med?.dose ?? "")
            let status: String
            switch log.status {
            case .taken: status = "Taken"
            case .skipped: status = "Skipped"
            case .snoozed: status = "Snoozed"
            }
            let key = log.scheduleKey ?? ""
            csv += "\(dateStr),\(name),\(dose),\(status),\(key)\n"
        }

        let url = FileManager.default.temporaryDirectory.appendingPathComponent("Ccare_Intake_\(Int(Date().timeIntervalSince1970)).csv")
        try csv.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    @MainActor
    static func generateMeasurementsCSV(store: DataStore, startDate: Date, endDate: Date) throws -> URL {
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd HH:mm"

        var csv = "Date,Type,Value,Diastolic,Unit\n"
        let filtered = store.measurements.filter { $0.date >= startDate && $0.date < endDate }
            .sorted { $0.date < $1.date }
        for m in filtered {
            let dateStr = df.string(from: m.date)
            let typeName = csvEscape(m.type.rawValue)
            let value: String
            let unit: String
            if m.type == .bloodGlucose {
                let v = UnitPreferences.mgdlToPreferred(m.value)
                value = UnitPreferences.glucoseUnit == .mgdL ? String(format: "%.0f", v) : String(format: "%.1f", v)
                unit = UnitPreferences.glucoseUnit.rawValue
            } else {
                value = String(format: "%.1f", m.value)
                unit = m.type.unit
            }
            let dia = m.diastolic.map { String(format: "%.0f", $0) } ?? ""
            csv += "\(dateStr),\(typeName),\(value),\(dia),\(unit)\n"
        }

        let url = FileManager.default.temporaryDirectory.appendingPathComponent("Ccare_Measurements_\(Int(Date().timeIntervalSince1970)).csv")
        try csv.write(to: url, atomically: true, encoding: .utf8)
        return url
    }
}
