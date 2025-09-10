import Foundation
import PDFKit
import SwiftUI
import UIKit

enum PDFGenerator {
    @MainActor
    static func generateReport(store: DataStore, days: Int = 30) throws -> URL {
        let tmp = FileManager.default.temporaryDirectory
        let url = tmp.appendingPathComponent("Ccare_Report_\(Int(Date().timeIntervalSince1970)).pdf")
        let bounds = CGRect(x: 0, y: 0, width: 612, height: 792) // US Letter
        let renderer = UIGraphicsPDFRenderer(bounds: bounds)

        try renderer.writePDF(to: url) { ctx in
            ctx.beginPage()
            let title = "Ccare Health Report"
            title.draw(at: CGPoint(x: 40, y: 40), withAttributes: [.font: UIFont.boldSystemFont(ofSize: 20)])

            let dateStr = DateFormatter.localizedString(from: Date(), dateStyle: .medium, timeStyle: .short)
            ("Generated: " + dateStr).draw(at: CGPoint(x: 40, y: 70), withAttributes: [.font: UIFont.systemFont(ofSize: 12)])

            var y: CGFloat = 110
            let sectionTitleAttrs: [NSAttributedString.Key: Any] = [.font: UIFont.boldSystemFont(ofSize: 16)]
            let bodyAttrs: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 12)]

            // Medications summary
            "Medications".draw(at: CGPoint(x: 40, y: y), withAttributes: sectionTitleAttrs); y += 20
            for m in store.medications {
                ("• \(m.name) — \(m.dose)").draw(at: CGPoint(x: 50, y: y), withAttributes: bodyAttrs); y += 16
            }
            y += 8

            // Last N days measurements summary (latest 20)
            "Recent Measurements".draw(at: CGPoint(x: 40, y: y), withAttributes: sectionTitleAttrs); y += 20
            let start = Calendar.current.date(byAdding: .day, value: -days, to: Date())!
            let ms = store.measurements.filter { $0.date >= start }.sorted(by: { $0.date > $1.date }).prefix(20)
            let df = DateFormatter(); df.dateStyle = .short; df.timeStyle = .short
            for m in ms {
                let v: String
                if m.type == .bloodPressure, let d = m.diastolic {
                    v = "\(Int(m.value))/\(Int(d)) \(m.type.unit)"
                } else {
                    v = String(format: "%.1f %@", m.value, m.type.unit)
                }
                let line = "• \(m.type.rawValue): \(v)  (\(df.string(from: m.date)))"
                line.draw(at: CGPoint(x: 50, y: y), withAttributes: bodyAttrs); y += 16
                if y > bounds.height - 80 { ctx.beginPage(); y = 40 }
            }

            y += 8
            // Adherence summary (last 7 days)
            "Adherence (7 days)".draw(at: CGPoint(x: 40, y: y), withAttributes: sectionTitleAttrs); y += 20
            let weekly = store.weeklyAdherence()
            let pct = weekly.map { $0.1 }.reduce(0, +) / Double(max(1, weekly.count))
            (String(format: "Average: %.0f%%", pct * 100)).draw(at: CGPoint(x: 50, y: y), withAttributes: bodyAttrs); y += 18
            for (day, p) in weekly {
                let ds = DateFormatter.localizedString(from: day, dateStyle: .short, timeStyle: .none)
                ("• \(ds): \(Int(p * 100))%\n").draw(at: CGPoint(x: 50, y: y), withAttributes: bodyAttrs); y += 16
            }
        }
        return url
    }
}
