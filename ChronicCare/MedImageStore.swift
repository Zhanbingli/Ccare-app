import Foundation
import UIKit

func medImagesDir() -> URL {
    let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
    let dir = docs.appendingPathComponent("med_images", conformingTo: .directory)
    if !FileManager.default.fileExists(atPath: dir.path) {
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }
    try? (dir as NSURL).setResourceValue(true, forKey: .isExcludedFromBackupKey)
    return dir
}

func storeMedicationImage(_ image: UIImage, id: UUID) -> String? {
    let url = medImagesDir().appendingPathComponent("\(id.uuidString).jpg")
    guard let data = image.jpegData(compressionQuality: 0.9) else { return nil }
    do {
        try data.write(to: url, options: [.atomic, .completeFileProtection])
        try? (url as NSURL).setResourceValue(true, forKey: .isExcludedFromBackupKey)
        return "med_images/\(id.uuidString).jpg"
    } catch {
        return nil
    }
}

func loadMedicationImage(path: String?) -> UIImage? {
    guard let path = path else { return nil }
    let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
    let url = docs.appendingPathComponent(path)
    return UIImage(contentsOfFile: url.path)
}

func loadMedicationImageData(path: String?) -> Data? {
    guard let path = path else { return nil }
    let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
    let url = docs.appendingPathComponent(path)
    return try? Data(contentsOf: url)
}

func restoreMedicationImageData(_ data: Data, path: String) {
    let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
    let url = docs.appendingPathComponent(path)
    let dir = url.deletingLastPathComponent()
    if !FileManager.default.fileExists(atPath: dir.path) {
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }
    do {
        try data.write(to: url, options: [.atomic, .completeFileProtection])
    } catch {
        try? data.write(to: url, options: [.atomic])
    }
    try? (dir as NSURL).setResourceValue(true, forKey: .isExcludedFromBackupKey)
    try? (url as NSURL).setResourceValue(true, forKey: .isExcludedFromBackupKey)
}

func deleteMedicationImage(path: String?) {
    guard let path = path else { return }
    let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
    let url = docs.appendingPathComponent(path)
    try? FileManager.default.removeItem(at: url)
}
