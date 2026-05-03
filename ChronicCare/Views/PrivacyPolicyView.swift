import SwiftUI

struct PrivacyPolicyView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    policySection(
                        title: NSLocalizedString("Overview", comment: ""),
                        body: NSLocalizedString("Ccare is designed with your privacy as a priority. Medication routines, health measurements, intake logs, contacts, and settings are stored locally on your device. We do not operate analytics, advertising, or tracking services.", comment: "")
                    )

                    policySection(
                        title: NSLocalizedString("Data Stored on Device", comment: ""),
                        body: NSLocalizedString("The following data is stored only on your device:\n• Medications and dosing schedules\n• Health measurements (blood pressure, blood glucose, weight, heart rate)\n• Intake logs and adherence history\n• Emergency contacts and medical information\n• Caregiver contact information\n• App preferences and settings", comment: "")
                    )

                    policySection(
                        title: NSLocalizedString("Apple Health Integration", comment: ""),
                        body: NSLocalizedString("If you grant permission, Ccare can read and write health measurements to Apple Health. This data exchange happens entirely on your device through Apple's HealthKit framework. We never access your Apple Health data remotely.", comment: "")
                    )

                    policySection(
                        title: NSLocalizedString("Camera Access", comment: ""),
                        body: NSLocalizedString("The camera is used solely to scan medication labels for assisted data entry. Photos taken for scanning are processed on-device and are not stored or transmitted unless you choose to save a medication photo.", comment: "")
                    )

                    policySection(
                        title: NSLocalizedString("Notifications", comment: ""),
                        body: NSLocalizedString("With your permission, Ccare sends local notifications to remind you of medication doses. These notifications are scheduled on-device and do not involve any external server.", comment: "")
                    )

                    policySection(
                        title: NSLocalizedString("AI Features", comment: ""),
                        body: NSLocalizedString("If you choose to use AI-powered features, the limited summary shown before that request is sent to the configured AI service for processing. No AI request is sent until you approve it. The AI API key is stored securely in your device's Keychain.", comment: "")
                    )

                    policySection(
                        title: NSLocalizedString("No Analytics or Tracking", comment: ""),
                        body: NSLocalizedString("Ccare does not use any analytics, crash reporting, or advertising frameworks. We do not track your usage or behavior in any way.", comment: "")
                    )

                    policySection(
                        title: NSLocalizedString("Data Deletion", comment: ""),
                        body: NSLocalizedString("You can delete all your data at any time from Settings > Clear All Data. Uninstalling the app also removes all stored data from your device.", comment: "")
                    )

                    policySection(
                        title: NSLocalizedString("Changes to This Policy", comment: ""),
                        body: NSLocalizedString("If we update this privacy policy, the changes will be reflected in the app and on our website. Since we do not collect your contact information, please check periodically.", comment: "")
                    )

                    policySection(
                        title: NSLocalizedString("Contact", comment: ""),
                        body: NSLocalizedString("If you have questions about this privacy policy, please contact us through the App Store listing.", comment: "")
                    )

                    Text(NSLocalizedString("Last updated: April 2026", comment: ""))
                        .appFont(.caption)
                        .foregroundStyle(.tertiary)
                        .padding(.top, 8)
                }
                .padding(20)
            }
            .background(AppBackground())
            .navigationTitle(NSLocalizedString("Privacy Policy", comment: ""))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(NSLocalizedString("Done", comment: "")) { dismiss() }
                }
            }
        }
    }

    private func policySection(title: String, body: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .appFont(.headline)
            Text(body)
                .appFont(.subheadline)
                .foregroundStyle(.secondary)
        }
    }
}
