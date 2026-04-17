import SwiftUI
import WidgetKit

struct CcareWidgetEntryView: View {
    @Environment(\.widgetFamily) var family
    var entry: NextDoseEntry

    private enum WidgetDoseStatus {
        case overdue
        case dueSoon
        case upcoming
        case complete
    }

    private var status: WidgetDoseStatus {
        guard let nextDose = entry.nextDose else { return .complete }
        let now = Date()
        if nextDose.scheduledTime < now {
            return .overdue
        }
        if nextDose.scheduledTime.timeIntervalSince(now) <= 60 * 60 {
            return .dueSoon
        }
        return .upcoming
    }

    private var statusTitle: String {
        switch status {
        case .overdue:
            return NSLocalizedString("Overdue", comment: "Widget status")
        case .dueSoon:
            return NSLocalizedString("Due Soon", comment: "Widget status")
        case .upcoming:
            return NSLocalizedString("Next Dose", comment: "Widget status")
        case .complete:
            return NSLocalizedString("All Caught Up", comment: "Widget status")
        }
    }

    private var statusIcon: String {
        switch status {
        case .overdue:
            return "exclamationmark.circle.fill"
        case .dueSoon, .upcoming:
            return "pills.fill"
        case .complete:
            return "checkmark.circle.fill"
        }
    }

    private var statusColor: Color {
        switch status {
        case .overdue:
            return .red
        case .dueSoon:
            return .orange
        case .upcoming:
            return .blue
        case .complete:
            return .green
        }
    }

    private var progressSummary: String {
        String(format: NSLocalizedString("%lld of %lld taken", comment: "Widget progress"), entry.todayTaken, entry.todayTotal)
    }

    private var upcomingPreviewDoses: [WidgetDoseEntry] {
        guard let nextDose = entry.nextDose else { return [] }
        return Array(entry.upcomingDoses.filter { $0.id != nextDose.id }.prefix(2))
    }

    private var widgetDestinationURL: URL? {
        if let dose = entry.nextDose {
            return URL(string: "chroniccare://medication/\(dose.medicationID.uuidString)")
        }
        return URL(string: "chroniccare://today")
    }

    var body: some View {
        Group {
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
        .widgetURL(widgetDestinationURL)
        .widgetContainerBackground(for: family)
    }

    // MARK: - System Small

    private var smallView: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: statusIcon)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(statusColor)
                Text(statusTitle)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
            }

            if let dose = entry.nextDose {
                Spacer(minLength: 0)
                Text(dose.scheduledTime, style: .time)
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(statusColor)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                VStack(alignment: .leading, spacing: 3) {
                    Text(dose.medicationName)
                        .font(.system(size: 15, weight: .bold))
                        .lineLimit(2)
                        .minimumScaleFactor(0.8)
                    Text(dose.dose)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                Text(progressSummary)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
            } else {
                Spacer(minLength: 0)
                Image(systemName: statusIcon)
                    .font(.system(size: 28))
                    .foregroundStyle(statusColor)
                Text(NSLocalizedString("All done today", comment: "Widget complete"))
                    .font(.system(size: 16, weight: .semibold))
                Text(progressSummary)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(14)
    }

    // MARK: - System Medium

    private var mediumView: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: statusIcon)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(statusColor)
                    Text(statusTitle)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                }

                if let dose = entry.nextDose {
                    Text(dose.scheduledTime, style: .time)
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(statusColor)
                    Text(dose.medicationName)
                        .font(.system(size: 17, weight: .bold))
                        .lineLimit(1)
                    Text(dose.dose)
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                    Text(progressSummary)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                } else {
                    Spacer()
                    HStack(spacing: 6) {
                        Image(systemName: statusIcon)
                            .foregroundStyle(statusColor)
                        Text(NSLocalizedString("All done today", comment: "Widget complete"))
                            .font(.system(size: 18, weight: .semibold))
                    }
                    Text(progressSummary)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                    Spacer()
                }
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)

            VStack(alignment: .leading, spacing: 8) {
                Text(NSLocalizedString("Today", comment: "Widget today label"))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)

                HStack(alignment: .lastTextBaseline, spacing: 4) {
                    Text("\(entry.todayTaken)")
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .foregroundStyle(.green)
                    Text("/ \(entry.todayTotal)")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.secondary)
                }

                if upcomingPreviewDoses.isEmpty {
                    Text(entry.nextDose == nil
                         ? NSLocalizedString("No more doses today", comment: "Widget empty")
                         : NSLocalizedString("No other doses scheduled", comment: "Widget empty"))
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                } else {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(upcomingPreviewDoses) { dose in
                            HStack(spacing: 6) {
                                Text(dose.medicationName)
                                    .font(.system(size: 11))
                                    .lineLimit(1)
                                    .foregroundStyle(.secondary)
                                Spacer(minLength: 4)
                                Text(dose.scheduledTime, style: .time)
                                    .font(.system(size: 11, weight: .medium, design: .rounded))
                                    .monospacedDigit()
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .padding(14)
    }

    // MARK: - Lock Screen Inline

    private var inlineView: some View {
        if let dose = entry.nextDose {
            switch status {
            case .overdue:
                Label(NSLocalizedString("Dose overdue", comment: "Widget inline"), systemImage: statusIcon)
            case .dueSoon, .upcoming:
                Label(
                    String(format: NSLocalizedString("Next %@", comment: "Widget inline next dose time"),
                           dose.scheduledTime.formatted(date: .omitted, time: .shortened)),
                    systemImage: statusIcon
                )
            case .complete:
                Label(NSLocalizedString("All caught up", comment: "Widget inline"), systemImage: statusIcon)
            }
        } else {
            Label(NSLocalizedString("No scheduled dose", comment: "Widget inline"), systemImage: statusIcon)
        }
    }

    // MARK: - Lock Screen Rectangular

    private var rectangularView: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 4) {
                Image(systemName: statusIcon)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(statusColor)
                Text(statusTitle)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.primary)
            }

            if let dose = entry.nextDose {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(dose.scheduledTime, style: .time)
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(statusColor)
                    Text(dose.medicationName)
                        .font(.system(size: 13, weight: .bold))
                        .lineLimit(1)
                        .foregroundStyle(.primary)
                }
                Text(dose.dose)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.primary)
                Text(progressSummary)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            } else {
                HStack(spacing: 4) {
                    Image(systemName: statusIcon)
                        .font(.system(size: 10))
                        .foregroundStyle(statusColor)
                    Text(NSLocalizedString("No scheduled dose", comment: "Widget rectangular"))
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.primary)
                }
                Text(entry.todayTotal > 0
                     ? progressSummary
                     : NSLocalizedString("Open ChronicCare to set up", comment: "Widget empty hint"))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Background helper for iOS 17+ containerBackground vs older padding

