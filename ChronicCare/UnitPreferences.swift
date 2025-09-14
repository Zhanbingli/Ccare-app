import Foundation

enum GlucoseUnit: String, CaseIterable, Identifiable, Codable {
    case mgdL = "mg/dL"
    case mmolL = "mmol/L"
    var id: String { rawValue }
}

enum UnitPreferences {
    private static let glucoseKey = "units.glucose"

    static var glucoseUnit: GlucoseUnit {
        let raw = UserDefaults.standard.string(forKey: glucoseKey) ?? GlucoseUnit.mgdL.rawValue
        return GlucoseUnit(rawValue: raw) ?? .mgdL
    }

    static func setGlucoseUnit(_ unit: GlucoseUnit) {
        UserDefaults.standard.set(unit.rawValue, forKey: glucoseKey)
    }

    // Conversion helpers (canonical storage is mg/dL)
    private static let factor: Double = 18.0 // 1 mmol/L = 18 mg/dL
    static func mgdlToPreferred(_ mgdl: Double) -> Double {
        switch glucoseUnit {
        case .mgdL: return mgdl
        case .mmolL: return mgdl / factor
        }
    }
    static func preferredToMgdl(_ value: Double) -> Double {
        switch glucoseUnit {
        case .mgdL: return value
        case .mmolL: return value * factor
        }
    }

    // Parameterized conversions (do not depend on global preference)
    static func convertFromMgdl(_ mgdl: Double, to unit: GlucoseUnit) -> Double {
        switch unit {
        case .mgdL: return mgdl
        case .mmolL: return mgdl / factor
        }
    }

    static func convertToMgdl(_ value: Double, from unit: GlucoseUnit) -> Double {
        switch unit {
        case .mgdL: return value
        case .mmolL: return value * factor
        }
    }
}
