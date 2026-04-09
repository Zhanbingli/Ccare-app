import SwiftUI

struct DrugInteractionView: View {
    @EnvironmentObject var store: DataStore
    @State private var isAnalyzing = false
    @State private var analysisResult: DrugInteractionResponse?
    @State private var errorMessage: String?
    @State private var showSettings = false
    @State private var hasConsent = AIService.shared.hasUserConsent

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    headerCard

                    if store.medications.isEmpty {
                        emptyStateView
                    } else {
                        medicationListSection

                        analyzeButton

                        if isAnalyzing {
                            loadingView
                        }

                        if let error = errorMessage {
                            errorView(message: error)
                        }

                        if let result = analysisResult {
                            analysisResultView(result: result)
                        }
                    }
                }
                .padding()
            }
            .navigationTitle(NSLocalizedString("Drug Interactions", comment: ""))
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showSettings = true
                    } label: {
                        Image(systemName: "gear")
                    }
                }
            }
            .sheet(isPresented: $showSettings) {
                AISettingsView(onSave: { hasConsent = AIService.shared.hasUserConsent })
            }
            .onChange(of: showSettings) { newValue in
                if !newValue {
                    hasConsent = AIService.shared.hasUserConsent
                }
            }
        }
    }

    private var headerCard: some View {
        TintedCard(tint: .purple) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: "brain.head.profile")
                        .font(.system(size: 28))
                        .foregroundStyle(.white)
                    Spacer()
                }
                Text(NSLocalizedString("AI Drug Interaction Analysis", comment: ""))
                    .appFont(.headline)
                    .foregroundStyle(.white)
                Text(NSLocalizedString("Powered by AI to analyze medication interactions, effects, and side effects", comment: ""))
                    .appFont(.subheadline)
                    .foregroundStyle(.white.opacity(0.9))
                if !hasConsent {
                    Text(NSLocalizedString("To protect your privacy, analysis is disabled until you allow sending medication info to your chosen AI provider in Settings.", comment: ""))
                        .appFont(.caption)
                        .foregroundStyle(.white.opacity(0.85))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "pills")
                .font(.system(size: 60))
                .foregroundStyle(.secondary)
            Text(NSLocalizedString("No medications added", comment: ""))
                .appFont(.headline)
                .foregroundStyle(.secondary)
            Text(NSLocalizedString("Add medications to analyze drug interactions", comment: ""))
                .appFont(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
    }

    private var medicationListSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(String(format: NSLocalizedString("Current Medications (%lld)", comment: ""), store.medications.count))
                .appFont(.headline)
                .foregroundStyle(.primary)

            VStack(spacing: 8) {
                ForEach(store.medications) { med in
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(med.name)
                                .appFont(.subheadline)
                                .foregroundStyle(.primary)
                            Text(med.dose)
                                .appFont(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if let categoryName = med.displayCategoryName {
                            Text(categoryName)
                                .appFont(.caption)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Capsule().fill(Color.accentColor.opacity(0.15)))
                                .foregroundStyle(Color.accentColor)
                        }
                    }
                    .padding(12)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color(.secondarySystemBackground))
                    )
                }
            }
        }
    }

    private var analyzeButton: some View {
        Button {
            analyzeInteractions()
        } label: {
            HStack {
                Image(systemName: "wand.and.stars")
                Text(NSLocalizedString("Analyze Interactions", comment: ""))
            }
            .frame(maxWidth: .infinity)
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.accentColor)
            )
            .foregroundStyle(.white)
        }
        .disabled(isAnalyzing || store.medications.count < 2 || !hasConsent)
        .overlay {
            if !hasConsent {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color.orange.opacity(0.8), lineWidth: 1)
            } else { EmptyView() }
        }
    }

    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.5)
            Text(NSLocalizedString("Analyzing drug interactions...", comment: ""))
                .appFont(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }

    private func errorView(message: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 6) {
                Text(NSLocalizedString("Error", comment: ""))
                    .appFont(.subheadline)
                    .foregroundStyle(.primary)
                Text(message)
                    .appFont(.caption)
                    .foregroundStyle(.secondary)
                if message.contains("allow sending") {
                    Button {
                        showSettings = true
                    } label: {
                        Label("Open AI Settings", systemImage: "gear")
                            .appFont(.caption)
                    }
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.orange.opacity(0.1))
        )
    }

    private func analysisResultView(result: DrugInteractionResponse) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            // Overall Analysis
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: "doc.text.fill")
                        .foregroundStyle(.blue)
                    Text(NSLocalizedString("Overall Analysis", comment: ""))
                        .appFont(.headline)
                }
                Text(result.analysis)
                    .appFont(.body)
                    .foregroundStyle(.primary)
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.blue.opacity(0.1))
            )

            // Interactions
            if !result.interactions.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .foregroundStyle(.purple)
                        Text(String(format: NSLocalizedString("Detected Interactions (%lld)", comment: ""), result.interactions.count))
                            .appFont(.headline)
                    }

                    ForEach(result.interactions) { interaction in
                        interactionCard(interaction: interaction)
                    }
                }
            }

            // Recommendations
            if !result.recommendations.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Image(systemName: "lightbulb.fill")
                            .foregroundStyle(.yellow)
                        Text(NSLocalizedString("Recommendations", comment: ""))
                            .appFont(.headline)
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(Array(result.recommendations.enumerated()), id: \.offset) { index, recommendation in
                            HStack(alignment: .top, spacing: 8) {
                                Text("\(index + 1).")
                                    .appFont(.subheadline)
                                    .foregroundStyle(.secondary)
                                Text(recommendation)
                                    .appFont(.subheadline)
                                    .foregroundStyle(.primary)
                            }
                        }
                    }
                    .padding()
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color(.secondarySystemBackground))
                    )
                }
            }
        }
    }

    private func interactionCard(interaction: DrugInteractionResponse.Interaction) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header with drugs and severity
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(interaction.drug1)
                            .appFont(.subheadline)
                            .foregroundStyle(.primary)
                        Image(systemName: "arrow.left.and.right")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(interaction.drug2)
                            .appFont(.subheadline)
                            .foregroundStyle(.primary)
                    }
                }
                Spacer()
                severityBadge(severity: interaction.severity)
            }

            Divider()

            // Description
            Text(interaction.description)
                .appFont(.body)
                .foregroundStyle(.primary)

            // Effects
            if !interaction.effects.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.caption)
                            .foregroundStyle(.green)
                        Text(NSLocalizedString("Therapeutic Effects", comment: ""))
                            .appFont(.caption)
                            .foregroundStyle(.secondary)
                    }
                    ForEach(interaction.effects, id: \.self) { effect in
                        HStack(alignment: .top, spacing: 6) {
                            Text("•")
                                .foregroundStyle(.secondary)
                            Text(effect)
                                .appFont(.caption)
                                .foregroundStyle(.primary)
                        }
                    }
                }
                .padding(10)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.green.opacity(0.08))
                )
            }

            // Side Effects
            if !interaction.sideEffects.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundStyle(.orange)
                        Text(NSLocalizedString("Potential Side Effects", comment: ""))
                            .appFont(.caption)
                            .foregroundStyle(.secondary)
                    }
                    ForEach(interaction.sideEffects, id: \.self) { sideEffect in
                        HStack(alignment: .top, spacing: 6) {
                            Text("•")
                                .foregroundStyle(.secondary)
                            Text(sideEffect)
                                .appFont(.caption)
                                .foregroundStyle(.primary)
                        }
                    }
                }
                .padding(10)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.orange.opacity(0.08))
                )
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(.secondarySystemBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(severityColor(severity: interaction.severity).opacity(0.3), lineWidth: 2)
        )
    }

    private func severityBadge(severity: DrugInteractionResponse.Interaction.Severity) -> some View {
        Text(severity.rawValue)
            .appFont(.caption)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(
                Capsule().fill(severityColor(severity: severity).opacity(0.2))
            )
            .foregroundStyle(severityColor(severity: severity))
    }

    private func severityColor(severity: DrugInteractionResponse.Interaction.Severity) -> Color {
        switch severity {
        case .low:
            return .green
        case .moderate:
            return .yellow
        case .high:
            return .orange
        case .severe:
            return .red
        }
    }

    private func analyzeInteractions() {
        errorMessage = nil
        analysisResult = nil
        isAnalyzing = true

        Task {
            do {
                let result = try await AIService.shared.analyzeDrugInteractions(medications: store.medications)
                await MainActor.run {
                    self.analysisResult = result
                    self.isAnalyzing = false
                    Haptics.success()
                }
            } catch {
                await MainActor.run {
                    self.errorMessage = error.localizedDescription
                    self.isAnalyzing = false
                    Haptics.error()
                }
            }
        }
    }
}

