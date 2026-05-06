import Foundation
import Security
import os

private enum KeychainHelper {
    static func set(_ value: String, service: String, account: String) {
        guard let data = value.data(using: .utf8) else { return }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        let deleteStatus = SecItemDelete(query as CFDictionary)
        guard deleteStatus == errSecSuccess || deleteStatus == errSecItemNotFound else { return }
        let insert: [String: Any] = query.merging([
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ], uniquingKeysWith: { _, new in new })
        let addStatus = SecItemAdd(insert as CFDictionary, nil)
        if addStatus != errSecSuccess {
            os_log(.error, "Keychain save failed: %d", addStatus)
        }
    }

    static func get(service: String, account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }
}

enum AIProvider: String, CaseIterable, Codable {
    case openai = "OpenAI"
    case anthropic = "Anthropic"
    case deepseek = "DeepSeek"
}

struct AIConfiguration: Codable {
    var provider: AIProvider
    var apiKey: String

    static var `default`: AIConfiguration {
        AIConfiguration(provider: .openai, apiKey: "")
    }
}

private enum AIModelCatalog {
    static let openAIJSON = "gpt-4o"
    static let openAIText = "gpt-4o-mini"
    static let anthropicJSON = "claude-sonnet-4-20250514"
    static let anthropicText = "claude-haiku-4-5-20251001"
    static let deepSeekJSON = "deepseek-v4-flash"
    static let deepSeekText = "deepseek-v4-flash"
}

struct DrugInteractionRequest: Codable {
    let medications: [MedicationInfo]

    struct MedicationInfo: Codable {
        let name: String
        let dose: String
        let category: String?
    }
}

struct AITrendInsightRequest {
    let measurementType: String
    let recentMeasurements: [String]
    let relatedMedications: [DrugInteractionRequest.MedicationInfo]
    let latest: String
    let change: String
    let sevenDayAverage: String
    let sevenDayInRange: String
}

struct AIVisitQuestionRequest {
    let localeIdentifier: String
    let visitTitle: String?
    let reason: String?
    let allergies: String?
    let medications: [String]
    let adherenceGaps: [String]
    let measurements: [String]
    let symptoms: [String]
    let previousVisitPlan: [String]
    let followUpChecks: String?
    let missingPostVisitItems: [String]
}

struct DrugInteractionResponse: Codable {
    let analysis: String
    let interactions: [Interaction]
    let recommendations: [String]

    struct Interaction: Codable, Identifiable {
        let id: UUID
        let drug1: String
        let drug2: String
        let severity: Severity
        let description: String
        let effects: [String]
        let sideEffects: [String]

        enum Severity: String, Codable {
            case low = "Low"
            case moderate = "Moderate"
            case high = "High"
            case severe = "Severe"
        }

        init(id: UUID = UUID(), drug1: String, drug2: String, severity: Severity, description: String, effects: [String], sideEffects: [String]) {
            self.id = id
            self.drug1 = drug1
            self.drug2 = drug2
            self.severity = severity
            self.description = description
            self.effects = effects
            self.sideEffects = sideEffects
        }
    }
}

enum AIServiceError: Error, LocalizedError {
    case invalidAPIKey
    case consentRequired
    case networkError(String)
    case invalidResponse
    case rateLimitExceeded
    case invalidJSON(String)

    var errorDescription: String? {
        switch self {
        case .invalidAPIKey:
            return NSLocalizedString("Invalid API key. Please check your settings.", comment: "")
        case .consentRequired:
            return NSLocalizedString("You need to allow sending medication data to the AI provider before analysis.", comment: "")
        case .networkError(let message):
            return String(format: NSLocalizedString("Network error: %@", comment: ""), message)
        case .invalidResponse:
            return NSLocalizedString("Invalid response from AI service.", comment: "")
        case .rateLimitExceeded:
            return NSLocalizedString("Rate limit exceeded. Please try again later.", comment: "")
        case .invalidJSON(let message):
            return String(format: NSLocalizedString("Failed to parse response: %@", comment: ""), message)
        }
    }
}

