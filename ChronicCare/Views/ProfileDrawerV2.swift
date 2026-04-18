import SwiftUI

struct ProfileDrawerV2: View {
    @EnvironmentObject var store: DataStore
    @Environment(\.dismiss) private var dismiss
    @State private var medicationDeepLink: UUID? = .none
    var onLogMeasurement: () -> Void = {}

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button(action: onLogMeasurement) {
                        HStack(spacing: AppSpacing.medium) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(Color.accentColor.opacity(0.15))
                                    .frame(width: 34, height: 34)
                                Image(systemName: "plus")
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundStyle(Color.accentColor)
                            }
                            VStack(alignment: .leading, spacing: 2) {
                                Text(NSLocalizedString("Log Measurement", comment: ""))
                                    .appFont(.body)
                                    .foregroundStyle(.primary)
                                Text(NSLocalizedString("Blood pressure, glucose, weight, heart rate", comment: ""))
                                    .appFont(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                        }
                        .padding(.vertical, 4)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }

                Section {
                    navRow(
                        icon: "pills.fill",
                        tint: .indigo,
                        title: NSLocalizedString("My Medications", comment: ""),
                        subtitle: medicationSubtitle
                    ) {
                        MedicationsView(deepLinkMedicationID: $medicationDeepLink)
                    }
                }

                Section(NSLocalizedString("Review", comment: "")) {
                    navRow(
                        icon: "chart.line.uptrend.xyaxis",
                        tint: .blue,
                        title: NSLocalizedString("Trends", comment: ""),
                        subtitle: trendsSubtitle
                    ) {
                        EnhancedTrendsView()
                            .environmentObject(store)
                    }
                }

                Section(NSLocalizedString("Safety", comment: "")) {
                    navRow(
                        icon: "cross.case.fill",
                        tint: .red,
                        title: NSLocalizedString("Emergency Info", comment: ""),
                        subtitle: emergencySubtitle
                    ) {
                        EmergencyCardView()
                    }

                    navRow(
                        icon: "person.2.fill",
                        tint: .orange,
                        title: NSLocalizedString("Caregivers", comment: ""),
                        subtitle: caregiverSubtitle
                    ) {
                        CaregiversView()
                    }
                }

                Section {
                    navRow(
                        icon: "gearshape.fill",
                        tint: .gray,
                        title: NSLocalizedString("Settings", comment: ""),
                        subtitle: NSLocalizedString("Reminders, units, data, AI", comment: "")
                    ) {
                        ProfileView()
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle(NSLocalizedString("Profile", comment: ""))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(NSLocalizedString("Done", comment: "")) { dismiss() }
                }
            }
        }
    }

    private var medicationSubtitle: String {
        let count = store.medications.count
        if count == 0 { return NSLocalizedString("No medications yet", comment: "") }
        return String(format: NSLocalizedString("%d medications", comment: ""), count)
    }

    private var emergencySubtitle: String {
        if let info = store.emergencyInfo, !info.emergencyContacts.isEmpty {
            return String(format: NSLocalizedString("%d contacts", comment: ""), info.emergencyContacts.count)
        }
        return NSLocalizedString("Not set up", comment: "")
    }

    private var caregiverSubtitle: String {
        let count = store.caregivers.count
        if count == 0 { return NSLocalizedString("No caregivers added", comment: "") }
        return String(format: NSLocalizedString("%d caregivers", comment: ""), count)
    }

    private var trendsSubtitle: String {
        if store.measurements.isEmpty {
            return NSLocalizedString("No measurements yet", comment: "")
        }
        return String(format: NSLocalizedString("%d measurements", comment: ""), store.measurements.count)
    }

    @ViewBuilder
    private func navRow<Destination: View>(
        icon: String,
        tint: Color,
        title: String,
        subtitle: String,
        @ViewBuilder destination: @escaping () -> Destination
    ) -> some View {
        NavigationLink {
            destination()
        } label: {
            HStack(spacing: AppSpacing.medium) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(tint.opacity(0.15))
                        .frame(width: 34, height: 34)
                    Image(systemName: icon)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(tint)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).appFont(.body).foregroundStyle(.primary)
                    Text(subtitle).appFont(.caption).foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 4)
        }
    }
}
