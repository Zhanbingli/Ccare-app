import Foundation
import Security

private enum KeychainHelper {
    static func set(_ value: String, service: String, account: String) {
        let data = value.data(using: .utf8) ?? Data()
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
        let insert: [String: Any] = query.merging([
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ], uniquingKeysWith: { _, new in new })
        SecItemAdd(insert as CFDictionary, nil)
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
}

struct AIConfiguration: Codable {
    var provider: AIProvider
    var apiKey: String

    static var `default`: AIConfiguration {
        AIConfiguration(provider: .openai, apiKey: "")
    }
}

struct DrugInteractionRequest: Codable {
    let medications: [MedicationInfo]

    struct MedicationInfo: Codable {
        let name: String
        let dose: String
        let category: String?
    }
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
        }
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
            "model": "gpt-4o",
            "messages": [
                ["role": "system", "content": "You are a medical expert specializing in pharmacology and drug interactions. Provide detailed analysis of medication interactions, focusing on therapeutic effects and side effects. Always respond in valid JSON format."],
                ["role": "user", "content": prompt]
            ],
            "temperature": 0.7,
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
            "model": "claude-3-5-sonnet-20241022",
            "max_tokens": 4096,
            "messages": [
                [
                    "role": "user",
                    "content": "You are a medical expert specializing in pharmacology and drug interactions. Provide detailed analysis of medication interactions, focusing on therapeutic effects and side effects. Always respond in valid JSON format.\n\n\(prompt)"
                ]
            ],
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
