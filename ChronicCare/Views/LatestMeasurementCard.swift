import SwiftUI

// MARK: - LatestMeasurementCard

/// Shows the most recent health measurement logged, or an empty state prompt.
struct LatestMeasurementCard: View {
    let measurement: Measurement?
    let onLogMeasurement: () -> Void

    var body: some View {
        if let measurement {
            Card {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text(NSLocalizedString("Latest Measurement", comment: ""))
                            .appFont(.headline)
                        Spacer()
                        Text(measurement.date, format: .dateTime.month(.abbreviated).day().hour().minute())
                            .appFont(.caption)
                            .foregroundStyle(.secondary)
                    }

                    InsetPanel(tint: measurement.type.tint) {
                        measurementRow(measurement)
                    }

                }
            }
        } else {
            Card {
                EmptyStateView(
                    systemImage: "waveform.path.ecg",
                    title: NSLocalizedString("No measurements yet", comment: ""),
                    subtitle: NSLocalizedString("Use the top-right menu to log your first blood pressure, glucose, weight, or heart rate reading.", comment: ""),
                    actionTitle: NSLocalizedString("Log Measurement", comment: ""),
                    action: onLogMeasurement
                )
            }
        }
    }

    private func measurementRow(_ m: Measurement) -> some View {
        HStack(spacing: 10) {
            Circle().fill(m.type.tint).frame(width: 8, height: 8)
            Text(m.type.rawValue).appFont(.subheadline)
            Spacer()
            Group {
                if m.type == .bloodPressure, let dia = m.diastolic {
                    Text("\(Int(m.value))/\(Int(dia)) \(m.type.unit)")
                } else if m.type == .bloodGlucose {
                    let v = UnitPreferences.mgdlToPreferred(m.value)
                    let formatted = UnitPreferences.glucoseUnit == .mgdL ? String(format: "%.0f", v) : String(format: "%.1f", v)
                    Text("\(formatted) \(UnitPreferences.glucoseUnit.rawValue)")
                } else {
                    Text("\(String(format: "%.1f", m.value)) \(m.type.unit)")
                }
            }
            .appFont(.subheadline)
            .fontWeight(.medium)
        }
    }
}
