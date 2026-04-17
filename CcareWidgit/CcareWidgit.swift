import WidgetKit
import SwiftUI

struct CcareNextDoseWidget: Widget {
    let kind = "CcareNextDoseWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: NextDoseTimelineProvider()) { entry in
            CcareWidgetEntryView(entry: entry)
        }
        .configurationDisplayName(NSLocalizedString("Next Dose", comment: "Widget display name"))
        .description(NSLocalizedString("Shows your next upcoming medication dose.", comment: "Widget description"))
        .supportedFamilies([
            .systemSmall,
            .systemMedium,
            .accessoryInline,
            .accessoryRectangular
        ])
    }
}
