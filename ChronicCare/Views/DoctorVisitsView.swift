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
                            .tint(.green)
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
                            .tint(.green)
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
        TintedCard(tint: visitTint(visit)) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "stethoscope")
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundStyle(visitTint(visit))
                        .frame(width: 44, height: 44)
                        .background(Circle().fill(visitTint(visit).opacity(0.12)))
                    VStack(alignment: .leading, spacing: 4) {
                        Text(prepTitle(for: visit))
                            .appFont(.headline)
                        Text(visit.displayTitle)
                            .appFont(.subheadline)
                            .foregroundStyle(.secondary)
                        if let reason = visit.reason, !reason.isEmpty {
                            Text(reason)
                                .appFont(.caption)
                                .foregroundStyle(.secondary)
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
                    .foregroundStyle(.secondary)
            }
            Text(visitSubtitle(visit))
                .appFont(.caption)
                .foregroundStyle(.secondary)
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
        guard let days = visit.daysUntil() else { return .secondary }
        if days < 0 { return .orange }
        return days <= 3 ? .teal : .blue
    }
}
