import Foundation
import PDFKit
import SwiftUI
import UIKit

enum PDFGenerator {
    @MainActor
    static func generateReport(store: DataStore, days: Int = 30) throws -> URL {
        let tmp = FileManager.default.temporaryDirectory
        let url = tmp.appendingPathComponent("ChronicCare_Report_\(Int(Date().timeIntervalSince1970)).pdf")
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

        let data = renderer.pdfData { ctx in
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

            let title = NSLocalizedString("ChronicCare Health Report", comment: "")
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

            // --- Adherence Bar Chart ---
            let scheduledMeds = store.medications.filter { $0.isAsNeeded != true }
            if !scheduledMeds.isEmpty {
                let barHeight: CGFloat = 14
                let spacing: CGFloat = 4
                let chartHeight = CGFloat(scheduledMeds.count) * (barHeight + spacing) + 10
                ensureSpace(chartHeight)
                y += 6
                let maxBarWidth = bounds.width - margin * 2 - 130
                for med in scheduledMeds {
                    let adh = store.adherencePercent(for: med.id, days: days)
                    let barColor: UIColor = adh >= 0.8 ? .systemGreen : adh >= 0.5 ? .systemOrange : .systemRed
                    // Label
                    let label = med.name.count > 15 ? String(med.name.prefix(15)) + "…" : med.name
                    label.draw(at: CGPoint(x: margin, y: y), withAttributes: [.font: UIFont.systemFont(ofSize: 9)])
                    // Bar background
                    let barX = margin + 120
                    UIColor.systemGray5.setFill()
                    UIBezierPath(roundedRect: CGRect(x: barX, y: y + 1, width: maxBarWidth, height: barHeight), cornerRadius: 3).fill()
                    // Bar fill
                    barColor.setFill()
                    let fillWidth = max(2, maxBarWidth * CGFloat(adh))
                    UIBezierPath(roundedRect: CGRect(x: barX, y: y + 1, width: fillWidth, height: barHeight), cornerRadius: 3).fill()
                    // Percentage label
                    let pctStr = String(format: "%.0f%%", adh * 100)
                    pctStr.draw(at: CGPoint(x: barX + fillWidth + 4, y: y), withAttributes: [.font: UIFont.systemFont(ofSize: 9), .foregroundColor: barColor])
                    y += barHeight + spacing
                }
                y += 6
            }

            drawSeparator()

            // --- Medications with Per-Med Adherence & Supply ---
            ensureSpace(30)
            NSLocalizedString("Medications", comment: "").draw(at: CGPoint(x: margin, y: y), withAttributes: sectionAttrs)
            y += 22

            for med in store.medications {
                ensureSpace(60)

                // Medication name and dose
                let medTitle = "\(med.name) — \(med.dose)"
                medTitle.draw(at: CGPoint(x: margin + 10, y: y), withAttributes: subheadAttrs)
                y += 16

                if med.isAsNeeded == true {
                    // PRN meds: show label instead of adherence
                    let prnText = NSLocalizedString("As Needed (PRN)", comment: "")
                    prnText.draw(at: CGPoint(x: margin + 20, y: y), withAttributes: [.font: UIFont.italicSystemFont(ofSize: 11), .foregroundColor: UIColor.systemBlue])
                    y += 15
                } else {
                    // Adherence and streak
                    let medAdh = store.adherencePercent(for: med.id, days: days)
                    let streak = store.currentStreak(for: med.id)
                    let adhText = String(format: NSLocalizedString("Adherence: %.0f%%", comment: ""), medAdh * 100)
                    let streakText = String(format: NSLocalizedString("Streak: %lld days", comment: ""), streak)
                    adhText.draw(at: CGPoint(x: margin + 20, y: y), withAttributes: medAdh >= 0.8 ? greenAttrs : medAdh >= 0.5 ? orangeAttrs : redAttrs)
                    streakText.draw(at: CGPoint(x: margin + 180, y: y), withAttributes: bodyAttrs)
                    y += 15
                }

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
                    if let sysMin = sysValues.min(), let sysMax = sysValues.max() {
                        let sysAvg = Int(sysValues.reduce(0, +) / Double(sysValues.count))
                        let sysText = String(format: NSLocalizedString("Systolic — Min: %lld  Avg: %lld  Max: %lld mmHg", comment: ""), Int(sysMin), sysAvg, Int(sysMax))
                        sysText.draw(at: CGPoint(x: margin + 20, y: y), withAttributes: bodyAttrs)
                        y += 14
                    }
                    if let diaMin = diaValues.min(), let diaMax = diaValues.max() {
                        let diaAvg = Int(diaValues.reduce(0, +) / Double(diaValues.count))
                        let diaText = String(format: NSLocalizedString("Diastolic — Min: %lld  Avg: %lld  Max: %lld mmHg", comment: ""), Int(diaMin), diaAvg, Int(diaMax))
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

                // Mini line chart
                let sorted = typeMeasurements.sorted { $0.date < $1.date }
                if sorted.count >= 2 {
                    let chartW = bounds.width - margin * 2 - 20
                    let chartH: CGFloat = 80
                    ensureSpace(chartH + 16)

                    let chartX = margin + 10
                    let chartY = y
                    // Background
                    UIColor.systemGray6.setFill()
                    UIBezierPath(roundedRect: CGRect(x: chartX, y: chartY, width: chartW, height: chartH), cornerRadius: 4).fill()

                    let vals = sorted.map { $0.value }
                    guard let vMin = vals.min(), let vMax = vals.max() else { continue }
                    let range = vMax - vMin
                    let effectiveRange = range < 1 ? 1.0 : range
                    let padded = effectiveRange * 0.1

                    let path = UIBezierPath()
                    for (i, m) in sorted.enumerated() {
                        let px = chartX + 4 + (chartW - 8) * CGFloat(i) / CGFloat(max(1, sorted.count - 1))
                        let py = chartY + chartH - 4 - (chartH - 8) * CGFloat((m.value - vMin + padded) / (effectiveRange + padded * 2))
                        if i == 0 { path.move(to: CGPoint(x: px, y: py)) }
                        else { path.addLine(to: CGPoint(x: px, y: py)) }
                    }
                    type.tintUIColor.setStroke()
                    path.lineWidth = 1.5
                    path.stroke()

                    // Dot on last point
                    if let last = sorted.last {
                        let px = chartX + chartW - 4
                        let py = chartY + chartH - 4 - (chartH - 8) * CGFloat((last.value - vMin + padded) / (effectiveRange + padded * 2))
                        type.tintUIColor.setFill()
                        UIBezierPath(ovalIn: CGRect(x: px - 3, y: py - 3, width: 6, height: 6)).fill()
                    }

                    y += chartH + 8
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
        try data.write(to: url, options: [.atomic, .completeFileProtection])
        try? (url as NSURL).setResourceValue(true, forKey: .isExcludedFromBackupKey)
        return url
    }
}