class AIService {
    static let shared = AIService()
    private init() {}

    private let keychainService = "ChronicCare.AI"
    private let keychainAccount = "apiKey"
    private let optInKey = "ai.optIn"

    private var apiKey: String {
        get {
            if let key = KeychainHelper.get(service: keychainService, account: keychainAccount) {
                return key
            }
            // Migration: try to read legacy stored config
            if let data = UserDefaults.standard.data(forKey: "AIConfiguration"),
               let legacy = try? JSONDecoder().decode(AIConfiguration.self, from: data) {
                KeychainHelper.set(legacy.apiKey, service: keychainService, account: keychainAccount)
                return legacy.apiKey
            }
            return ""
        }
        set {
            KeychainHelper.set(newValue, service: keychainService, account: keychainAccount)
        }
    }

    var hasUserConsent: Bool {
        get { UserDefaults.standard.bool(forKey: optInKey) }
        set { UserDefaults.standard.set(newValue, forKey: optInKey) }
    }

    private var configuration: AIConfiguration {
        get {
            let providerRaw = UserDefaults.standard.data(forKey: "AIConfiguration")
                .flatMap { try? JSONDecoder().decode(AIConfiguration.self, from: $0) }?.provider ?? .openai
            return AIConfiguration(provider: providerRaw, apiKey: apiKey)
        }
        set {
            apiKey = newValue.apiKey
            if let data = try? JSONEncoder().encode(AIConfiguration(provider: newValue.provider, apiKey: "")) {
                UserDefaults.standard.set(data, forKey: "AIConfiguration")
            }
        }
    }

    func updateConfiguration(_ config: AIConfiguration) {
        self.configuration = config
    }

    func getConfiguration() -> AIConfiguration {
        return configuration
    }

