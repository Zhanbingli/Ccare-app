import SwiftUI

struct ProfileDrawerV2: View {
    @EnvironmentObject var store: DataStore
    @Environment(\.dismiss) private var dismiss
    @State private var medicationDeepLink: UUID? = .none
    @State private var shareURL: URL?
    @State private var showShare = false
    @State private var shareErrorMessage: String?
    @State private var showShareError = false
    var onLogMeasurement: () -> Void = {}

    var body: some View {
        NavigationStack {
            List {
                Section {
                    quickActionRow(
                        icon: "plus",
                        tint: AppColor.primary,
                        title: NSLocalizedString("Log Measurement", comment: ""),
                        subtitle: NSLocalizedString("Blood pressure, glucose, weight, heart rate", comment: ""),
                        action: onLogMeasurement
                    )

                    quickActionRow(
                        icon: "square.and.arrow.up",
                        tint: AppColor.primary,
                        title: NSLocalizedString("Share Health Report", comment: ""),
                        subtitle: NSLocalizedString("PDF for your doctor — last 30 days", comment: ""),
                        action: exportHealthReport
                    )
                }

                Section {
                    navRow(
                        icon: "pills.fill",
                        tint: AppColor.primary,
                        title: NSLocalizedString("My Medications", comment: ""),
                        subtitle: medicationSubtitle
                    ) {
                        MedicationsView(deepLinkMedicationID: $medicationDeepLink)
                    }
                }

                Section(NSLocalizedString("Review", comment: "")) {
                    navRow(
                        icon: "chart.line.uptrend.xyaxis",
                        tint: AppColor.primary,
                        title: NSLocalizedString("Trends", comment: ""),
                        subtitle: trendsSubtitle
                    ) {
                        EnhancedTrendsView()
                            .environmentObject(store)
                    }
                }

                Section(NSLocalizedString("For Your Doctor", comment: "Drawer section")) {
                    navRow(
                        icon: "calendar.badge.clock",
                        tint: AppColor.primary,
                        title: NSLocalizedString("Visit Prep", comment: ""),
                        subtitle: visitPrepSubtitle
                    ) {
                        DoctorVisitsView()
                    }

                    navRow(
                        icon: "cross.case.fill",
                        tint: AppColor.warning,
                        title: NSLocalizedString("Emergency Card", comment: ""),
                        subtitle: emergencySubtitle
                    ) {
                        EmergencyCardView()
                    }

                    navRow(
                        icon: "person.2.fill",
                        tint: AppColor.textSecondary,
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
            .scrollContentBackground(.hidden)
            .background(AppColor.background)
            .navigationTitle(NSLocalizedString("Profile", comment: ""))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(NSLocalizedString("Done", comment: "")) { dismiss() }
                }
            }
            .sheet(isPresented: $showShare) {
                if let url = shareURL {
                    ShareSheet(activityItems: [url])
                }
            }
            .alert(NSLocalizedString("Could not create report", comment: ""), isPresented: $showShareError) {
                Button(NSLocalizedString("OK", comment: ""), role: .cancel) {}
            } message: {
                if let message = shareErrorMessage {
                    Text(message)
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

    private var visitPrepSubtitle: String {
        guard let visit = store.nextDoctorVisit else {
            return NSLocalizedString("Plan your next appointment", comment: "")
        }
        if let days = visit.daysUntil() {
            if days == 0 {
                return String(format: NSLocalizedString("Today · %@", comment: ""), visit.displayTitle)
            }
            if days > 0 {
                return String(format: NSLocalizedString("In %lld days · %@", comment: ""), days, visit.displayTitle)
            }
            return String(format: NSLocalizedString("%lld days overdue · %@", comment: ""), abs(days), visit.displayTitle)
        }
        return visit.displayTitle
    }

    @MainActor
    private func exportHealthReport() {
        do {
            let url = try PDFGenerator.generateReport(store: store, days: 30)
            shareURL = url
            showShare = true
            Haptics.success()
        } catch {
            shareErrorMessage = error.localizedDescription
            showShareError = true
        }
    }

    @ViewBuilder
    private func quickActionRow(
        icon: String,
        tint: Color,
        title: String,
        subtitle: String,
        action: @escaping () -> Void
    ) -> some View {
        Button {
            Haptics.impact(.light)
            action()
        } label: {
            HStack(spacing: AppSpacing.medium) {
                rowIcon(icon, tint: tint)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .appFont(.body)
                        .foregroundStyle(AppColor.textPrimary)
                    Text(subtitle)
                        .appFont(.caption)
                        .foregroundStyle(AppColor.textSecondary)
                }
                Spacer()
            }
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(EditorialRowButtonStyle())
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
                rowIcon(icon, tint: tint)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).appFont(.body).foregroundStyle(AppColor.textPrimary)
                    Text(subtitle).appFont(.caption).foregroundStyle(AppColor.textSecondary)
                }
            }
            .padding(.vertical, 4)
        }
    }

    private func rowIcon(_ icon: String, tint: Color) -> some View {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(AppColor.surface)
            .frame(width: 34, height: 34)
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(AppColor.divider, lineWidth: 1)
            )
            .overlay(
                Image(systemName: icon)
                    .font(.system(size: 15, weight: .regular))
                    .foregroundStyle(tint)
            )
    }
}