struct AISettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var provider: AIProvider
    @State private var apiKey: String
    @State private var showingSaveConfirmation = false
    @State private var optIn: Bool
    var onSave: (() -> Void)?
    private let openAIKeyURL = URL(string: "https://platform.openai.com/api-keys")
    private let anthropicKeyURL = URL(string: "https://console.anthropic.com/")

    init(onSave: (() -> Void)? = nil) {
        let config = AIService.shared.getConfiguration()
        _provider = State(initialValue: config.provider)
        _apiKey = State(initialValue: config.apiKey)
        _optIn = State(initialValue: AIService.shared.hasUserConsent)
        self.onSave = onSave
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("AI Provider", selection: $provider) {
                        ForEach(AIProvider.allCases, id: \.self) { provider in
                            Text(provider.rawValue).tag(provider)
                        }
                    }
                } header: {
                    Text(NSLocalizedString("Provider", comment: ""))
                } footer: {
                    Text(NSLocalizedString("Choose between OpenAI or Anthropic for drug interaction analysis", comment: ""))
                }

                Section {
                    SecureField("API Key", text: $apiKey)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                } header: {
                    Text(NSLocalizedString("API Key", comment: ""))
                } footer: {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(NSLocalizedString("Your API key is stored securely on your device and never shared", comment: ""))
                        if provider == .openai, let openAIKeyURL {
                            Link("Get OpenAI API Key →", destination: openAIKeyURL)
                        } else if provider == .anthropic, let anthropicKeyURL {
                            Link("Get Anthropic API Key →", destination: anthropicKeyURL)
                        }
                    }
                }

                Section {
                    Toggle(isOn: $optIn) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(NSLocalizedString("Allow sending medication data for analysis", comment: ""))
                            Text(NSLocalizedString("Medication names, doses, and categories are sent to the selected provider. No health measurements are sent.", comment: ""))
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                } footer: {
                    Text(NSLocalizedString("Analysis is blocked until you opt in. You can turn this off anytime.", comment: ""))
                }

                Section {
                    VStack(alignment: .leading, spacing: 12) {
                        Label(NSLocalizedString("Privacy Notice", comment: ""), systemImage: "lock.shield.fill")
                            .appFont(.subheadline)
                            .foregroundStyle(.blue)
                        Text(NSLocalizedString("Your medication data is sent to the selected AI provider for analysis. The analysis is performed in real-time and is not stored by the AI provider. Your API key ensures secure, direct communication.", comment: ""))
                            .appFont(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle(NSLocalizedString("AI Settings", comment: ""))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        saveConfiguration()
                        showingSaveConfirmation = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                            dismiss()
                        }
                    }
                    .disabled(apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !optIn)
                }
            }
            .alert(NSLocalizedString("Settings Saved", comment: ""), isPresented: $showingSaveConfirmation) {
                Button(NSLocalizedString("OK", comment: "")) { }
            } message: {
                Text(NSLocalizedString("Your AI configuration has been updated successfully", comment: ""))
            }
        }
    }

    private func saveConfiguration() {
        let config = AIConfiguration(provider: provider, apiKey: apiKey)
        AIService.shared.updateConfiguration(config)
        AIService.shared.hasUserConsent = optIn
        onSave?()
        Haptics.success()
    }
}

#Preview {
    DrugInteractionView()
        .environmentObject(DataStore())
}