    var isConfigured: Bool {
        !configuration.apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func testConfiguration(_ config: AIConfiguration) async throws {
        let key = config.apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else {
            throw AIServiceError.invalidAPIKey
        }

        let prompt = "Reply with only: OK"
        switch config.provider {
        case .openai:
            _ = try await generateOpenAIText(prompt: prompt, apiKey: key, maxTokens: 8)
        case .anthropic:
            _ = try await generateAnthropicText(prompt: prompt, apiKey: key, maxTokens: 8)
        case .deepseek:
            _ = try await generateDeepSeekText(prompt: prompt, apiKey: key, maxTokens: 8)
        }
    }

    func analyzeDrugInteractions(medications: [Medication]) async throws -> DrugInteractionResponse {
        guard hasUserConsent else {
            throw AIServiceError.consentRequired
        }
        guard !configuration.apiKey.isEmpty else {
            throw AIServiceError.invalidAPIKey
        }

        let medicationInfos = medications.map { med in
            DrugInteractionRequest.MedicationInfo(
                name: med.name,
                dose: med.dose,
                category: med.category?.displayName
            )
        }

        let request = DrugInteractionRequest(medications: medicationInfos)

        switch configuration.provider {
        case .openai:
            return try await analyzeWithOpenAI(request: request)
        case .anthropic:
            return try await analyzeWithAnthropic(request: request)
        case .deepseek:
            return try await analyzeWithDeepSeek(request: request)
        }
    }

    func analyzeTrendInsights(_ request: AITrendInsightRequest) async throws -> String {
        guard hasUserConsent else {
            throw AIServiceError.consentRequired
        }
        guard !configuration.apiKey.isEmpty else {
            throw AIServiceError.invalidAPIKey
        }

        let prompt = createTrendPrompt(request)
        switch configuration.provider {
        case .openai:
            return try await generateOpenAIText(prompt: prompt)
        case .anthropic:
            return try await generateAnthropicText(prompt: prompt)
        case .deepseek:
            return try await generateDeepSeekText(prompt: prompt)
        }
    }

    func draftVisitQuestions(_ request: AIVisitQuestionRequest) async throws -> [String] {
        guard hasUserConsent else {
            throw AIServiceError.consentRequired
        }
        guard !configuration.apiKey.isEmpty else {
            throw AIServiceError.invalidAPIKey
        }

        let prompt = createVisitQuestionPrompt(request)
        let text: String
        switch configuration.provider {
        case .openai:
            text = try await generateOpenAIText(prompt: prompt)
        case .anthropic:
            text = try await generateAnthropicText(prompt: prompt)
        case .deepseek:
            text = try await generateDeepSeekText(prompt: prompt)
        }

        let questions = parseQuestionLines(text)
        guard !questions.isEmpty else {
            throw AIServiceError.invalidResponse
        }
        return Array(questions.prefix(3))
    }

    func draftHypertensionFollowUpReport(_ context: HypertensionFollowUpLLMContext) async throws -> HypertensionFollowUpLLMDraft {
        guard hasUserConsent else {
            throw AIServiceError.consentRequired
        }
        guard !configuration.apiKey.isEmpty else {
            throw AIServiceError.invalidAPIKey
        }

        let prompt = try createHypertensionFollowUpPrompt(context)
        let text: String
        switch configuration.provider {
        case .openai:
            text = try await generateOpenAIText(prompt: prompt, maxTokens: 900)
        case .anthropic:
            text = try await generateAnthropicText(prompt: prompt, maxTokens: 900)
        case .deepseek:
            text = try await generateDeepSeekText(prompt: prompt, maxTokens: 900)
        }

        return try parseHypertensionDraft(text)
    }

    private func analyzeWithOpenAI(request: DrugInteractionRequest) async throws -> DrugInteractionResponse {
        let url = URL(string: "https://api.openai.com/v1/chat/completions")!
        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("Bearer \(configuration.apiKey)", forHTTPHeaderField: "Authorization")
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.timeoutInterval = 30

        let prompt = createAnalysisPrompt(medications: request.medications)

        let body: [String: Any] = [
            "model": AIModelCatalog.openAIJSON,
            "messages": [
                ["role": "system", "content": "You summarize possible medication interaction risks for patient self-management. Do not diagnose, do not recommend starting or stopping medication, and always advise discussing changes with a licensed clinician. Always respond in valid JSON format."],
                ["role": "user", "content": prompt]
            ],
            "temperature": 0.2,
            "response_format": ["type": "json_object"]
        ]

        urlRequest.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: urlRequest)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw AIServiceError.networkError("Invalid response")
        }

        if httpResponse.statusCode == 429 {
            throw AIServiceError.rateLimitExceeded
        }

        guard httpResponse.statusCode == 200 else {
            let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw AIServiceError.networkError("HTTP \(httpResponse.statusCode): \(errorMessage)")
        }

