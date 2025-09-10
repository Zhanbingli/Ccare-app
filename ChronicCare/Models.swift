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
    var timeOfDay: DateComponents // hour & minute
    var remindersEnabled: Bool
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
}
