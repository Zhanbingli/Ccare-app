import SwiftUI
import WidgetKit

struct CcareWidgetEntryView: View {
    @Environment(\.widgetFamily) var family
    var entry: NextDoseEntry

    var body: some View {
        switch family {
        case .systemSmall:
            smallView
        case .systemMedium:
            mediumView
        case .accessoryInline:
            inlineView
        case .accessoryRectangular:
            rectangularView
        default:
            smallView
        }
    }

    // MARK: - System Small

    private var smallView: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "pills.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.blue)
                Text("ChronicCare")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
            }

            if let dose = entry.nextDose {
                Spacer(minLength: 0)
                Text(dose.medicationName)
                    .font(.system(size: 17, weight: .bold))
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
                Text(dose.dose)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                Text(dose.scheduledTime, style: .time)
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.blue)
            } else {
                Spacer()
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 28))
                    .foregroundStyle(.green)
                Text("All done")
                    .font(.system(size: 15, weight: .semibold))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(14)
        .widgetBackground()
    }

    // MARK: - System Medium

    private var mediumView: some View {
        HStack(spacing: 16) {
            // Left: next dose
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Image(systemName: "pills.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.blue)
                    Text("Next Dose")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                }

                if let dose = entry.nextDose {
                    Text(dose.medicationName)
                        .font(.system(size: 17, weight: .bold))
                        .lineLimit(1)
                    Text(dose.dose)
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                    Text(dose.scheduledTime, style: .time)
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.blue)
                } else {
                    Spacer()
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark.seal.fill")
                            .foregroundStyle(.green)
                        Text("All done")
                            .font(.system(size: 15, weight: .semibold))
                    }
                    Spacer()
                }
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)

            // Right: today progress + upcoming
            VStack(alignment: .trailing, spacing: 8) {
                // Progress
                HStack(spacing: 4) {
                    Text("\(entry.todayTaken)")
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .foregroundStyle(.green)
                    Text("/ \(entry.todayTotal)")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.secondary)
                }

                // Upcoming list
                if entry.upcomingDoses.count > 1 {
                    VStack(alignment: .trailing, spacing: 3) {
                        ForEach(entry.upcomingDoses.dropFirst().prefix(2)) { dose in
                            HStack(spacing: 4) {
                                Text(dose.medicationName)
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                Text(dose.scheduledTime, style: .time)
                                    .font(.system(size: 11, weight: .medium, design: .rounded))
                                    .monospacedDigit()
                            }
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .topTrailing)
        }
        .padding(14)
        .widgetBackground()
    }

    // MARK: - Lock Screen Inline

    private var inlineView: some View {
        if let dose = entry.nextDose {
            Label("\(dose.medicationName) \(dose.scheduledTime.formatted(date: .omitted, time: .shortened))", systemImage: "pills.fill")
        } else {
            Label("All doses done", systemImage: "checkmark.circle.fill")
        }
    }

    // MARK: - Lock Screen Rectangular

    private var rectangularView: some View {
        VStack(alignment: .leading, spacing: 2) {
            if let dose = entry.nextDose {
                HStack(spacing: 4) {
                    Image(systemName: "pills.fill")
                        .font(.system(size: 10))
                    Text(dose.medicationName)
                        .font(.system(size: 13, weight: .bold))
                        .lineLimit(1)
                }
                Text("\(dose.dose) · \(dose.scheduledTime.formatted(date: .omitted, time: .shortened))")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                Text("\(entry.todayTaken)/\(entry.todayTotal) today")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            } else {
                HStack(spacing: 4) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 10))
                    Text("All done today")
                        .font(.system(size: 13, weight: .bold))
                }
                Text("\(entry.todayTaken)/\(entry.todayTotal) completed")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Background helper for iOS 17+ containerBackground vs older padding

extension View {
    @ViewBuilder
    func widgetBackground() -> some View {
        if #available(iOSApplicationExtension 17.0, *) {
            self.containerBackground(.fill.tertiary, for: .widget)
        } else {
            self.background(Color(.systemBackground))
        }
    }
}

// MARK: - Previews

#Preview("Small", as: .systemSmall) {
    CcareNextDoseWidget()
} timeline: {
    NextDoseEntry(
        date: Date(),
        nextDose: WidgetDoseEntry(
            medicationName: "Metformin",
            dose: "500mg",
            scheduledTime: Calendar.current.date(bySettingHour: 14, minute: 0, second: 0, of: Date())!,
            medicationID: UUID()
        ),
        upcomingDoses: [],
        todayTaken: 2,
        todayTotal: 5
    )
}

#Preview("Medium", as: .systemMedium) {
    CcareNextDoseWidget()
} timeline: {
    NextDoseEntry(
        date: Date(),
        nextDose: WidgetDoseEntry(
            medicationName: "Metformin",
            dose: "500mg",
            scheduledTime: Calendar.current.date(bySettingHour: 14, minute: 0, second: 0, of: Date())!,
            medicationID: UUID()
        ),
        upcomingDoses: [
            WidgetDoseEntry(medicationName: "Metformin", dose: "500mg", scheduledTime: Calendar.current.date(bySettingHour: 14, minute: 0, second: 0, of: Date())!, medicationID: UUID()),
            WidgetDoseEntry(medicationName: "Amlodipine", dose: "5mg", scheduledTime: Calendar.current.date(bySettingHour: 20, minute: 0, second: 0, of: Date())!, medicationID: UUID()),
            WidgetDoseEntry(medicationName: "Atorvastatin", dose: "20mg", scheduledTime: Calendar.current.date(bySettingHour: 21, minute: 0, second: 0, of: Date())!, medicationID: UUID())
        ],
        todayTaken: 2,
        todayTotal: 5
    )
}
