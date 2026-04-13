import SwiftUI

// MARK: - HealthQuickLinksCard

/// Grid of navigation tiles at the bottom of HealthView (Medical Summary, Caregivers, Calendar, Trends).
struct HealthQuickLinksCard: View {
    @EnvironmentObject var store: DataStore

    private let quickLinkColumns = Array(repeating: GridItem(.flexible(), spacing: 12), count: 2)

    private var activeMedicationCount: Int {
        store.medications.filter { $0.remindersEnabled }.count
    }

    private var hasEmergencyCardContent: Bool {
        let info = store.emergencyInfo
        return !(info?.bloodType?.isEmpty ?? true)
            || !(info?.allergies?.isEmpty ?? true)
            || !(info?.medicalConditions?.isEmpty ?? true)
            || !((info?.emergencyContacts ?? []).isEmpty)
    }

    private var emergencyCardSubtitle: String {
        hasEmergencyCardContent
            ? NSLocalizedString("Review current meds, allergies, conditions, and recent readings for doctor visits.", comment: "")
            : NSLocalizedString("Add allergies, conditions, and contacts so doctor visit details are ready.", comment: "")
    }

    private var caregiversSubtitle: String {
        if store.caregivers.isEmpty {
            return NSLocalizedString("Add someone you trust so missed-dose support has a real contact path.", comment: "")
        }
        if store.caregivers.contains(where: \.notifyOnMiss) {
            return NSLocalizedString("Your support network is set up for missed-dose follow-up.", comment: "")
        }
        return NSLocalizedString("Caregivers are saved, but missed-dose support is still turned off for them.", comment: "")
    }

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 14) {
                Text(NSLocalizedString("Quick Links", comment: ""))
                    .appFont(.headline)

                LazyVGrid(columns: quickLinkColumns, spacing: 12) {
                    quickLinkTile(
                        title: NSLocalizedString("Medical Summary", comment: ""),
                        subtitle: emergencyCardSubtitle,
                        systemImage: "person.text.rectangle",
                        tint: .red
                    ) {
                        EmergencyCardView()
                            .environmentObject(store)
                    }

                    quickLinkTile(
                        title: NSLocalizedString("Caregivers", comment: ""),
                        subtitle: caregiversSubtitle,
                        systemImage: "person.2.fill",
                        tint: .blue
                    ) {
                        CaregiversView()
                            .environmentObject(store)
                    }

                    if activeMedicationCount > 0 {
                        quickLinkTile(
                            title: NSLocalizedString("Adherence Calendar", comment: ""),
                            subtitle: NSLocalizedString("Review your medication consistency across recent days.", comment: ""),
                            systemImage: "calendar",
                            tint: .green
                        ) {
                            AdherenceCalendarView()
                        }
                    }

                    quickLinkTile(
                        title: NSLocalizedString("View Trends", comment: ""),
                        subtitle: NSLocalizedString("See blood pressure, glucose, weight, and heart rate trends.", comment: ""),
                        systemImage: "chart.line.uptrend.xyaxis",
                        tint: .orange
                    ) {
                        EnhancedTrendsView()
                            .environmentObject(store)
                    }
                }
            }
        }
    }

    private func quickLinkTile<Destination: View>(
        title: String,
        subtitle: String,
        systemImage: String,
        tint: Color,
        @ViewBuilder destination: @escaping () -> Destination
    ) -> some View {
        NavigationLink(destination: destination) {
            InsetPanel(tint: tint) {
                VStack(alignment: .leading, spacing: 16) {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(tint.opacity(0.14))
                        .frame(width: 44, height: 44)
                        .overlay(
                            Image(systemName: systemImage)
                                .font(.system(size: 17, weight: .semibold))
                                .foregroundStyle(tint)
                        )

                    VStack(alignment: .leading, spacing: 4) {
                        Text(title)
                            .appFont(.subheadline)
                            .foregroundStyle(.primary)
                        Text(subtitle)
                            .appFont(.caption)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer(minLength: 0)

                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .buttonStyle(.plain)
    }
}
