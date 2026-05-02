import SwiftUI

/// Three-section list of doctor visits: upcoming, overdue, completed.
/// Entry point from ProfileDrawer's "For Your Doctor" section.
struct DoctorVisitsView: View {
    @EnvironmentObject var store: DataStore
    @State private var showNewVisit = false

    private var highlightedVisitID: UUID? {
        store.nextDoctorVisit?.id
    }

    private var secondaryUpcomingVisits: [DoctorVisit] {
        store.upcomingDoctorVisits.filter { $0.id != highlightedVisitID }
    }

    private var secondaryOverdueVisits: [DoctorVisit] {
        store.overdueDoctorVisits.filter { $0.id != highlightedVisitID }
    }

    private var incompletePostVisit: DoctorVisit? {
        store.completedDoctorVisits.first { $0.needsPostVisitCapture }
    }

    var body: some View {
        List {
            Section {
                if let visit = store.nextDoctorVisit {
                    nextVisitHeader(visit)

                    NavigationLink {
                        ConsultationSnapshotView(visit: visit)
                    } label: {
                        visitActionRow(
                            title: NSLocalizedString("Review Snapshot", comment: ""),
                            subtitle: NSLocalizedString("Doctor-facing summary for the appointment", comment: ""),
                            systemImage: "doc.text.magnifyingglass",
                            tint: AppColor.primary
                        )
                    }

                    NavigationLink {
                        DoctorVisitFormView(editing: visit, showsCancelButton: false)
                    } label: {
                        visitActionRow(
                            title: NSLocalizedString("Edit Visit", comment: "Edit doctor visit details"),
                            subtitle: NSLocalizedString("Time, doctor, department, and reason", comment: ""),
                            systemImage: "square.and.pencil",
                            tint: AppColor.textSecondary
                        )
                    }
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
            .listRowInsets(EdgeInsets(top: 10, leading: 16, bottom: 10, trailing: 16))
            .listRowBackground(AppColor.surface)

            if let visit = incompletePostVisit {
                Section {
                    NavigationLink {
                        DoctorVisitFormView(editing: visit, showsCancelButton: false)
                    } label: {
                        visitActionRow(
                            title: NSLocalizedString("Complete Visit Plan", comment: "Post visit action title"),
                            subtitle: postVisitMissingSummary(visit),
                            systemImage: "checklist",
                            tint: AppColor.warning
                        )
                    }

                    NavigationLink {
                        MedicationsView()
                    } label: {
                        visitActionRow(
                            title: NSLocalizedString("Review Medication List", comment: "Post visit medication review action"),
                            subtitle: NSLocalizedString("Apply medication changes to reminders and the next visit summary", comment: "Post visit medication review subtitle"),
                            systemImage: "pills.fill",
                            tint: AppColor.primary
                        )
                    }
                } header: {
                    Text(NSLocalizedString("After Last Visit", comment: "Post visit section title"))
                } footer: {
                    Text(NSLocalizedString("Capture the doctor's instructions while they are fresh so daily reminders and the next visit summary stay accurate.", comment: "Post visit section footer"))
                }
            }

            if !secondaryUpcomingVisits.isEmpty {
                Section(NSLocalizedString("Upcoming", comment: "")) {
                    ForEach(secondaryUpcomingVisits) { visit in
                        NavigationLink {
                            DoctorVisitFormView(editing: visit, showsCancelButton: false)
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

            if !secondaryOverdueVisits.isEmpty {
                Section(NSLocalizedString("Overdue", comment: "")) {
                    ForEach(secondaryOverdueVisits) { visit in
                        NavigationLink {
                            DoctorVisitFormView(editing: visit, showsCancelButton: false)
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
                            DoctorVisitFormView(editing: visit, showsCancelButton: false)
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

    private func nextVisitHeader(_ visit: DoctorVisit) -> some View {
        VStack(alignment: .leading, spacing: EditorialSpacing.sm) {
            Text(NSLocalizedString("Next visit", comment: ""))
                .appFont(.micro)
                .foregroundStyle(AppColor.textTertiary)
                .textCase(.uppercase)

            Text(prepTitle(for: visit))
                .appFontNumeric(.heroNumber)
                .foregroundStyle(visitTint(visit))
                .lineLimit(1)
                .minimumScaleFactor(0.82)

            VStack(alignment: .leading, spacing: EditorialSpacing.xs) {
                Text(visit.displayTitle)
                    .appFont(.body)
                    .fontWeight(.semibold)
                    .foregroundStyle(AppColor.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)

                if let reason = visit.reason, !reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text(reason)
                        .appFont(.caption)
                        .foregroundStyle(AppColor.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(.vertical, EditorialSpacing.sm)
        .accessibilityElement(children: .combine)
    }

    private func visitActionRow(title: String, subtitle: String, systemImage: String, tint: Color) -> some View {
        HStack(spacing: EditorialSpacing.md) {
            Image(systemName: systemImage)
                .font(.system(size: 16, weight: .regular))
                .foregroundStyle(tint)
                .frame(width: 22)

            VStack(alignment: .leading, spacing: EditorialSpacing.xs) {
                Text(title)
                    .appFont(.body)
                    .foregroundStyle(AppColor.textPrimary)
                Text(subtitle)
                    .appFont(.caption)
                    .foregroundStyle(AppColor.textSecondary)
            }
        }
        .padding(.vertical, EditorialSpacing.xs)
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
            if visit.needsPostVisitCapture {
                return postVisitMissingSummary(visit)
            }
            return String(format: NSLocalizedString("Completed %@", comment: ""), completed.formatted(date: .abbreviated, time: .omitted))
        }
        if let reason = visit.reason, !reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return reason
        }
        return NSLocalizedString("Tap to add doctor, department, and reason.", comment: "")
    }

    private func postVisitMissingSummary(_ visit: DoctorVisit) -> String {
        let missing = visit.postVisitMissingItems
        guard !missing.isEmpty else {
            return NSLocalizedString("Post-visit plan saved.", comment: "Post visit complete detail")
        }
        return String(
            format: NSLocalizedString("Still needs: %@", comment: "Post visit missing detail"),
            missing.joined(separator: ", ")
        )
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
