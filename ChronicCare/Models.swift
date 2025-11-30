import Foundation

enum MeasurementType: String, CaseIterable, Codable, Identifiable {
    case bloodPressure = "Blood Pressure"
    case bloodGlucose = "Blood Glucose"
    case weight = "Weight"
    case heartRate = "Heart Rate"

    var id: String { rawValue }

    var unit: String {
        switch self {
        case .bloodPressure: return "mmHg"
        case .bloodGlucose: return "mg/dL"
        case .weight: return "kg"
        case .heartRate: return "bpm"
        }
    }
}

enum MedicationCategory: String, CaseIterable, Codable, Identifiable {
    case unspecified
    case antihypertensive
    case antidiabetic
    case custom
    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .unspecified: return NSLocalizedString("Unspecified", comment: "")
        case .antihypertensive: return NSLocalizedString("Antihypertensive", comment: "")
        case .antidiabetic: return NSLocalizedString("Antidiabetic", comment: "")
        case .custom: return NSLocalizedString("Custom", comment: "")
        }
    }
}

// Typical normal ranges for visual guidance in Trends charts
extension MeasurementType {
    var normalRange: ClosedRange<Double>? {
        switch self {
        case .bloodGlucose:
            return 70...180
        case .heartRate:
            return 50...110
        case .weight:
            return nil
        case .bloodPressure:
            return nil // handled specially (two values)
        }
    }
}

struct Measurement: Identifiable, Codable {
    var id: UUID = UUID()
    var type: MeasurementType
    var value: Double
    var diastolic: Double? // only for blood pressure
    var date: Date
    var note: String?
}

struct Medication: Identifiable, Codable {
    var id: UUID = UUID()
    var name: String
    var dose: String
    var notes: String?
    var timesOfDay: [DateComponents] // one or more times (hour & minute)
    var remindersEnabled: Bool
    var category: MedicationCategory? // optional for backward compatibility
    var customCategoryName: String?
    var imagePath: String? // relative path under Documents (e.g., "med_images/<id>.jpg")

    // Backward compatibility decoder to support legacy `timeOfDay`
    enum CodingKeys: String, CodingKey { case id, name, dose, notes, timesOfDay, timeOfDay, remindersEnabled, category, customCategoryName, imagePath }

    init(id: UUID = UUID(), name: String, dose: String, notes: String? = nil, timesOfDay: [DateComponents], remindersEnabled: Bool, category: MedicationCategory? = nil, customCategoryName: String? = nil, imagePath: String? = nil) {
        self.id = id
        self.name = name
        self.dose = dose
        self.notes = notes
        self.timesOfDay = timesOfDay
        self.remindersEnabled = remindersEnabled
        self.category = category
        self.customCategoryName = customCategoryName
        self.imagePath = imagePath
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        self.name = try c.decode(String.self, forKey: .name)
        self.dose = try c.decode(String.self, forKey: .dose)
        self.notes = try c.decodeIfPresent(String.self, forKey: .notes)
        self.remindersEnabled = try c.decodeIfPresent(Bool.self, forKey: .remindersEnabled) ?? true
        self.category = try c.decodeIfPresent(MedicationCategory.self, forKey: .category)
        self.customCategoryName = try c.decodeIfPresent(String.self, forKey: .customCategoryName)
        self.imagePath = try c.decodeIfPresent(String.self, forKey: .imagePath)
        if let times = try c.decodeIfPresent([DateComponents].self, forKey: .timesOfDay) {
            self.timesOfDay = times
        } else if let legacy = try c.decodeIfPresent(DateComponents.self, forKey: .timeOfDay) {
            self.timesOfDay = [legacy]
        } else {
            self.timesOfDay = []
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(name, forKey: .name)
        try c.encode(dose, forKey: .dose)
        try c.encodeIfPresent(notes, forKey: .notes)
        try c.encode(timesOfDay, forKey: .timesOfDay)
        try c.encode(remindersEnabled, forKey: .remindersEnabled)
        try c.encodeIfPresent(category, forKey: .category)
        try c.encodeIfPresent(customCategoryName, forKey: .customCategoryName)
        try c.encodeIfPresent(imagePath, forKey: .imagePath)
    }
}

extension Medication {
    var displayCategoryName: String? {
        guard let cat = category else { return nil }
        switch cat {
        case .custom:
            let trimmed = (customCategoryName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? MedicationCategory.custom.displayName : trimmed
        case .unspecified:
            return nil
        default:
            return cat.displayName
        }
    }
}

enum IntakeStatus: String, Codable, CaseIterable, Identifiable {
    case taken
    case skipped
    case snoozed
    var id: String { rawValue }
}

struct IntakeLog: Identifiable, Codable {
    var id: UUID = UUID()
    var medicationID: UUID
    var date: Date
    var status: IntakeStatus
    // Optional schedule key (e.g., "08:00") for multi-time medications
    var scheduleKey: String?
}
