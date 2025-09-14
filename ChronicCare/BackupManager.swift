import Foundation

struct AppBackup: Codable {
    let version: Int
    let date: Date
    let measurements: [Measurement]
    let medications: [Medication]
    let intakeLogs: [IntakeLog]
}

enum BackupManager {
    @MainActor
    static func makeBackup(store: DataStore) throws -> URL {
        let backup = AppBackup(version: 1, date: Date(), measurements: store.measurements, medications: store.medications, intakeLogs: store.intakeLogs)
        let data = try JSONEncoder().encode(backup)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("Ccare_Backup_\(Int(Date().timeIntervalSince1970)).json")
        try data.write(to: url, options: .atomic)
        return url
    }

    static func loadBackup(from url: URL) throws -> AppBackup {
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(AppBackup.self, from: data)
    }
}
