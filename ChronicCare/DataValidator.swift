import Foundation

enum ValidationResult {
    case valid
    case warning(String)
    case error(String)
}

struct DataValidator {

    // MARK: - Measurement Validation

    static func validateBloodPressure(systolic: Double, diastolic: Double?) -> ValidationResult {
        // Check systolic range
        if systolic < 40 {
            return .error(NSLocalizedString("Systolic blood pressure seems too low. Normal range is 90-180 mmHg.", comment: ""))
        }
        if systolic > 300 {
            return .error(NSLocalizedString("Systolic blood pressure seems too high. Please verify the value.", comment: ""))
        }

        // Check diastolic if provided
        if let dia = diastolic {
            if dia < 20 {
                return .error(NSLocalizedString("Diastolic blood pressure seems too low. Normal range is 60-120 mmHg.", comment: ""))
            }
            if dia > 200 {
                return .error(NSLocalizedString("Diastolic blood pressure seems too high. Please verify the value.", comment: ""))
            }

            // Check relationship between systolic and diastolic
            if dia >= systolic {
                return .error(NSLocalizedString("Diastolic cannot be higher than or equal to systolic pressure.", comment: ""))
            }
        }

        // Warning ranges
        if systolic > 180 || (diastolic ?? 0) > 120 {
            return .warning(NSLocalizedString("⚠️ This is a very high blood pressure reading. Consider consulting your healthcare provider.", comment: ""))
        }
        if systolic < 90 || (diastolic ?? 0) < 60 {
            return .warning(NSLocalizedString("⚠️ This is a low blood pressure reading. Please ensure you feel well.", comment: ""))
        }

        return .valid
    }

    static func validateBloodGlucose(value: Double, unit: GlucoseUnit = .mgdL) -> ValidationResult {
        let mgdlValue = unit == .mgdL ? value : value * 18.0

        if mgdlValue < 20 {
            return .error(NSLocalizedString("Blood glucose seems too low. Please verify the value.", comment: ""))
        }
        if mgdlValue > 600 {
            return .error(NSLocalizedString("Blood glucose seems extremely high. Please verify the value.", comment: ""))
        }

        // Critical ranges
        if mgdlValue < 54 {
            return .warning(NSLocalizedString("⚠️ This is a critically low blood glucose reading. Please take action if you feel unwell.", comment: ""))
        }
        if mgdlValue > 400 {
            return .warning(NSLocalizedString("⚠️ This is a very high blood glucose reading. Consider consulting your healthcare provider.", comment: ""))
        }

        return .valid
    }

    static func validateWeight(value: Double) -> ValidationResult {
        if value < 20 {
            return .error(NSLocalizedString("Weight seems too low. Please verify the value.", comment: ""))
        }
        if value > 300 {
            return .error(NSLocalizedString("Weight seems extremely high. Please verify the value.", comment: ""))
        }

        return .valid
    }

    static func validateHeartRate(value: Double) -> ValidationResult {
        if value < 20 {
            return .error(NSLocalizedString("Heart rate seems too low. Please verify the value.", comment: ""))
        }
        if value > 250 {
            return .error(NSLocalizedString("Heart rate seems too high. Please verify the value.", comment: ""))
        }

        // Warning ranges
        if value < 40 {
            return .warning(NSLocalizedString("⚠️ This is a very low heart rate. Please ensure you feel well.", comment: ""))
        }
        if value > 150 {
            return .warning(NSLocalizedString("⚠️ This is a high heart rate. If you're not exercising, consider checking with your doctor.", comment: ""))
        }

        return .valid
    }

    // MARK: - Medication Validation

    static func validateMedicationName(_ name: String) -> ValidationResult {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)

        if trimmed.isEmpty {
            return .error(NSLocalizedString("Medication name cannot be empty.", comment: ""))
        }

        if trimmed.count < 2 {
            return .warning(NSLocalizedString("Medication name seems very short. Please verify.", comment: ""))
        }

        return .valid
    }

    static func validateMedicationSchedule(_ times: [DateComponents]) -> ValidationResult {
        if times.isEmpty {
            return .warning(NSLocalizedString("No schedule times set. Reminders will not work.", comment: ""))
        }

        // Check for duplicate times
        let timeStrings = times.compactMap { comps -> String? in
            guard let h = comps.hour, let m = comps.minute else { return nil }
            return String(format: "%02d:%02d", h, m)
        }

        if Set(timeStrings).count < timeStrings.count {
            return .warning(NSLocalizedString("Some reminder times are duplicated.", comment: ""))
        }

        return .valid
    }

    // MARK: - Smart Suggestions

    static func suggestMedicationAdjustment(medication: Medication, skipCount: Int, timeWindow: TimeInterval) -> String? {
        if skipCount >= 2 {
            return NSLocalizedString("You've skipped this medication twice recently. Would you like to adjust the reminder time?", comment: "")
        }
        return nil
    }

    static func suggestDataEntry(lastEntryDate: Date?, type: MeasurementType) -> String? {
        guard let lastDate = lastEntryDate else {
            return NSLocalizedString("Start tracking your \(type.rawValue.lowercased()) to see trends.", comment: "")
        }

        let daysSinceLastEntry = Calendar.current.dateComponents([.day], from: lastDate, to: Date()).day ?? 0

        switch type {
        case .bloodPressure, .bloodGlucose:
            if daysSinceLastEntry > 7 {
                return String(format: NSLocalizedString("It's been %d days since your last %@ measurement. Consider taking a new reading.", comment: ""), daysSinceLastEntry, type.rawValue.lowercased())
            }
        case .weight:
            if daysSinceLastEntry > 14 {
                return String(format: NSLocalizedString("It's been %d days since you last measured your weight.", comment: ""), daysSinceLastEntry)
            }
        case .heartRate:
            if daysSinceLastEntry > 7 {
                return String(format: NSLocalizedString("Consider measuring your heart rate regularly for better tracking.", comment: ""))
            }
        }

        return nil
    }

    // MARK: - Trend Analysis

    static func analyzeTrend(measurements: [Measurement], type: MeasurementType) -> String? {
        guard measurements.count >= 3 else { return nil }

        let recent = Array(measurements.prefix(3))
        let values = recent.map { $0.value }

        // Check if all values are increasing
        let isIncreasing = zip(values, values.dropFirst()).allSatisfy { $0 < $1 }
        let isDecreasing = zip(values, values.dropFirst()).allSatisfy { $0 > $1 }

        if isIncreasing {
            switch type {
            case .bloodPressure:
                return NSLocalizedString("Your blood pressure has been increasing. Consider consulting your doctor.", comment: "")
            case .bloodGlucose:
                return NSLocalizedString("Your blood glucose has been rising. Review your diet and medication adherence.", comment: "")
            case .weight:
                return NSLocalizedString("Your weight has been increasing steadily.", comment: "")
            case .heartRate:
                return NSLocalizedString("Your heart rate has been increasing.", comment: "")
            }
        } else if isDecreasing {
            switch type {
            case .bloodPressure:
                if values.last! < 90 {
                    return NSLocalizedString("Your blood pressure has been decreasing and may be too low.", comment: "")
                }
            case .bloodGlucose:
                if values.last! < 70 {
                    return NSLocalizedString("Your blood glucose has been decreasing. Be careful of hypoglycemia.", comment: "")
                }
            default:
                break
            }
        }

        return nil
    }
}
