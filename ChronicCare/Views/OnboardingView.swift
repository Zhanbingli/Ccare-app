import SwiftUI

struct OnboardingView: View {
    @EnvironmentObject var store: DataStore
    var onComplete: () -> Void

    @State private var currentStep: Step = .welcome
    @State private var medName = ""
    @State private var medDose = ""
    @State private var medTime = Calendar.current.date(bySettingHour: 8, minute: 0, second: 0, of: Date()) ?? Date()
    @State private var notificationGranted: Bool?

    private enum Step {
        case welcome, addMedication, notifications, completion
    }

    var body: some View {
        ZStack {
            AppBackground()
            Group {
                switch currentStep {
                case .welcome: welcomeStep
                case .addMedication: addMedicationStep
                case .notifications: notificationStep
                case .completion: completionStep
                }
            }
            .transition(.asymmetric(insertion: .move(edge: .trailing), removal: .move(edge: .leading)))
            .animation(.easeInOut(duration: 0.3), value: currentStep)
        }
        .dynamicTypeSize(.medium ... .accessibility5)
    }

    // MARK: - Step: Welcome

    private var welcomeStep: some View {
        VStack(spacing: 0) {
            Spacer()
            VStack(spacing: 20) {
                Image(systemName: "heart.text.clipboard")
                    .font(.system(size: 72))
                    .foregroundStyle(Color.accentColor)
                    .symbolRenderingMode(.hierarchical)

                Text(NSLocalizedString("ChronicCare", comment: "onboarding"))
                    .appFont(.largeTitle)

                Text(NSLocalizedString("Track medications, log measurements, stay consistent.", comment: "onboarding"))
                    .appFont(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }
            Spacer()
            primaryButton(NSLocalizedString("Get Started", comment: "onboarding")) {
                advance(to: .addMedication)
            }
            skipButton
        }
    }

    // MARK: - Step: Add Medication

    private var addMedicationStep: some View {
        VStack(spacing: 0) {
            header(
                title: NSLocalizedString("Add your first medication", comment: "onboarding"),
                subtitle: NSLocalizedString("You can change or add more anytime.", comment: "onboarding")
            )

            ScrollView {
                VStack(spacing: 14) {
                    Card {
                        VStack(alignment: .leading, spacing: 14) {
                            labeledField(
                                title: NSLocalizedString("Name", comment: ""),
                                text: $medName,
                                placeholder: NSLocalizedString("e.g. Metformin", comment: "")
                            )
                            Divider()
                            labeledField(
                                title: NSLocalizedString("Dose", comment: ""),
                                text: $medDose,
                                placeholder: NSLocalizedString("e.g. 500mg", comment: "")
                            )
                        }
                    }

                    Card {
                        DatePicker(
                            NSLocalizedString("Reminder time", comment: "onboarding"),
                            selection: $medTime,
                            displayedComponents: .hourAndMinute
                        )
                        .appFont(.body)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
            }

            primaryButton(NSLocalizedString("Next", comment: "onboarding")) {
                advance(to: .notifications)
            }
            .disabled(medName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

            skipButton
        }
    }

    // MARK: - Step: Notifications

    private var notificationStep: some View {
        VStack(spacing: 0) {
            Spacer()
            VStack(spacing: 20) {
                Image(systemName: "bell.badge.fill")
                    .font(.system(size: 72))
                    .foregroundStyle(.orange)
                    .symbolRenderingMode(.hierarchical)

                Text(NSLocalizedString("Turn on reminders", comment: "onboarding"))
                    .appFont(.title)

                Text(NSLocalizedString("So you don't miss a dose.", comment: "onboarding"))
                    .appFont(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)

                if let granted = notificationGranted {
                    grantStatusBadge(granted: granted)
                }
            }
            Spacer()

            if notificationGranted == nil {
                primaryButton(NSLocalizedString("Enable Reminders", comment: "onboarding")) {
                    requestNotificationPermission()
                }
            } else {
                primaryButton(NSLocalizedString("Next", comment: "onboarding")) {
                    advance(to: .completion)
                }
            }

            skipButton
        }
    }

    // MARK: - Step: Completion

    private var completionStep: some View {
        VStack(spacing: 0) {
            Spacer()
            VStack(spacing: 20) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 72))
                    .foregroundStyle(.green)
                    .symbolRenderingMode(.hierarchical)

                Text(NSLocalizedString("You're all set", comment: "onboarding"))
                    .appFont(.title)

                Text(completionSubtitle)
                    .appFont(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }
            Spacer()

            primaryButton(NSLocalizedString("Go to Dashboard", comment: "onboarding")) {
                finishOnboarding()
            }
            .padding(.bottom, 48)
        }
    }

    // MARK: - Helpers

    private var completionSubtitle: String {
        let trimmed = medName.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return NSLocalizedString("Add medications anytime from the profile drawer.", comment: "onboarding")
        }
        return String(format: NSLocalizedString("We'll remind you to take %@ on time.", comment: "onboarding"), trimmed)
    }

    private func header(title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .appFont(.title)
            Text(subtitle)
                .appFont(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20)
        .padding(.top, 40)
        .padding(.bottom, 8)
    }

    private func labeledField(title: String, text: Binding<String>, placeholder: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .appFont(.caption)
                .foregroundStyle(.secondary)
            TextField(placeholder, text: text)
                .appFont(.body)
                .textFieldStyle(.plain)
        }
    }

    private func grantStatusBadge(granted: Bool) -> some View {
        HStack(spacing: 8) {
            Image(systemName: granted ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundStyle(granted ? .green : .orange)
            Text(granted
                 ? NSLocalizedString("Reminders enabled", comment: "onboarding")
                 : NSLocalizedString("You can enable reminders later in Settings.", comment: "onboarding"))
                .appFont(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func primaryButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .padding(.horizontal, 20)
    }

    private var skipButton: some View {
        Button {
            finishOnboarding()
        } label: {
            Text(NSLocalizedString("Skip for now", comment: "onboarding"))
                .appFont(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 16)
    }

    private func advance(to step: Step) {
        withAnimation { currentStep = step }
    }

    private func requestNotificationPermission() {
        Task {
            let granted = await NotificationManager.shared.ensureAuthorization()
            await MainActor.run {
                notificationGranted = granted
                Haptics.success()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                    withAnimation { currentStep = .completion }
                }
            }
        }
    }

    private func finishOnboarding() {
        let trimmedName = medName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedName.isEmpty {
            let comps = Calendar.current.dateComponents([.hour, .minute], from: medTime)
            let med = Medication(
                name: trimmedName,
                dose: medDose.trimmingCharacters(in: .whitespacesAndNewlines),
                timesOfDay: [comps],
                remindersEnabled: true
            )
            store.addMedication(med)
            store.syncNotifications()
        }
        Haptics.success()
        onComplete()
    }
}

#Preview {
    OnboardingView(onComplete: {})
        .environmentObject(DataStore())
}
