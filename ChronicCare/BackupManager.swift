import Foundation

struct AppBackup: Codable {
    var version: Int
    let date: Date
    let measurements: [Measurement]
    let medications: [Medication]
    let intakeLogs: [IntakeLog]
    var emergencyInfo: EmergencyInfo?
    var caregivers: [CaregiverContact]?
    var medicationImagesByPath: [String: Data]?
}

enum BackupManager {
    private static let protectedWriteOptions: Data.WritingOptions = [.atomic, .completeFileProtection]

    private static func prepareExportURL(prefix: String, ext: String) -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("\(prefix)_\(Int(Date().timeIntervalSince1970)).\(ext)")
    }

    private static func writeProtectedData(_ data: Data, to url: URL) throws {
        try data.write(to: url, options: protectedWriteOptions)
        try? (url as NSURL).setResourceValue(true, forKey: .isExcludedFromBackupKey)
    }

    private static func writeProtectedString(_ string: String, to url: URL) throws {
        let data = Data(string.utf8)
        try writeProtectedData(data, to: url)
    }

    @MainActor
    static func makeBackup(store: DataStore) throws -> URL {
        let medicationImagesByPath = Dictionary(
            uniqueKeysWithValues: store.medications.compactMap { medication -> (String, Data)? in
                guard let path = medication.imagePath,
                      let data = loadMedicationImageData(path: path) else { return nil }
                return (path, data)
            }
        )
        let backup = AppBackup(
            version: BackupManager.currentVersion,
            date: Date(),
            measurements: store.measurements,
            medications: store.medications,
            intakeLogs: store.intakeLogs,
            emergencyInfo: store.emergencyInfo,
            caregivers: store.caregivers,
            medicationImagesByPath: medicationImagesByPath.isEmpty ? nil : medicationImagesByPath
        )
        let data = try JSONEncoder().encode(backup)
        let url = prepareExportURL(prefix: "Ccare_Backup", ext: "json")
        try writeProtectedData(data, to: url)
        return url
    }

    static let currentVersion = 2

    static func loadBackup(from url: URL) throws -> AppBackup {
        let data = try Data(contentsOf: url)
        let backup = try JSONDecoder().decode(AppBackup.self, from: data)
        return migrate(backup)
    }

    /// Migrate older backup versions to the current format.
    private static func migrate(_ backup: AppBackup) -> AppBackup {
        var result = backup
        if result.version < 2 {
            // v1 -> v2: emergencyInfo and caregivers were added; ensure non-nil defaults
            if result.caregivers == nil { result.caregivers = [] }
            result.version = 2
        }
        return result
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

        let url = prepareExportURL(prefix: "Ccare_Intake", ext: "csv")
        try writeProtectedString(csv, to: url)
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

        let url = prepareExportURL(prefix: "Ccare_Measurements", ext: "csv")
        try writeProtectedString(csv, to: url)
        return url
    }
}
