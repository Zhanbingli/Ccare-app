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
        let margin: CGFloat = 40
        let renderer = UIGraphicsPDFRenderer(bounds: bounds)

        let titleAttrs: [NSAttributedString.Key: Any] = [.font: UIFont.boldSystemFont(ofSize: 22)]
        let sectionAttrs: [NSAttributedString.Key: Any] = [.font: UIFont.boldSystemFont(ofSize: 16)]
        let subheadAttrs: [NSAttributedString.Key: Any] = [.font: UIFont.boldSystemFont(ofSize: 13)]
        let bodyAttrs: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 11)]
        let smallAttrs: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 10), .foregroundColor: UIColor.secondaryLabel]
        let greenAttrs: [NSAttributedString.Key: Any] = [.font: UIFont.boldSystemFont(ofSize: 11), .foregroundColor: UIColor.systemGreen]
        let orangeAttrs: [NSAttributedString.Key: Any] = [.font: UIFont.boldSystemFont(ofSize: 11), .foregroundColor: UIColor.systemOrange]
        let redAttrs: [NSAttributedString.Key: Any] = [.font: UIFont.boldSystemFont(ofSize: 11), .foregroundColor: UIColor.systemRed]

        try renderer.writePDF(to: url) { ctx in
            var y: CGFloat = 0

            func ensureSpace(_ needed: CGFloat) {
                if y + needed > bounds.height - 60 {
                    ctx.beginPage()
                    y = margin
                }
            }

            func drawSeparator() {
                let path = UIBezierPath()
                path.move(to: CGPoint(x: margin, y: y))
                path.addLine(to: CGPoint(x: bounds.width - margin, y: y))
                UIColor.separator.setStroke()
                path.lineWidth = 0.5
                path.stroke()
                y += 10
            }

            // --- Page 1: Header ---
            ctx.beginPage()
            y = margin

            let title = NSLocalizedString("Ccare Health Report", comment: "")
            title.draw(at: CGPoint(x: margin, y: y), withAttributes: titleAttrs)
            y += 30

            let dateStr = DateFormatter.localizedString(from: Date(), dateStyle: .long, timeStyle: .short)
            let gen = String(format: NSLocalizedString("Generated: %@", comment: ""), dateStr)
            gen.draw(at: CGPoint(x: margin, y: y), withAttributes: smallAttrs)
            y += 14

            let period = String(format: NSLocalizedString("Report period: Last %lld days", comment: ""), days)
            period.draw(at: CGPoint(x: margin, y: y), withAttributes: smallAttrs)
            y += 20

            drawSeparator()

            // --- Overall Adherence Summary ---
            ensureSpace(60)
            NSLocalizedString("Overall Adherence", comment: "").draw(at: CGPoint(x: margin, y: y), withAttributes: sectionAttrs)
            y += 22

            let adh7 = store.adherencePercent(days: 7)
            let adh30 = store.adherencePercent(days: 30)
            let adhStr7 = String(format: NSLocalizedString("7-day: %.0f%%", comment: ""), adh7 * 100)
            let adhStr30 = String(format: NSLocalizedString("30-day: %.0f%%", comment: ""), adh30 * 100)
            adhStr7.draw(at: CGPoint(x: margin + 10, y: y), withAttributes: adh7 >= 0.8 ? greenAttrs : adh7 >= 0.5 ? orangeAttrs : redAttrs)
            adhStr30.draw(at: CGPoint(x: margin + 160, y: y), withAttributes: adh30 >= 0.8 ? greenAttrs : adh30 >= 0.5 ? orangeAttrs : redAttrs)
            y += 20

            drawSeparator()

            // --- Medications with Per-Med Adherence & Supply ---
            ensureSpace(30)
            NSLocalizedString("Medications", comment: "").draw(at: CGPoint(x: margin, y: y), withAttributes: sectionAttrs)
            y += 22

            for med in store.medications {
                ensureSpace(60)
                let medAdh = store.adherencePercent(for: med.id, days: days)
                let streak = store.currentStreak(for: med.id)

                // Medication name and dose
                let medTitle = "\(med.name) — \(med.dose)"
                medTitle.draw(at: CGPoint(x: margin + 10, y: y), withAttributes: subheadAttrs)
                y += 16

                // Adherence and streak
                let adhText = String(format: NSLocalizedString("Adherence: %.0f%%", comment: ""), medAdh * 100)
                let streakText = String(format: NSLocalizedString("Streak: %lld days", comment: ""), streak)
                adhText.draw(at: CGPoint(x: margin + 20, y: y), withAttributes: medAdh >= 0.8 ? greenAttrs : medAdh >= 0.5 ? orangeAttrs : redAttrs)
                streakText.draw(at: CGPoint(x: margin + 180, y: y), withAttributes: bodyAttrs)
                y += 15

                // Category
                if let catName = med.displayCategoryName {
                    let catText = String(format: NSLocalizedString("Category: %@", comment: ""), catName)
                    catText.draw(at: CGPoint(x: margin + 20, y: y), withAttributes: smallAttrs)
                    y += 13
                }

                // Supply status
                if let remaining = med.pillsRemaining {
                    let supplyText: String
                    if let daysLeft = med.daysOfSupplyRemaining {
                        supplyText = String(format: NSLocalizedString("Supply: %lld pills (~%lld days)", comment: ""), remaining, daysLeft)
                    } else {
                        supplyText = String(format: NSLocalizedString("Supply: %lld pills", comment: ""), remaining)
                    }
                    let attrs = med.isLowSupply ? redAttrs : bodyAttrs
                    supplyText.draw(at: CGPoint(x: margin + 20, y: y), withAttributes: attrs)
                    if med.isLowSupply {
                        let warn = NSLocalizedString(" (Low - refill needed)", comment: "")
                        warn.draw(at: CGPoint(x: margin + 20 + (supplyText as NSString).size(withAttributes: attrs).width, y: y), withAttributes: redAttrs)
                    }
                    y += 15
                }

                // Schedule times
                let timeStrs = med.timesOfDay.compactMap { c -> String? in
                    guard let h = c.hour, let m = c.minute else { return nil }
                    return String(format: "%02d:%02d", h, m)
                }
                if !timeStrs.isEmpty {
                    let schedText = String(format: NSLocalizedString("Schedule: %@", comment: ""), timeStrs.joined(separator: ", "))
                    schedText.draw(at: CGPoint(x: margin + 20, y: y), withAttributes: smallAttrs)
                    y += 13
                }

                y += 6
            }

            if store.medications.isEmpty {
                NSLocalizedString("No medications recorded.", comment: "").draw(at: CGPoint(x: margin + 10, y: y), withAttributes: bodyAttrs)
                y += 18
            }

            drawSeparator()

            // --- Measurement Statistics ---
            ensureSpace(30)
            NSLocalizedString("Measurement Statistics", comment: "").draw(at: CGPoint(x: margin, y: y), withAttributes: sectionAttrs)
            y += 22

            let cutoff = Calendar.current.date(byAdding: .day, value: -days, to: Date())!
            let recentMeasurements = store.measurements.filter { $0.date >= cutoff }

            for type in MeasurementType.allCases {
                let typeMeasurements = recentMeasurements.filter { $0.type == type }
                guard !typeMeasurements.isEmpty else { continue }

                ensureSpace(50)
                type.rawValue.draw(at: CGPoint(x: margin + 10, y: y), withAttributes: subheadAttrs)
                y += 16

                let countText = String(format: NSLocalizedString("Readings: %lld", comment: ""), typeMeasurements.count)
                countText.draw(at: CGPoint(x: margin + 20, y: y), withAttributes: bodyAttrs)
                y += 14

                if type == .bloodPressure {
                    let sysValues = typeMeasurements.map { $0.value }
                    let diaValues = typeMeasurements.compactMap { $0.diastolic }
                    if !sysValues.isEmpty {
                        let sysMin = Int(sysValues.min()!), sysMax = Int(sysValues.max()!), sysAvg = Int(sysValues.reduce(0, +) / Double(sysValues.count))
                        let sysText = String(format: NSLocalizedString("Systolic — Min: %lld  Avg: %lld  Max: %lld mmHg", comment: ""), sysMin, sysAvg, sysMax)
                        sysText.draw(at: CGPoint(x: margin + 20, y: y), withAttributes: bodyAttrs)
                        y += 14
                    }
                    if !diaValues.isEmpty {
                        let diaMin = Int(diaValues.min()!), diaMax = Int(diaValues.max()!), diaAvg = Int(diaValues.reduce(0, +) / Double(diaValues.count))
                        let diaText = String(format: NSLocalizedString("Diastolic — Min: %lld  Avg: %lld  Max: %lld mmHg", comment: ""), diaMin, diaAvg, diaMax)
                        diaText.draw(at: CGPoint(x: margin + 20, y: y), withAttributes: bodyAttrs)
                        y += 14
                    }
                } else {
                    let values = typeMeasurements.map { $0.value }
                    guard let vMin = values.min(), let vMax = values.max() else { continue }
                    let vAvg = values.reduce(0, +) / Double(values.count)

                    let displayValues: (min: String, avg: String, max: String, unit: String)
                    if type == .bloodGlucose {
                        let unit = UnitPreferences.glucoseUnit
                        let fmt = unit == .mgdL ? "%.0f" : "%.1f"
                        displayValues = (
                            String(format: fmt, UnitPreferences.mgdlToPreferred(vMin)),
                            String(format: fmt, UnitPreferences.mgdlToPreferred(vAvg)),
                            String(format: fmt, UnitPreferences.mgdlToPreferred(vMax)),
                            unit.rawValue
                        )
                    } else {
                        displayValues = (
                            String(format: "%.1f", vMin),
                            String(format: "%.1f", vAvg),
                            String(format: "%.1f", vMax),
                            type.unit
                        )
                    }

                    let statsText = String(format: NSLocalizedString("Min: %@  Avg: %@  Max: %@ %@", comment: ""), displayValues.min, displayValues.avg, displayValues.max, displayValues.unit)
                    statsText.draw(at: CGPoint(x: margin + 20, y: y), withAttributes: bodyAttrs)
                    y += 14
                }

                y += 6
            }

            if recentMeasurements.isEmpty {
                NSLocalizedString("No measurements in this period.", comment: "").draw(at: CGPoint(x: margin + 10, y: y), withAttributes: bodyAttrs)
                y += 18
            }

            drawSeparator()

            // --- Recent Measurements List (latest 20) ---
            ensureSpace(30)
            NSLocalizedString("Recent Measurements", comment: "").draw(at: CGPoint(x: margin, y: y), withAttributes: sectionAttrs)
            y += 22

            let df = DateFormatter(); df.dateStyle = .short; df.timeStyle = .short
            let latest = recentMeasurements.sorted(by: { $0.date > $1.date }).prefix(20)
            for m in latest {
                ensureSpace(16)
                let v: String
                if m.type == .bloodPressure, let d = m.diastolic {
                    v = "\(Int(m.value))/\(Int(d)) \(m.type.unit)"
                } else if m.type == .bloodGlucose {
                    let val = UnitPreferences.mgdlToPreferred(m.value)
                    let unit = UnitPreferences.glucoseUnit.rawValue
                    v = UnitPreferences.glucoseUnit == .mgdL ? String(format: "%.0f %@", val, unit) : String(format: "%.1f %@", val, unit)
                } else {
                    v = String(format: "%.1f %@", m.value, m.type.unit)
                }
                let line = "\(m.type.rawValue): \(v)  (\(df.string(from: m.date)))"
                ("  \(line)").draw(at: CGPoint(x: margin + 10, y: y), withAttributes: bodyAttrs)
                y += 14
            }

            // --- Footer ---
            ensureSpace(30)
            y += 10
            drawSeparator()
            let footer = NSLocalizedString("This report is for informational purposes only. Consult your healthcare provider for medical advice.", comment: "")
            footer.draw(at: CGPoint(x: margin, y: y), withAttributes: smallAttrs)
        }
        return url
    }
}
