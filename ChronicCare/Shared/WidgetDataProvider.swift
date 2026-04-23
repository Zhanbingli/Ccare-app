import Foundation
import os

private let logger = Logger(subsystem: "ChronicCare", category: "WidgetData")

/// Lightweight snapshot the widget reads — pre-computed by the main app.
struct WidgetData: Codable {
    var nextDose: WidgetDoseEntry?
    var upcomingDoses: [WidgetDoseEntry]
    var todayTaken: Int
    var todayTotal: Int
    var lastUpdated: Date
}

struct WidgetDoseEntry: Codable, Identifiable {
    var id: UUID = UUID()
    var medicationName: String
    var dose: String
    var scheduledTime: Date
    var medicationID: UUID
}

enum WidgetDataProvider {
    static let appGroupID = "group.ccare"
    private static let widgetFileProtection: Data.WritingOptions = [.atomic, .completeFileProtectionUntilFirstUserAuthentication]

    static var sharedContainerURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupID)
    }

    static var widgetDataURL: URL? {
        sharedContainerURL?.appendingPathComponent("widget_data.json")
    }

    static func write(_ data: WidgetData) {
        guard let url = widgetDataURL else { return }
        do {
            let encoded = try JSONEncoder().encode(data)
            try encoded.write(to: url, options: widgetFileProtection)
            try? (url as NSURL).setResourceValue(true, forKey: .isExcludedFromBackupKey)
        } catch {
            logger.error("Failed to write widget data: \(error.localizedDescription)")
        }
    }

    static func read() -> WidgetData? {
        guard let url = widgetDataURL,
              let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(WidgetData.self, from: data)
    }

}