        return try parseOpenAIResponse(data: data)
    }

    private func analyzeWithDeepSeek(request: DrugInteractionRequest) async throws -> DrugInteractionResponse {
        let url = URL(string: "https://api.deepseek.com/chat/completions")!
        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("Bearer \(configuration.apiKey)", forHTTPHeaderField: "Authorization")
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.timeoutInterval = 30

        let prompt = createAnalysisPrompt(medications: request.medications)

        let body: [String: Any] = [
            "model": AIModelCatalog.deepSeekJSON,
            "messages": [
                ["role": "system", "content": "You summarize possible medication interaction risks for patient self-management. Do not diagnose, do not recommend starting or stopping medication, and always advise discussing changes with a licensed clinician. Always respond in valid JSON format."],
                ["role": "user", "content": prompt]
            ],
            "temperature": 0.2,
            "response_format": ["type": "json_object"]
        ]

        urlRequest.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: urlRequest)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw AIServiceError.networkError("Invalid response")
        }

        if httpResponse.statusCode == 429 {
            throw AIServiceError.rateLimitExceeded
        }

        guard httpResponse.statusCode == 200 else {
            let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw AIServiceError.networkError("HTTP \(httpResponse.statusCode): \(errorMessage)")
        }

        return try parseOpenAIResponse(data: data)
    }

    private func analyzeWithAnthropic(request: DrugInteractionRequest) async throws -> DrugInteractionResponse {
        let url = URL(string: "https://api.anthropic.com/v1/messages")!
        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue(configuration.apiKey, forHTTPHeaderField: "x-api-key")
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        urlRequest.timeoutInterval = 30

        let prompt = createAnalysisPrompt(medications: request.medications)

        let body: [String: Any] = [
            "model": AIModelCatalog.anthropicJSON,
            "max_tokens": 4096,
            "system": "You summarize possible medication interaction risks for patient self-management. Do not diagnose, do not recommend starting or stopping medication, and always advise discussing changes with a licensed clinician. Always respond in valid JSON format.",
            "messages": [
                [
                    "role": "user",
                    "content": prompt
                ]
            ]
        ]

        urlRequest.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: urlRequest)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw AIServiceError.networkError("Invalid response")
        }

        if httpResponse.statusCode == 429 {
            throw AIServiceError.rateLimitExceeded
        }

        guard httpResponse.statusCode == 200 else {
            let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw AIServiceError.networkError("HTTP \(httpResponse.statusCode): \(errorMessage)")
        }

        return try parseAnthropicResponse(data: data)
    }

    private func createAnalysisPrompt(medications: [DrugInteractionRequest.MedicationInfo]) -> String {
        let medList = medications.map { "- \($0.name) (\($0.dose))\($0.category.map { " - \($0)" } ?? "")" }.joined(separator: "\n")

        return """
        Analyze the following medications for potential drug interactions, therapeutic effects, and side effects:

        \(medList)

        Provide a comprehensive analysis in the following JSON format:
        {
          "analysis": "Overall summary of the medication regimen and key findings",
          "interactions": [
            {
              "drug1": "Name of first medication",
              "drug2": "Name of second medication",
              "severity": "Low|Moderate|High|Severe",
              "description": "Detailed description of the interaction",
              "effects": ["List of therapeutic effects or interaction outcomes"],
              "sideEffects": ["List of potential side effects from this interaction"]
            }
          ],
          "recommendations": ["List of clinical recommendations and monitoring suggestions"]
        }

        Focus on:
        1. Drug-drug interactions and their clinical significance
        2. Therapeutic effects and expected outcomes
        3. Common and serious side effects
        4. Monitoring recommendations
        5. Timing considerations (if any drugs should be taken separately)

        Be thorough but concise. Prioritize patient safety.
        """
    }

    private func createTrendPrompt(_ request: AITrendInsightRequest) -> String {
        let measurements = request.recentMeasurements.joined(separator: "\n")
        let medications = request.relatedMedications.map { med in
            "- \(med.name) (\(med.dose))\(med.category.map { " - \($0)" } ?? "")"
        }.joined(separator: "\n")

        return """
        Review this patient-entered \(request.measurementType) tracking summary.

        Recent readings:
        \(measurements)

        \(medications.isEmpty ? "Related medications: none provided" : "Related medications:\n\(medications)")

        Current stats:
        - Latest: \(request.latest)
        - Change from previous: \(request.change)
        - 7-day average: \(request.sevenDayAverage)
        - 7-day in target range: \(request.sevenDayInRange)

        Write a concise, patient-friendly summary with three short sections:
        1. Pattern
        2. What to watch
        3. Questions for your clinician

        Safety rules:
        - Do not diagnose.
        - Do not recommend changing medication or dose.
        - Mention urgent care only for clearly concerning readings or symptoms.
        - Do not claim certainty from sparse data.
        """
    }

    private func createVisitQuestionPrompt(_ request: AIVisitQuestionRequest) -> String {
        func list(_ title: String, _ values: [String]) -> String {
            guard !values.isEmpty else { return "\(title): none provided" }
            return "\(title):\n" + values.map { "- \($0)" }.joined(separator: "\n")
        }

        return """
        Draft exactly 3 questions this patient can ask their clinician during a follow-up visit.

        Output rules:
        - Return only the 3 questions, one per line.
        - No introduction.
        - Keep each question short and practical.
        - Write in the user's locale: \(request.localeIdentifier).

        Safety rules:
        - Do not diagnose.
        - Do not recommend starting, stopping, or changing medication.
        - Focus on clarifying the clinician's plan, target ranges, monitoring, and follow-up.
        - Use only the data below.

        Visit:
        - Title: \(request.visitTitle ?? "none provided")
        - Reason: \(request.reason ?? "none provided")
        - Allergies: \(request.allergies ?? "none provided")

        \(list("Current medications", request.medications))

        \(list("Adherence gaps", request.adherenceGaps))

        \(list("Home measurements", request.measurements))

        \(list("Symptoms", request.symptoms))

        \(list("Previous visit plan", request.previousVisitPlan))

        Follow-up checks before next visit: \(request.followUpChecks ?? "none provided")

        \(list("Missing post-visit plan items", request.missingPostVisitItems))
        """
    }

    private func createHypertensionFollowUpPrompt(_ context: HypertensionFollowUpLLMContext) throws -> String {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(context)
        let json = String(data: data, encoding: .utf8) ?? "{}"

        return """
        You are drafting bounded follow-up preparation text for a hypertension patient.

        Use only the structured report JSON below.

        Output rules:
        - Return valid JSON only.
        - JSON keys: patientSummary, doctorSummary, questions.
        - patientSummary: 2-4 short patient-facing sentences.
        - doctorSummary: 4-6 concise clinician-facing bullet-like sentences.
        - questions: exactly 3 short questions the patient can ask the clinician.

        Safety rules:
        - Do not diagnose.
        - Do not recommend starting, stopping, or changing medication or dose.
        - Do not tell the user a medication timing change is needed.
        - Use cautious wording such as "may be worth discussing with your doctor".
        - Rule-based red flags are already determined by the app; do not create new red flags.
        - If redFlags are present, preserve their seriousness and do not reassure against them.
        - State that medication decisions should be made with a licensed clinician.

        JSON schema:
        {
          "patientSummary": "string",
          "doctorSummary": "string",
          "questions": ["string", "string", "string"]
        }

        Structured report JSON:
        \(json)
        """
    }

    private func parseQuestionLines(_ text: String) -> [String] {
        text
            .split(whereSeparator: \.isNewline)
            .map { line -> String in
                var value = String(line).trimmingCharacters(in: .whitespacesAndNewlines)
                value = value.replacingOccurrences(
                    of: #"^\s*(?:[-*•]|\d+[\.)、])\s*"#,
                    with: "",
                    options: .regularExpression
                )
                return value.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            .filter { !$0.isEmpty }
    }

    private func parseHypertensionDraft(_ text: String) throws -> HypertensionFollowUpLLMDraft {
        let json = extractJSONObject(from: text)
        guard let data = json.data(using: .utf8) else {
            throw AIServiceError.invalidResponse
        }
        let draft = try JSONDecoder().decode(HypertensionFollowUpLLMDraft.self, from: data)
        let patientSummary = trimmedOrNil(draft.patientSummary)
        let doctorSummary = trimmedOrNil(draft.doctorSummary)
        let questions = draft.questions
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .prefix(3)

        guard patientSummary != nil || doctorSummary != nil || !questions.isEmpty else {
            throw AIServiceError.invalidResponse
        }

        return HypertensionFollowUpLLMDraft(
            patientSummary: patientSummary,
            doctorSummary: doctorSummary,
            questions: Array(questions)
        )
    }

    private func extractJSONObject(from text: String) -> String {
        var value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.hasPrefix("```") {
            value = value
                .replacingOccurrences(of: #"^```(?:json)?\s*"#, with: "", options: .regularExpression)
                .replacingOccurrences(of: #"\s*```$"#, with: "", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        guard let start = value.firstIndex(of: "{"),
              let end = value.lastIndex(of: "}"),
              start <= end else {
            return value
        }
        return String(value[start...end])
    }

    private func trimmedOrNil(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else { return nil }
        return trimmed
    }

    private func generateOpenAIText(prompt: String, apiKey: String? = nil, maxTokens: Int = 500) async throws -> String {
        let url = URL(string: "https://api.openai.com/v1/chat/completions")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey ?? configuration.apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 30

        let body: [String: Any] = [
            "model": AIModelCatalog.openAIText,
            "messages": [
                ["role": "system", "content": "You are a careful health tracking summarizer. Be concise, conservative, and clear that the user should discuss medical decisions with a clinician."],
                ["role": "user", "content": prompt]
            ],
            "temperature": 0.2,
            "max_tokens": maxTokens
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw AIServiceError.networkError("Invalid response")
        }
        if httpResponse.statusCode == 429 {
            throw AIServiceError.rateLimitExceeded
        }
        guard httpResponse.statusCode == 200 else {
            throw AIServiceError.networkError("HTTP \(httpResponse.statusCode)")
        }

        struct OpenAIResponse: Codable {
            struct Choice: Codable {
                struct Message: Codable {
                    let content: String
                }
                let message: Message
            }
            let choices: [Choice]
        }

        let result = try JSONDecoder().decode(OpenAIResponse.self, from: data)
        guard let content = result.choices.first?.message.content.trimmingCharacters(in: .whitespacesAndNewlines),
              !content.isEmpty else {
            throw AIServiceError.invalidResponse
        }
        return content
    }

    private func generateDeepSeekText(prompt: String, apiKey: String? = nil, maxTokens: Int = 500) async throws -> String {
        let url = URL(string: "https://api.deepseek.com/chat/completions")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey ?? configuration.apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 30

        let body: [String: Any] = [
            "model": AIModelCatalog.deepSeekText,
            "messages": [
                ["role": "system", "content": "You are a careful health tracking summarizer. Be concise, conservative, and clear that the user should discuss medical decisions with a clinician."],
                ["role": "user", "content": prompt]
            ],
            "temperature": 0.2,
            "max_tokens": maxTokens
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw AIServiceError.networkError("Invalid response")
        }
        if httpResponse.statusCode == 429 {
            throw AIServiceError.rateLimitExceeded
        }
        guard httpResponse.statusCode == 200 else {
            throw AIServiceError.networkError("HTTP \(httpResponse.statusCode)")
        }

        struct DeepSeekResponse: Codable {
            struct Choice: Codable {
                struct Message: Codable {
                    let content: String
                }
                let message: Message
            }
            let choices: [Choice]
        }

        let result = try JSONDecoder().decode(DeepSeekResponse.self, from: data)
        guard let content = result.choices.first?.message.content.trimmingCharacters(in: .whitespacesAndNewlines),
              !content.isEmpty else {
            throw AIServiceError.invalidResponse
        }
        return content
    }

    private func generateAnthropicText(prompt: String, apiKey: String? = nil, maxTokens: Int = 500) async throws -> String {
        let url = URL(string: "https://api.anthropic.com/v1/messages")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(apiKey ?? configuration.apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.timeoutInterval = 30

        let body: [String: Any] = [
            "model": AIModelCatalog.anthropicText,
            "max_tokens": maxTokens,
            "system": "You are a careful health tracking summarizer. Be concise, conservative, and clear that the user should discuss medical decisions with a clinician.",
            "messages": [
                [
                    "role": "user",
                    "content": prompt
                ]
            ]
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw AIServiceError.networkError("Invalid response")
        }
        if httpResponse.statusCode == 429 {
            throw AIServiceError.rateLimitExceeded
        }
        guard httpResponse.statusCode == 200 else {
            throw AIServiceError.networkError("HTTP \(httpResponse.statusCode)")
        }

        struct AnthropicResponse: Codable {
            struct Content: Codable {
                let text: String
            }
            let content: [Content]
        }

        let result = try JSONDecoder().decode(AnthropicResponse.self, from: data)
        guard let content = result.content.first?.text.trimmingCharacters(in: .whitespacesAndNewlines),
              !content.isEmpty else {
            throw AIServiceError.invalidResponse
        }
        return content
    }

    private func parseOpenAIResponse(data: Data) throws -> DrugInteractionResponse {
        struct OpenAIResponse: Codable {
            struct Choice: Codable {
                struct Message: Codable {
                    let content: String
                }
                let message: Message
            }
            let choices: [Choice]
        }

        let openAIResponse = try JSONDecoder().decode(OpenAIResponse.self, from: data)
        guard let content = openAIResponse.choices.first?.message.content else {
            throw AIServiceError.invalidResponse
        }

        return try parseAnalysisJSON(content)
    }

    private func parseAnthropicResponse(data: Data) throws -> DrugInteractionResponse {
        struct AnthropicResponse: Codable {
            struct Content: Codable {
                let text: String
            }
            let content: [Content]
        }

        let anthropicResponse = try JSONDecoder().decode(AnthropicResponse.self, from: data)
        guard let text = anthropicResponse.content.first?.text else {
            throw AIServiceError.invalidResponse
        }

        return try parseAnalysisJSON(text)
    }

    private func parseAnalysisJSON(_ jsonString: String) throws -> DrugInteractionResponse {
        struct RawResponse: Codable {
            let analysis: String
            let interactions: [RawInteraction]
            let recommendations: [String]

            struct RawInteraction: Codable {
                let drug1: String
                let drug2: String
                let severity: String
                let description: String
                let effects: [String]
                let sideEffects: [String]
            }
        }

        guard let jsonData = jsonString.data(using: .utf8) else {
            throw AIServiceError.invalidJSON("Failed to convert string to data")
        }

        do {
            let rawResponse = try JSONDecoder().decode(RawResponse.self, from: jsonData)

            let interactions = rawResponse.interactions.map { raw in
                let severity: DrugInteractionResponse.Interaction.Severity
                switch raw.severity.lowercased() {
                case "low": severity = .low
                case "moderate": severity = .moderate
                case "high": severity = .high
                case "severe": severity = .severe
                default: severity = .moderate
                }

                return DrugInteractionResponse.Interaction(
                    drug1: raw.drug1,
                    drug2: raw.drug2,
                    severity: severity,
                    description: raw.description,
                    effects: raw.effects,
                    sideEffects: raw.sideEffects
                )
            }

            return DrugInteractionResponse(
                analysis: rawResponse.analysis,
                interactions: interactions,
                recommendations: rawResponse.recommendations
            )
        } catch {
            // Try to salvage JSON object substring if provider wrapped it
            if let start = jsonString.firstIndex(of: "{"),
               let end = jsonString.lastIndex(of: "}") {
                let slice = String(jsonString[start...end])
                if let data = slice.data(using: .utf8),
                   let rawResponse = try? JSONDecoder().decode(RawResponse.self, from: data) {
                    let interactions = rawResponse.interactions.map { raw in
                        let severity: DrugInteractionResponse.Interaction.Severity
                        switch raw.severity.lowercased() {
                        case "low": severity = .low
                        case "moderate": severity = .moderate
                        case "high": severity = .high
                        case "severe": severity = .severe
                        default: severity = .moderate
                        }

                        return DrugInteractionResponse.Interaction(
                            drug1: raw.drug1,
                            drug2: raw.drug2,
                            severity: severity,
                            description: raw.description,
                            effects: raw.effects,
                            sideEffects: raw.sideEffects
                        )
                    }

                    return DrugInteractionResponse(
                        analysis: rawResponse.analysis,
                        interactions: interactions,
                        recommendations: rawResponse.recommendations
                    )
                }
            }
            throw AIServiceError.invalidJSON(error.localizedDescription)
        }
    }
}
