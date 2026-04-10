import Foundation
@preconcurrency import Vision

struct MedicationOCRSuggestion: Identifiable, Equatable {
    let id = UUID()
    let name: String?
    let dose: String?
    let notes: String?
    let rawText: String

    var hasUsefulContent: Bool {
        !(name?.isEmpty ?? true) || !(dose?.isEmpty ?? true) || !(notes?.isEmpty ?? true)
    }
}

enum MedicationOCRService {
    enum OCRFailure: LocalizedError {
        case unreadableImage
        case noRecognizedText

        var errorDescription: String? {
            switch self {
            case .unreadableImage:
                return NSLocalizedString("The selected image could not be read.", comment: "")
            case .noRecognizedText:
                return NSLocalizedString("No medication text could be recognized from that image.", comment: "")
            }
        }
    }

    static func recognizeMedication(from imageData: Data) async throws -> MedicationOCRSuggestion {
        let lines = try await recognizeLines(from: imageData)
        let suggestion = MedicationLabelParser.parse(recognizedLines: lines)
        guard suggestion.hasUsefulContent || !suggestion.rawText.isEmpty else {
            throw OCRFailure.noRecognizedText
        }
        return suggestion
    }

    private static func recognizeLines(from imageData: Data) async throws -> [String] {
        try await withCheckedThrowingContinuation { continuation in
            let request = VNRecognizeTextRequest { request, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                let observations = request.results as? [VNRecognizedTextObservation] ?? []
                let lines = observations
                    .compactMap { $0.topCandidates(1).first?.string.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
                if lines.isEmpty {
                    continuation.resume(throwing: OCRFailure.noRecognizedText)
                } else {
                    continuation.resume(returning: lines)
                }
            }
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            request.recognitionLanguages = ["en-US", "zh-Hans"]

            do {
                let handler = VNImageRequestHandler(data: imageData)
                try handler.perform([request])
            } catch {
                continuation.resume(throwing: OCRFailure.unreadableImage)
            }
        }
    }
}

enum MedicationLabelParser {
    private static let doseRegex: NSRegularExpression? = {
        let pattern = #"(?ix)\b\d+(?:\.\d+)?(?:\s*\/\s*\d+(?:\.\d+)?)?\s*(?:mg|mcg|ug|g|ml|mL|units?|iu|IU|%)\b"#
        return try? NSRegularExpression(pattern: pattern)
    }()

