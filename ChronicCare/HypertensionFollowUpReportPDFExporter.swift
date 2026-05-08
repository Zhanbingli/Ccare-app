import Foundation
import UIKit

enum HypertensionFollowUpReportPDFExporter {
    static func generate(report: HypertensionFollowUpReport, aiDraft: HypertensionFollowUpLLMDraft? = nil) throws -> URL {
        let generatedAt = Date()
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("Ccare_Hypertension_Report_\(Int(generatedAt.timeIntervalSince1970)).pdf")

        let bounds = CGRect(x: 0, y: 0, width: 612, height: 792)
        let margin: CGFloat = 42
        let renderer = UIGraphicsPDFRenderer(bounds: bounds)

        let titleAttrs: [NSAttributedString.Key: Any] = [.font: UIFont.boldSystemFont(ofSize: 22)]
        let sectionAttrs: [NSAttributedString.Key: Any] = [.font: UIFont.boldSystemFont(ofSize: 14)]
        let bodyAttrs: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 10.5)]
        let smallAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 9.5),
            .foregroundColor: UIColor.secondaryLabel
        ]
        let warningAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 10.5),
            .foregroundColor: UIColor(red: 0xC0 / 255.0, green: 0x45 / 255.0, blue: 0x45 / 255.0, alpha: 1)
        ]

        let data = renderer.pdfData { context in
            var y: CGFloat = 0

            func beginPageIfNeeded(_ needed: CGFloat) {
                if y == 0 {
                    context.beginPage()
                    y = margin
                } else if y + needed > bounds.height - margin {
                    context.beginPage()
                    y = margin
                }
            }

            func drawWrapped(
                _ text: String,
                attributes: [NSAttributedString.Key: Any] = bodyAttrs,
                indent: CGFloat = 0,
                after: CGFloat = 5
            ) {
                let width = bounds.width - margin * 2 - indent
                let rect = (text as NSString).boundingRect(
                    with: CGSize(width: width, height: CGFloat.greatestFiniteMagnitude),
                    options: [.usesLineFragmentOrigin, .usesFontLeading],
                    attributes: attributes,
                    context: nil
                )
                let height = ceil(rect.height) + 2
                beginPageIfNeeded(height + after)
                (text as NSString).draw(
                    with: CGRect(x: margin + indent, y: y, width: width, height: height),
                    options: [.usesLineFragmentOrigin, .usesFontLeading],
                    attributes: attributes,
                    context: nil
                )
                y += height + after
            }

            func drawSeparator() {
                beginPageIfNeeded(12)
                let path = UIBezierPath()
                path.move(to: CGPoint(x: margin, y: y))
                path.addLine(to: CGPoint(x: bounds.width - margin, y: y))
                UIColor.separator.setStroke()
                path.lineWidth = 0.5
                path.stroke()
                y += 10
            }

            func drawSection(_ title: String) {
                beginPageIfNeeded(28)
                y += 4
                drawWrapped(title.uppercased(), attributes: sectionAttrs, after: 4)
                drawSeparator()
            }

            func drawBullet(_ text: String, warning: Bool = false) {
                drawWrapped("- \(text)", attributes: warning ? warningAttrs : bodyAttrs, indent: 8, after: 4)
            }

            drawWrapped(NSLocalizedString("Hypertension follow-up report", comment: "Hypertension report heading"), attributes: titleAttrs, after: 8)
            drawWrapped(String(format: NSLocalizedString("Generated: %@", comment: "Hypertension report share generated"), dateTime(report.generatedAt)), attributes: smallAttrs, after: 2)
            drawWrapped(String(format: NSLocalizedString("Period: %@ to %@", comment: "Hypertension report share period"), date(report.periodStart), date(report.periodEnd)), attributes: smallAttrs, after: 2)
            if let visitTitle = report.visitTitle {
                drawWrapped(String(format: NSLocalizedString("Visit: %@", comment: "Hypertension report share visit"), visitTitle), attributes: smallAttrs, after: 6)
            }

            drawSection(NSLocalizedString("Rule-Based Safety Signals", comment: "Hypertension report section"))
            if report.redFlags.isEmpty {
                drawBullet(NSLocalizedString("No rule-based safety signal in this report period.", comment: "Hypertension report share empty safety"))
            } else {
                for flag in report.redFlags {
                    drawBullet("\(flag.title): \(flag.detail)", warning: flag.severity == .urgent)
                }
            }

            drawSection(NSLocalizedString("Doctor-Facing Summary", comment: "Hypertension report section"))
            for line in report.doctorSummaryLines {
                drawBullet(line)
            }

            drawSection(NSLocalizedString("Patient Prep", comment: "Hypertension report section"))
            if report.patientInsights.isEmpty {
                drawBullet(NSLocalizedString("No strong pattern detected yet. Keep recording blood pressure, medication intake, and symptoms before the visit.", comment: "Hypertension report empty insights"))
            } else {
                for insight in report.patientInsights {
                    drawBullet("\(insight.title): \(insight.detail)", warning: insight.severity == .urgent)
                }
            }

            if let patientSummary = aiDraft?.patientSummary {
                drawSection(NSLocalizedString("Patient Prep Notes", comment: "Hypertension report AI patient section"))
                drawBullet(patientSummary)
            }

            drawSection(NSLocalizedString("Questions for Doctor", comment: "Hypertension report section"))
            if aiDraft?.questions.isEmpty == false {
                for question in aiDraft?.questions ?? [] {
                    drawBullet(question)
                }
            } else {
                for question in report.doctorQuestions {
                    drawBullet(question.prompt)
                }
            }

            drawSection(NSLocalizedString("Blood Pressure Appendix", comment: "Hypertension report section"))
            if report.rawBloodPressureRows.isEmpty {
                drawBullet(NSLocalizedString("No blood pressure readings in this report period.", comment: "Hypertension report empty raw data"))
            } else {
                for row in report.rawBloodPressureRows {
                    let value = row.diastolic.map { "\(row.systolic)/\($0) mmHg" } ?? "\(row.systolic) mmHg"
                    let note = row.note?.trimmingCharacters(in: .whitespacesAndNewlines)
                    let suffix = note?.isEmpty == false ? " - \(note!)" : ""
                    drawBullet("\(dateTime(row.date)): \(value)\(suffix)")
                }
            }

            drawSection(NSLocalizedString("Safety Note", comment: "Hypertension report PDF section"))
            drawWrapped(report.disclaimer, attributes: smallAttrs, after: 4)
        }

        try data.write(to: url, options: [.atomic])
        return url
    }

    private static func date(_ value: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: value)
    }

    private static func dateTime(_ value: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: value)
    }
}
