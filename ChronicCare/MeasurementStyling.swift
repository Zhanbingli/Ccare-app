import SwiftUI

extension Measurement {
    var isAbnormal: Bool {
        let defaults = UserDefaults.standard
        switch type {
        case .bloodPressure:
            let sysHigh = defaults.object(forKey: "goals.bp.sysHigh") != nil ? defaults.double(forKey: "goals.bp.sysHigh") : 140.0
            let diaHigh = defaults.object(forKey: "goals.bp.diaHigh") != nil ? defaults.double(forKey: "goals.bp.diaHigh") : 90.0
            let dia = diastolic ?? 0
            return value >= sysHigh || dia >= diaHigh
        case .bloodGlucose:
            let low = defaults.object(forKey: "goals.glucose.low") != nil ? defaults.double(forKey: "goals.glucose.low") : 70.0
            let high = defaults.object(forKey: "goals.glucose.high") != nil ? defaults.double(forKey: "goals.glucose.high") : 180.0
            return value < low || value > high
        case .heartRate:
            let low = defaults.object(forKey: "goals.hr.low") != nil ? defaults.double(forKey: "goals.hr.low") : 50.0
            let high = defaults.object(forKey: "goals.hr.high") != nil ? defaults.double(forKey: "goals.hr.high") : 110.0
            return value < low || value > high
        case .weight:
            return false
        }
    }

    var cardTint: Color {
        isAbnormal ? .red : type.tint
    }

    var valueForeground: Color {
        isAbnormal ? .red : .primary
    }
}

