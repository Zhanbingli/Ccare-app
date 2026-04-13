import SwiftUI

struct OnboardingView: View {
    @EnvironmentObject var store: DataStore
    var onComplete: () -> Void

    @State private var currentStep = 0
    @State private var medName = ""
    @State private var medDose = ""
    @State private var medTime = Calendar.current.date(bySettingHour: 8, minute: 0, second: 0, of: Date()) ?? Date()
    @State private var notificationGranted: Bool?

    private let totalSteps = 4

    var body: some View {
        Group {
            switch currentStep {
            case 0: welcomeStep
            case 1: addMedicationStep
            case 2: notificationStep
            default: completionStep
            }
        }
        .transition(.asymmetric(insertion: .move(edge: .trailing), removal: .move(edge: .leading)))
        .animation(.easeInOut(duration: 0.3), value: currentStep)
        .environment(\.font, AppFontStyle.body.font)
        .dynamicTypeSize(.medium ... .accessibility5)
    }

    // MARK: - Step 0: Welcome

    private var welcomeStep: some View {
        VStack(spacing: 0) {
            Spacer()
            VStack(spacing: 24) {
                Image(systemName: "heart.text.clipboard")
                    .font(.system(size: 80))
                    .foregroundStyle(Color.accentColor)
                    .symbolRenderingMode(.hierarchical)

                Text(NSLocalizedString("Welcome to ChronicCare", comment: "onboarding"))
                    .appFont(.title)
                    .fontWeight(.bold)
                    .multilineTextAlignment(.center)

                Text(NSLocalizedString("Your personal medication companion. We'll help you stay on track with your health.", comment: "onboarding"))
                    .appFont(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
            }
            Spacer()
            VStack(spacing: 16) {
                Button {
                    withAnimation { currentStep = 1 }
                } label: {
                    Text(NSLocalizedString("Get Started", comment: "onboarding"))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)

                skipButton
            }
            .padding(.horizontal, 32)
            .padding(.bottom, 48)
        }
    }

    // MARK: - Step 1: Add First Medication

    private var addMedicationStep: some View {
        VStack(spacing: 0) {
            VStack(spacing: 8) {
                stepIndicator(current: 1)
                Text(NSLocalizedString("Add Your First Medication", comment: "onboarding"))
                    .appFont(.headline)
            }
            .padding(.top, 32)

            Form {
                Section {
                    TextField(NSLocalizedString("Medication Name", comment: ""), text: $medName)
                        .appFont(.body)
                    TextField(NSLocalizedString("Dose (e.g. 500mg)", comment: ""), text: $medDose)
                        .appFont(.body)
                } header: {
                    Text(NSLocalizedString("What are you taking?", comment: ""))
                }

                Section {
                    DatePicker(
                        NSLocalizedString("Reminder Time", comment: "onboarding"),
                        selection: $medTime,
                        displayedComponents: .hourAndMinute
                    )
                    .appFont(.body)
                } header: {
                    Text(NSLocalizedString("When do you take it?", comment: ""))
                }
            }
            .scrollContentBackground(.hidden)

            VStack(spacing: 16) {
                Button {
                    withAnimation { currentStep = 2 }
                } label: {
                    Text(NSLocalizedString("Next", comment: "onboarding"))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(medName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                skipButton
            }
            .padding(.horizontal, 32)
            .padding(.bottom, 48)
        }
    }

    // MARK: - Step 2: Notification Permission

    private var notificationStep: some View {
        VStack(spacing: 0) {
            Spacer()
            VStack(spacing: 24) {
                stepIndicator(current: 2)

                Image(systemName: "bell.badge.fill")
                    .font(.system(size: 64))
                    .foregroundStyle(.orange)
                    .symbolRenderingMode(.hierarchical)

                Text(NSLocalizedString("Enable Reminders", comment: "onboarding"))
                    .appFont(.headline)

                Text(NSLocalizedString("We'll send you a gentle reminder when it's time to take your medication. You won't miss a dose.", comment: "onboarding"))
                    .appFont(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)

                if let granted = notificationGranted {
                    HStack(spacing: 8) {
                        Image(systemName: granted ? "checkmark.circle.fill" : "xmark.circle.fill")
                            .foregroundStyle(granted ? .green : .orange)
                        Text(granted
                             ? NSLocalizedString("Reminders enabled!", comment: "onboarding")
                             : NSLocalizedString("You can enable reminders later in Settings.", comment: "onboarding"))
                            .appFont(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            Spacer()
            VStack(spacing: 16) {
                if notificationGranted == nil {
                    Button {
                        Task {
                            let granted = await NotificationManager.shared.ensureAuthorization()
                            await MainActor.run {
                                notificationGranted = granted
                                Haptics.success()
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                                    withAnimation { currentStep = 3 }
                                }
                            }
                        }
                    } label: {
                        Label(NSLocalizedString("Enable Reminders", comment: "onboarding"), systemImage: "bell")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                } else {
                    Button {
                        withAnimation { currentStep = 3 }
                    } label: {
                        Text(NSLocalizedString("Next", comment: "onboarding"))
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                }

                skipButton
            }
            .padding(.horizontal, 32)
            .padding(.bottom, 48)
        }
    }

    // MARK: - Step 3: Completion

    private var completionStep: some View {
        VStack(spacing: 0) {
            Spacer()
            VStack(spacing: 24) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 80))
                    .foregroundStyle(.green)
                    .symbolRenderingMode(.hierarchical)

                Text(NSLocalizedString("You're All Set!", comment: "onboarding"))
                    .appFont(.title)
                    .fontWeight(.bold)

                Text(medName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                     ? NSLocalizedString("You can add medications anytime from the Medications tab.", comment: "onboarding")
                     : String(format: NSLocalizedString("We'll remind you to take %@ on time.", comment: "onboarding"), medName))
                    .appFont(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
            }
            Spacer()
            Button {
                finishOnboarding()
            } label: {
                Text(NSLocalizedString("Go to Dashboard", comment: "onboarding"))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .padding(.horizontal, 32)
            .padding(.bottom, 48)
        }
    }

    // MARK: - Helpers

    private var skipButton: some View {
        Button {
            finishOnboarding()
        } label: {
            Text(NSLocalizedString("Skip for now", comment: "onboarding"))
                .appFont(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private func stepIndicator(current: Int) -> some View {
        HStack(spacing: 8) {
            ForEach(1..<totalSteps, id: \.self) { step in
                Capsule()
                    .fill(step <= current ? Color.accentColor : Color.primary.opacity(0.15))
                    .frame(width: step == current ? 24 : 8, height: 8)
                    .animation(.easeInOut(duration: 0.2), value: current)
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
