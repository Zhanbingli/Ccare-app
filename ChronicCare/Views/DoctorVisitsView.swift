import SwiftUI

/// Three-section list of doctor visits: upcoming, overdue, completed.
/// Entry point from ProfileDrawer's "For Your Doctor" section.
struct DoctorVisitsView: View {
    @EnvironmentObject var store: DataStore
    @State private var showNewVisit = false

    var body: some View {
        List {
            Section {
                if let visit = store.nextDoctorVisit {
                    nextVisitHero(visit)
                } else {
                    EmptyStateView(
                        systemImage: "calendar.badge.plus",
                        title: NSLocalizedString("No visit scheduled", comment: ""),
                        subtitle: NSLocalizedString("Add your next appointment so the app can prepare a focused doctor snapshot.", comment: ""),
                        actionTitle: NSLocalizedString("Add Visit", comment: ""),
                        action: { showNewVisit = true }
                    )
                }
            }
            .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
            .listRowBackground(Color.clear)

            if !store.upcomingDoctorVisits.isEmpty {
                Section(NSLocalizedString("Upcoming", comment: "")) {
                    ForEach(store.upcomingDoctorVisits) { visit in
                        NavigationLink {
                            DoctorVisitFormView(editing: visit)
                        } label: {
                            visitRow(visit)
                        }
                        .swipeActions {
                            Button(NSLocalizedString("Done", comment: "")) {
                                store.completeDoctorVisit(visit)
                            }
                            .tint(AppColor.success)
                            Button(role: .destructive) {
                                store.removeDoctorVisit(visit)
                            } label: {
                                Label(NSLocalizedString("Delete", comment: ""), systemImage: "trash")
                            }
                        }
                    }
                }
            }

            if !store.overdueDoctorVisits.isEmpty {
                Section(NSLocalizedString("Overdue", comment: "")) {
                    ForEach(store.overdueDoctorVisits) { visit in
                        NavigationLink {
                            DoctorVisitFormView(editing: visit)
                        } label: {
                            visitRow(visit)
                        }
                        .swipeActions {
                            Button(NSLocalizedString("Done", comment: "")) {
                                store.completeDoctorVisit(visit)
                            }
                            .tint(AppColor.success)
                            Button(role: .destructive) {
                                store.removeDoctorVisit(visit)
                            } label: {
                                Label(NSLocalizedString("Delete", comment: ""), systemImage: "trash")
                            }
                        }
                    }
                }
            }

            if !store.completedDoctorVisits.isEmpty {
                Section(NSLocalizedString("Completed", comment: "")) {
                    ForEach(Array(store.completedDoctorVisits.prefix(8))) { visit in
                        NavigationLink {
                            DoctorVisitFormView(editing: visit)
                        } label: {
                            visitRow(visit)
                        }
                        .swipeActions {
                            Button(role: .destructive) {
                                store.removeDoctorVisit(visit)
                            } label: {
                                Label(NSLocalizedString("Delete", comment: ""), systemImage: "trash")
                            }
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(AppColor.background)
        .navigationTitle(NSLocalizedString("Visit Prep", comment: ""))
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showNewVisit = true
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel(NSLocalizedString("Add Visit", comment: ""))
            }
        }
        .sheet(isPresented: $showNewVisit) {
            NavigationStack {
                DoctorVisitFormView()
                    .environmentObject(store)
            }
        }
    }

    private func nextVisitHero(_ visit: DoctorVisit) -> some View {
        Card {
            VStack(alignment: .leading, spacing: EditorialSpacing.md) {
                HStack(alignment: .top, spacing: EditorialSpacing.md) {
                    Image(systemName: "stethoscope")
                        .font(.system(size: 22, weight: .regular))
                        .foregroundStyle(visitTint(visit))
                        .frame(width: 32, height: 32)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(prepTitle(for: visit))
                            .appFont(AppTypography.sectionTitle)
                            .foregroundStyle(AppColor.textPrimary)
                        Text(visit.displayTitle)
                            .appFont(AppTypography.body)
                            .foregroundStyle(AppColor.textSecondary)
                        if let reason = visit.reason, !reason.isEmpty {
                            Text(reason)
                                .appFont(AppTypography.caption)
                                .foregroundStyle(AppColor.textSecondary)
                        }
                    }
                }
                NavigationLink {
                    ConsultationSnapshotView(visit: visit)
                } label: {
                    Label(NSLocalizedString("Review Snapshot", comment: ""), systemImage: "doc.text.magnifyingglass")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(AppColor.primary)
            }
        }
    }

    private func visitRow(_ visit: DoctorVisit) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(visit.displayTitle)
                    .appFont(.body)
                Spacer()
                Text(visit.scheduledDate, format: .dateTime.month().day())
                    .appFontNumeric(.caption)
                    .foregroundStyle(AppColor.textSecondary)
            }
            Text(visitSubtitle(visit))
                .appFont(.caption)
                .foregroundStyle(AppColor.textSecondary)
        }
        .padding(.vertical, 2)
    }

    private func visitSubtitle(_ visit: DoctorVisit) -> String {
        if let completed = visit.completedDate {
            return String(format: NSLocalizedString("Completed %@", comment: ""), completed.formatted(date: .abbreviated, time: .omitted))
        }
        if let reason = visit.reason, !reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return reason
        }
        return NSLocalizedString("Tap to add doctor, department, and reason.", comment: "")
    }

    private func prepTitle(for visit: DoctorVisit) -> String {
        guard let days = visit.daysUntil() else {
            return NSLocalizedString("Visit completed", comment: "")
        }
        if days == 0 { return NSLocalizedString("Appointment today", comment: "") }
        if days > 0 {
            return String(format: NSLocalizedString("%lld days until appointment", comment: ""), days)
        }
        return String(format: NSLocalizedString("%lld days overdue", comment: ""), abs(days))
    }

    private func visitTint(_ visit: DoctorVisit) -> Color {
        guard let days = visit.daysUntil() else { return AppColor.textSecondary }
        if days < 0 { return AppColor.warning }
        return days <= 7 ? AppColor.primary : AppColor.textSecondary
    }
}
