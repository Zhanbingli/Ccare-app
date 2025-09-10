import SwiftUI

extension Measurement {
    var isAbnormal: Bool {
        switch type {
        case .bloodPressure:
            let dia = diastolic ?? 0
            return value >= 140 || dia >= 90
        case .bloodGlucose:
            return value < 70 || value > 180
        case .heartRate:
            return value < 50 || value > 110
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

