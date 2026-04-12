import Foundation

enum MeasurementType: String, CaseIterable, Codable, Identifiable {
    case bloodPressure = "Blood Pressure"
    case bloodGlucose = "Blood Glucose"
    case weight = "Weight"
    case heartRate = "Heart Rate"

    var id: String { rawValue }

    var displayName: String {
        NSLocalizedString(rawValue, comment: "")
    }

    var unit: String {
        switch self {
        case .bloodPressure: return NSLocalizedString("mmHg", comment: "Blood pressure unit")
        case .bloodGlucose: return NSLocalizedString("mg/dL", comment: "Blood glucose unit")
        case .weight: return NSLocalizedString("kg", comment: "Weight unit")
        case .heartRate: return NSLocalizedString("bpm", comment: "Heart rate unit")
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

extension Measurement {
    func clampedToNow(now: Date = Date()) -> Measurement {
        guard date > now else { return self }
        var copy = self
        copy.date = now
        return copy
    }
}

enum FoodInstruction: String, CaseIterable, Codable, Identifiable {
    case withFood
    case beforeFood
    case afterFood
    case onEmptyStomach
    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .withFood: return NSLocalizedString("With food", comment: "")
        case .beforeFood: return NSLocalizedString("Before food", comment: "")
        case .afterFood: return NSLocalizedString("After food", comment: "")
        case .onEmptyStomach: return NSLocalizedString("On empty stomach", comment: "")
        }
    }

    var shortLabel: String {
        switch self {
        case .withFood: return NSLocalizedString("w/ food", comment: "")
        case .beforeFood: return NSLocalizedString("before meal", comment: "")
        case .afterFood: return NSLocalizedString("after meal", comment: "")
        case .onEmptyStomach: return NSLocalizedString("empty stomach", comment: "")
        }
    }
}

struct Medication: Identifiable, Codable {
    var id: UUID = UUID()
    var name: String
    var dose: String
    var notes: String?
    var startDate: Date
    var timesOfDay: [DateComponents]
    var remindersEnabled: Bool
    var category: MedicationCategory?
    var customCategoryName: String?
    var imagePath: String?
    var pillsRemaining: Int?
    var pillsPerDose: Int?
    var foodInstruction: FoodInstruction?
    var isAsNeeded: Bool?
    var courseEndDate: Date?
    var specialInstructions: String?

    enum CodingKeys: String, CodingKey { case id, name, dose, notes, startDate, timesOfDay, timeOfDay, remindersEnabled, category, customCategoryName, imagePath, pillsRemaining, pillsPerDose, foodInstruction, isAsNeeded, courseEndDate, specialInstructions }

