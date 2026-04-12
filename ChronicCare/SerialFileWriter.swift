import Foundation

/// Serializes file writes so rapid mutations cannot race and overwrite each other.
actor SerialFileWriter {
    func write<T: Encodable>(_ value: T, to url: URL, label: String) {
        do {
            let data = try JSONEncoder().encode(value)
            do {
                try data.write(to: url, options: [.atomic, .completeFileProtection])
            } catch {
                // Fallback when file protection blocks writes (e.g., device locked)
                try data.write(to: url, options: [.atomic])
            }
            try? (url as NSURL).setResourceValue(true, forKey: .isExcludedFromBackupKey)
        } catch {
            #if DEBUG
            print("Failed to save \(label): \(error)")
            #endif
        }
    }
}