    private static let instructionPatterns: [(String, String?)] = [
        (#"(?i)\bonce daily\b"#, "Once daily"),
        (#"(?i)\btwice daily\b"#, "Twice daily"),
        (#"(?i)\bthree times daily\b"#, "Three times daily"),
        (#"(?i)\bevery \d+ ?hours?\b"#, nil),
        (#"(?i)\bwith food\b"#, "With food"),
        (#"(?i)\bafter meals?\b"#, "After meals"),
        (#"(?i)\bbefore meals?\b"#, "Before meals"),
        (#"(?i)\bat bedtime\b"#, "At bedtime"),
        (#"(?i)\bas needed\b"#, "As needed"),
        (#"(?i)\bprn\b"#, "As needed"),
    ]

    private static let noiseWords = [
        "tablet", "tablets", "tab", "tabs", "capsule", "capsules", "cap", "caps",
        "prescription", "rx", "doctor", "pharmacy", "label", "instructions",
        "take", "daily", "refill", "route", "qty", "quantity", "patient", "use",
        "mouth", "oral", "generic", "extended", "release", "delayed", "strength",
        "warning", "caution", "keep", "children", "store", "temperature", "lot",
        "batch", "exp", "expires", "manufacturer", "distributed", "dispense",
        "date", "address", "phone", "only", "labeler", "ndc", "barcode"
    ]

    private static let lineRejectPatterns = [
        #"(?i)\b(rx|ndc|lot|batch|exp|expires?|qty|quantity|refills?|pharmacy|doctor|patient|address|phone|barcode|store at|keep out|warning|caution|manufacturer|distributed by)\b"#,
        #"(?i)\b(take|use)\b.*\b(daily|mouth|tablet|capsule|food|bedtime|hours?)\b"#,
        #"^\W*$"#,
        #"^\d[\d\s\-\/:.]*$"#
    ]

    static func parse(recognizedLines: [String]) -> MedicationOCRSuggestion {
        let lines = recognizedLines
            .map { $0.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let rawText = lines.joined(separator: "\n")
        let dose = extractDose(from: lines)
        let name = extractName(from: lines)
        let notes = extractInstructions(from: rawText)

        return MedicationOCRSuggestion(
            name: name,
            dose: dose,
            notes: notes,
            rawText: rawText
        )
    }

    private static func extractDose(from lines: [String]) -> String? {
        guard let doseRegex else { return nil }
        for line in lines {
            if let match = firstMatch(in: line, regex: doseRegex) {
                return match.replacingOccurrences(of: "\\s+", with: "", options: .regularExpression)
                    .replacingOccurrences(of: "ML", with: "mL")
                    .replacingOccurrences(of: "ml", with: "mL")
            }
        }
        return nil
    }

    private static func extractName(from lines: [String]) -> String? {
        guard let doseRegex else { return nil }
        var bestCandidate: (text: String, score: Int)?

        for line in lines {
            guard !shouldRejectNameLine(line) else { continue }

            var candidate = line
            let range = NSRange(candidate.startIndex..<candidate.endIndex, in: candidate)
            candidate = doseRegex.stringByReplacingMatches(in: candidate, options: [], range: range, withTemplate: " ")
            candidate = candidate
                .replacingOccurrences(of: #"[()#,]"#, with: " ", options: .regularExpression)
                .replacingOccurrences(of: #"\b\d+\b"#, with: " ", options: .regularExpression)
                .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)

            let loweredWords = candidate.lowercased().split(separator: " ").map(String.init)
            let wordCount = loweredWords.count
            guard !candidate.isEmpty else { continue }
            guard wordCount <= 4 else { continue }
            guard candidate.range(of: "[A-Za-z\\u4e00-\\u9fff]", options: .regularExpression) != nil else { continue }
            guard candidate.count >= 3 else { continue }
            guard !candidate.contains(":") else { continue }
            guard candidate.filter({ $0.isNumber }).count <= 1 else { continue }

            let penalty = loweredWords.reduce(into: 0) { result, word in
                if noiseWords.contains(word) { result += 3 }
            }
            let alphaCount = candidate.filter { $0.isLetter || $0.isWhitespace }.count
            let score = alphaCount - penalty - max(0, wordCount - 2)
            guard score >= 5 else { continue }

            let cleaned = cleanupMedicationName(candidate)
            guard !cleaned.isEmpty else { continue }
            guard !shouldRejectNameLine(cleaned) else { continue }

            if bestCandidate == nil || score > bestCandidate!.score {
                bestCandidate = (cleaned, score)
            }
        }

        return bestCandidate?.text
    }

    private static func extractInstructions(from text: String) -> String? {
        var matches: [String] = []
        for (pattern, normalized) in instructionPatterns {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            guard let match = firstMatch(in: text, regex: regex) else { continue }
            let value = normalized ?? match.capitalized
            if !matches.contains(value) {
                matches.append(value)
            }
        }
        return matches.isEmpty ? nil : matches.joined(separator: ", ")
    }

    private static func cleanupMedicationName(_ candidate: String) -> String {
        var cleaned = candidate
        for word in noiseWords {
            cleaned = cleaned.replacingOccurrences(of: "\\b\(NSRegularExpression.escapedPattern(for: word))\\b", with: " ", options: [.regularExpression, .caseInsensitive])
        }
        cleaned = cleaned
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if cleaned == cleaned.uppercased(), cleaned.range(of: "[A-Z]", options: .regularExpression) != nil {
            cleaned = cleaned.lowercased().split(separator: " ").map { word in
                guard let first = word.first else { return "" }
                return first.uppercased() + word.dropFirst()
            }.joined(separator: " ")
        }

        return cleaned
    }

    private static func shouldRejectNameLine(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return true }

        if trimmed.count > 36 { return true }
        for pattern in lineRejectPatterns {
            if trimmed.range(of: pattern, options: .regularExpression) != nil {
                return true
            }
        }

        let lower = trimmed.lowercased()
        let words = lower.split(separator: " ").map(String.init)
        let noiseCount = words.filter { noiseWords.contains($0) }.count
        if noiseCount >= max(1, words.count / 2) { return true }

        return false
    }

    private static func firstMatch(in text: String, regex: NSRegularExpression) -> String? {
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, options: [], range: range),
              let matchRange = Range(match.range, in: text) else { return nil }
        return String(text[matchRange]).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