    init(id: UUID = UUID(), name: String, dose: String, notes: String? = nil, startDate: Date = Date(), timesOfDay: [DateComponents], remindersEnabled: Bool, category: MedicationCategory? = nil, customCategoryName: String? = nil, imagePath: String? = nil, pillsRemaining: Int? = nil, pillsPerDose: Int? = nil, foodInstruction: FoodInstruction? = nil, isAsNeeded: Bool? = nil, courseEndDate: Date? = nil, specialInstructions: String? = nil) {
        self.id = id
        self.name = name
        self.dose = dose
        self.notes = notes
        self.startDate = startDate
        self.timesOfDay = timesOfDay
        self.remindersEnabled = remindersEnabled
        self.category = category
        self.customCategoryName = customCategoryName
        self.imagePath = imagePath
        self.pillsRemaining = pillsRemaining
        self.pillsPerDose = pillsPerDose
        self.foodInstruction = foodInstruction
        self.isAsNeeded = isAsNeeded
        self.courseEndDate = courseEndDate
        self.specialInstructions = specialInstructions
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        self.name = try c.decode(String.self, forKey: .name)
        self.dose = try c.decode(String.self, forKey: .dose)
        self.notes = try c.decodeIfPresent(String.self, forKey: .notes)
        self.startDate = try c.decodeIfPresent(Date.self, forKey: .startDate) ?? .distantPast
        self.remindersEnabled = try c.decodeIfPresent(Bool.self, forKey: .remindersEnabled) ?? true
        self.category = try c.decodeIfPresent(MedicationCategory.self, forKey: .category)
        self.customCategoryName = try c.decodeIfPresent(String.self, forKey: .customCategoryName)
        self.imagePath = try c.decodeIfPresent(String.self, forKey: .imagePath)
        self.pillsRemaining = try c.decodeIfPresent(Int.self, forKey: .pillsRemaining)
        self.pillsPerDose = try c.decodeIfPresent(Int.self, forKey: .pillsPerDose)
        self.foodInstruction = try c.decodeIfPresent(FoodInstruction.self, forKey: .foodInstruction)
        self.isAsNeeded = try c.decodeIfPresent(Bool.self, forKey: .isAsNeeded)
        self.courseEndDate = try c.decodeIfPresent(Date.self, forKey: .courseEndDate)
        self.specialInstructions = try c.decodeIfPresent(String.self, forKey: .specialInstructions)
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
        try c.encode(startDate, forKey: .startDate)
        try c.encode(timesOfDay, forKey: .timesOfDay)
        try c.encode(remindersEnabled, forKey: .remindersEnabled)
        try c.encodeIfPresent(category, forKey: .category)
        try c.encodeIfPresent(customCategoryName, forKey: .customCategoryName)
        try c.encodeIfPresent(imagePath, forKey: .imagePath)
        try c.encodeIfPresent(pillsRemaining, forKey: .pillsRemaining)
        try c.encodeIfPresent(pillsPerDose, forKey: .pillsPerDose)
        try c.encodeIfPresent(foodInstruction, forKey: .foodInstruction)
        try c.encodeIfPresent(isAsNeeded, forKey: .isAsNeeded)
        try c.encodeIfPresent(courseEndDate, forKey: .courseEndDate)
        try c.encodeIfPresent(specialInstructions, forKey: .specialInstructions)
    }
}

enum MedicationCourseState: Equatable {
    case ended(daysPast: Int)
    case endsToday
    case endingSoon(daysRemaining: Int)
    case scheduled(daysRemaining: Int)
}

extension Medication {
    func isDoseActive(on scheduledDate: Date) -> Bool {
        scheduledDate >= startDate
    }

    /// How many days of supply remain (nil if not tracking)
    var daysOfSupplyRemaining: Int? {
        guard let remaining = pillsRemaining, remaining > 0 else { return pillsRemaining == 0 ? 0 : nil }
        guard isAsNeeded != true, !timesOfDay.isEmpty else { return nil }
        let perDose = pillsPerDose ?? 1
        let dosesPerDay = timesOfDay.count
        let pillsPerDay = perDose * dosesPerDay
        guard pillsPerDay > 0 else { return nil }
        return remaining / pillsPerDay
    }

    var isLowSupply: Bool {
        guard let days = daysOfSupplyRemaining else { return false }
        return days <= 7
    }

    func daysUntilCourseEnd(reference now: Date = Date(), calendar: Calendar = .current) -> Int? {
        guard let courseEndDate else { return nil }
        let start = calendar.startOfDay(for: now)
        let end = calendar.startOfDay(for: courseEndDate)
        return calendar.dateComponents([.day], from: start, to: end).day
    }

    func courseState(thresholdDays: Int = 3, reference now: Date = Date(), calendar: Calendar = .current) -> MedicationCourseState? {
        guard let days = daysUntilCourseEnd(reference: now, calendar: calendar) else { return nil }
        if days < 0 { return .ended(daysPast: abs(days)) }
        if days == 0 { return .endsToday }
        if days <= max(thresholdDays, 0) { return .endingSoon(daysRemaining: days) }
        return .scheduled(daysRemaining: days)
    }

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
    var scheduleKey: String?
    var note: String?
    var scheduledDate: Date? = nil
    var recordedAt: Date? = nil
}

extension IntakeLog {
    var effectiveRecordedAt: Date {
        recordedAt ?? date
    }
}

// MARK: - Category-Measurement Correlation

extension MedicationCategory {
    var correlatedMeasurementTypes: [MeasurementType] {
        switch self {
        case .antihypertensive: return [.bloodPressure, .heartRate]
        case .antidiabetic: return [.bloodGlucose]
        default: return []
        }
    }
}

// MARK: - Emergency Info

struct EmergencyContact: Codable, Identifiable {
    var id: UUID = UUID()
    var name: String
    var phone: String
    var relationship: String
}

struct EmergencyInfo: Codable {
    var bloodType: String?
    var allergies: String?
    var medicalConditions: String?
    var emergencyContacts: [EmergencyContact] = []
}

// MARK: - Caregiver

struct CaregiverContact: Codable, Identifiable {
    var id: UUID = UUID()
    var name: String
    var phone: String?
    var notifyOnMiss: Bool = true
}
