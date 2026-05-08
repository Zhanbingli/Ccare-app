import Foundation

struct AppBackup: Codable {
    var version: Int
    let date: Date
    let measurements: [Measurement]
    let medications: [Medication]
    let intakeLogs: [IntakeLog]
    var emergencyInfo: EmergencyInfo?
    var caregivers: [CaregiverContact]?
    var symptomEntries: [SymptomEntry]?
    var symptomClarifications: [SymptomClarification]?
    var doctorVisits: [DoctorVisit]?
    var followUpAgentTasks: [FollowUpAgentTask]?
    var hypertensionAIDrafts: [HypertensionFollowUpAIDraftRecord]?
    var medicationImagesByPath: [String: Data]?

    private enum CodingKeys: String, CodingKey {
        case version
        case date
        case measurements
        case medications
        case intakeLogs
        case emergencyInfo
        case caregivers
        case symptomEntries
        case symptomClarifications
        case doctorVisits
        case followUpAgentTasks
        case agentInboxItems
        case hypertensionAIDrafts
        case medicationImagesByPath
    }

    init(
        version: Int,
        date: Date,
        measurements: [Measurement],
        medications: [Medication],
        intakeLogs: [IntakeLog],
        emergencyInfo: EmergencyInfo?,
        caregivers: [CaregiverContact]?,
        symptomEntries: [SymptomEntry]?,
        symptomClarifications: [SymptomClarification]?,
        doctorVisits: [DoctorVisit]?,
        followUpAgentTasks: [FollowUpAgentTask]?,
        hypertensionAIDrafts: [HypertensionFollowUpAIDraftRecord]?,
        medicationImagesByPath: [String: Data]?
    ) {
        self.version = version
        self.date = date
        self.measurements = measurements
        self.medications = medications
        self.intakeLogs = intakeLogs
        self.emergencyInfo = emergencyInfo
        self.caregivers = caregivers
        self.symptomEntries = symptomEntries
        self.symptomClarifications = symptomClarifications
        self.doctorVisits = doctorVisits
        self.followUpAgentTasks = followUpAgentTasks
        self.hypertensionAIDrafts = hypertensionAIDrafts
        self.medicationImagesByPath = medicationImagesByPath
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try container.decode(Int.self, forKey: .version)
        date = try container.decode(Date.self, forKey: .date)
        measurements = try container.decode([Measurement].self, forKey: .measurements)
        medications = try container.decode([Medication].self, forKey: .medications)
        intakeLogs = try container.decode([IntakeLog].self, forKey: .intakeLogs)
        emergencyInfo = try container.decodeIfPresent(EmergencyInfo.self, forKey: .emergencyInfo)
        caregivers = try container.decodeIfPresent([CaregiverContact].self, forKey: .caregivers)
        symptomEntries = try container.decodeIfPresent([SymptomEntry].self, forKey: .symptomEntries)
        symptomClarifications = try container.decodeIfPresent([SymptomClarification].self, forKey: .symptomClarifications)
        doctorVisits = try container.decodeIfPresent([DoctorVisit].self, forKey: .doctorVisits)
        followUpAgentTasks = try container.decodeIfPresent([FollowUpAgentTask].self, forKey: .followUpAgentTasks)
            ?? container.decodeIfPresent([FollowUpAgentTask].self, forKey: .agentInboxItems)
        hypertensionAIDrafts = try container.decodeIfPresent([HypertensionFollowUpAIDraftRecord].self, forKey: .hypertensionAIDrafts)
        medicationImagesByPath = try container.decodeIfPresent([String: Data].self, forKey: .medicationImagesByPath)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(version, forKey: .version)
        try container.encode(date, forKey: .date)
        try container.encode(measurements, forKey: .measurements)
        try container.encode(medications, forKey: .medications)
        try container.encode(intakeLogs, forKey: .intakeLogs)
        try container.encodeIfPresent(emergencyInfo, forKey: .emergencyInfo)
        try container.encodeIfPresent(caregivers, forKey: .caregivers)
        try container.encodeIfPresent(symptomEntries, forKey: .symptomEntries)
        try container.encodeIfPresent(symptomClarifications, forKey: .symptomClarifications)
        try container.encodeIfPresent(doctorVisits, forKey: .doctorVisits)
        try container.encodeIfPresent(followUpAgentTasks, forKey: .followUpAgentTasks)
        try container.encodeIfPresent(hypertensionAIDrafts, forKey: .hypertensionAIDrafts)
        try container.encodeIfPresent(medicationImagesByPath, forKey: .medicationImagesByPath)
    }
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
            symptomEntries: store.symptomEntries,
            symptomClarifications: store.symptomClarifications,
            doctorVisits: store.doctorVisits,
            followUpAgentTasks: store.followUpAgentTasks,
            hypertensionAIDrafts: store.hypertensionAIDrafts,
            medicationImagesByPath: medicationImagesByPath.isEmpty ? nil : medicationImagesByPath
        )
        let data = try JSONEncoder().encode(backup)
        let url = prepareExportURL(prefix: "Ccare_Backup", ext: "json")
        try writeProtectedData(data, to: url)
        return url
    }

    static let currentVersion = 7

    static func loadBackup(from url: URL) throws -> AppBackup {
        let data = try Data(contentsOf: url)
        let backup = try JSONDecoder().decode(AppBackup.self, from: data)
        return migrate(backup)
    }

    /// Migrate older backup versions to the current format.
    private static func migrate(_ backup: AppBackup) -> AppBackup {
        var result = backup
        if result.followUpAgentTasks == nil {
            result.followUpAgentTasks = []
        }
        if result.version < 2 {
            // v1 -> v2: emergencyInfo and caregivers were added; ensure non-nil defaults
            if result.caregivers == nil { result.caregivers = [] }
            result.version = 2
        }
        if result.version < 3 {
            // v2 -> v3: doctor visit anchors were added for pre-visit prep.
            if result.doctorVisits == nil { result.doctorVisits = [] }
            result.version = 3
        }
        if result.version < 4 {
            // v3 -> v4: local follow-up agent state was added.
            if result.followUpAgentTasks == nil { result.followUpAgentTasks = [] }
            result.version = 4
        }
        if result.version < 5 {
            // v4 -> v5: bounded hypertension AI report drafts were added.
            if result.hypertensionAIDrafts == nil { result.hypertensionAIDrafts = [] }
            result.version = 5
        }
        if result.version < 6 {
            // v5 -> v6: structured symptom clarifications were added.
            if result.symptomClarifications == nil { result.symptomClarifications = [] }
            result.version = 6
        }
        if result.version < 7 {
            // v6 -> v7: follow-up agent task naming replaced the old inbox naming.
            result.version = 7
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