extension View {
    @ViewBuilder
    func widgetContainerBackground(for family: WidgetFamily) -> some View {
        if #available(iOSApplicationExtension 17.0, *) {
            self.containerBackground(for: .widget) {
                switch family {
                case .systemSmall, .systemMedium:
                    Color(.tertiarySystemFill)
                default:
                    Color.clear
                }
            }
        } else {
            switch family {
            case .systemSmall, .systemMedium:
                self.padding().background(Color(.systemBackground))
            default:
                self
            }
        }
    }
}

// MARK: - Previews

private enum NextDoseWidgetPreviewData {
    static let nextDoseTime = Calendar.current.date(bySettingHour: 14, minute: 0, second: 0, of: Date())!
    static let eveningDoseTime = Calendar.current.date(bySettingHour: 20, minute: 0, second: 0, of: Date())!
    static let nightDoseTime = Calendar.current.date(bySettingHour: 21, minute: 0, second: 0, of: Date())!

    static let smallEntry = NextDoseEntry(
        date: Date(),
        nextDose: WidgetDoseEntry(
            medicationName: "Metformin",
            dose: "500mg",
            scheduledTime: nextDoseTime,
            medicationID: UUID()
        ),
        upcomingDoses: [],
        todayTaken: 2,
        todayTotal: 5
    )

    static let mediumEntry = NextDoseEntry(
        date: Date(),
        nextDose: WidgetDoseEntry(
            medicationName: "Metformin",
            dose: "500mg",
            scheduledTime: nextDoseTime,
            medicationID: UUID()
        ),
        upcomingDoses: [
            WidgetDoseEntry(medicationName: "Metformin", dose: "500mg", scheduledTime: nextDoseTime, medicationID: UUID()),
            WidgetDoseEntry(medicationName: "Amlodipine", dose: "5mg", scheduledTime: eveningDoseTime, medicationID: UUID()),
            WidgetDoseEntry(medicationName: "Atorvastatin", dose: "20mg", scheduledTime: nightDoseTime, medicationID: UUID())
        ],
        todayTaken: 2,
        todayTotal: 5
    )
}

struct CcareWidgetEntryView_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            CcareWidgetEntryView(entry: NextDoseWidgetPreviewData.smallEntry)
                .previewContext(WidgetPreviewContext(family: .systemSmall))
                .previewDisplayName("Small")

            CcareWidgetEntryView(entry: NextDoseWidgetPreviewData.mediumEntry)
                .previewContext(WidgetPreviewContext(family: .systemMedium))
                .previewDisplayName("Medium")
        }
    }
}
