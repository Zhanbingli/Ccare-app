import SwiftUI

/// Form for scheduling a new doctor visit or editing an existing one.
/// The "After Visit" section is what turns this into an iterative care
/// log: notes + medication changes + next visit date close the loop
/// from one consultation to the next.
struct DoctorVisitFormView: View {
    @EnvironmentObject var store: DataStore
    @Environment(\.dismiss) private var dismiss

    var editing: DoctorVisit?
    var showsCancelButton: Bool

    @State private var scheduledDate: Date
    @State private var hospital: String
    @State private var department: String
    @State private var doctorName: String
    @State private var reason: String
    @State private var isCompleted: Bool
    @State private var notes: String
    @State private var medicationChangesSummary: String
    @State private var nextVisitDate: Date
    @State private var hasNextVisitDate: Bool
    @State private var showDeleteConfirm = false

    init(editing: DoctorVisit? = nil, showsCancelButton: Bool = true) {
        self.editing = editing
        self.showsCancelButton = showsCancelButton
        let defaultScheduled = Calendar.current.date(byAdding: .day, value: 7, to: Date()) ?? Date()
        _scheduledDate = State(initialValue: editing?.scheduledDate ?? defaultScheduled)
        _hospital = State(initialValue: editing?.hospital ?? "")
        _department = State(initialValue: editing?.department ?? "")
        _doctorName = State(initialValue: editing?.doctorName ?? "")
        _reason = State(initialValue: editing?.reason ?? "")
        _isCompleted = State(initialValue: editing?.isCompleted ?? false)
        _notes = State(initialValue: editing?.notes ?? "")
        _medicationChangesSummary = State(initialValue: editing?.medicationChangesSummary ?? "")
        _nextVisitDate = State(initialValue: editing?.nextVisitDate ?? Calendar.current.date(byAdding: .month, value: 1, to: Date()) ?? Date())
        _hasNextVisitDate = State(initialValue: editing?.nextVisitDate != nil)
    }

    var body: some View {
        Form {
            Section(NSLocalizedString("Appointment", comment: "")) {
                DatePicker(NSLocalizedString("Date", comment: ""), selection: $scheduledDate, displayedComponents: [.date])
                TextField(NSLocalizedString("Hospital", comment: ""), text: $hospital)
                TextField(NSLocalizedString("Department", comment: ""), text: $department)
                TextField(NSLocalizedString("Doctor", comment: ""), text: $doctorName)
                TextField(NSLocalizedString("Reason", comment: ""), text: $reason, axis: .vertical)
                    .lineLimit(2...4)
            }

            Section {
                Toggle(NSLocalizedString("Visit completed", comment: ""), isOn: $isCompleted)

                if showsAfterVisitFields {
                    postVisitCaptureGuide

                    VStack(alignment: .leading, spacing: 6) {
                        Text(NSLocalizedString("Doctor instructions", comment: "Post visit notes field label"))
                            .appFont(.caption)
                            .foregroundStyle(AppColor.textSecondary)
                        TextField(NSLocalizedString("What should you do or watch before the next visit?", comment: "Post visit notes placeholder"), text: $notes, axis: .vertical)
                            .lineLimit(3...7)
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text(NSLocalizedString("Medication plan", comment: "Post visit medication field label"))
                            .appFont(.caption)
                            .foregroundStyle(AppColor.textSecondary)
                        TextField(NSLocalizedString("Added, stopped, changed dose/time, or no changes", comment: "Post visit medication placeholder"), text: $medicationChangesSummary, axis: .vertical)
                            .lineLimit(3...7)
                    }

                    Toggle(NSLocalizedString("Set next visit date", comment: ""), isOn: $hasNextVisitDate)
                    if hasNextVisitDate {
                        DatePicker(NSLocalizedString("Next visit", comment: ""), selection: $nextVisitDate, displayedComponents: [.date])
                    }
                } else {
                    Text(NSLocalizedString("After the appointment, turn this on to record the doctor's notes and next follow-up.", comment: "Doctor visit after-visit collapsed helper"))
                        .appFont(.body)
                        .foregroundStyle(AppColor.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } header: {
                Text(NSLocalizedString("After Visit", comment: ""))
            } footer: {
                if createsFollowUpVisit {
                    Text(NSLocalizedString("Saving will also add the next follow-up visit to your schedule.", comment: "Doctor visit follow-up creation helper"))
                } else if isCompleted && hasNextVisitDate {
                    Text(NSLocalizedString("A visit already exists on that date, so this record will only save the follow-up date.", comment: "Doctor visit duplicate follow-up helper"))
                }
            }

            if editing != nil {
                Section {
                    Button(role: .destructive) {
                        showDeleteConfirm = true
                    } label: {
                        Label(NSLocalizedString("Delete Visit", comment: ""), systemImage: "trash")
                            .frame(maxWidth: .infinity, alignment: .center)
                    }
                }
            }
        }
        .navigationTitle(editing == nil ? NSLocalizedString("Add Visit", comment: "") : NSLocalizedString("Edit Visit", comment: ""))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if showsCancelButton {
                ToolbarItem(placement: .cancellationAction) {
                    Button(NSLocalizedString("Cancel", comment: "")) { dismiss() }
                }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button(NSLocalizedString("Save", comment: "")) {
                    save()
                }
            }
        }
        .confirmationDialog(
            NSLocalizedString("Delete this visit?", comment: ""),
            isPresented: $showDeleteConfirm,
            titleVisibility: .visible
        ) {
            Button(NSLocalizedString("Delete", comment: ""), role: .destructive) {
                if let editing { store.removeDoctorVisit(editing) }
                dismiss()
            }
            Button(NSLocalizedString("Cancel", comment: ""), role: .cancel) { }
        }
    }

    private func save() {
        var visit = editing ?? DoctorVisit(scheduledDate: scheduledDate)
        visit.scheduledDate = scheduledDate
        visit.completedDate = isCompleted ? (editing?.completedDate ?? Date()) : nil
        visit.hospital = trimmedOrNil(hospital)
        visit.department = trimmedOrNil(department)
        visit.doctorName = trimmedOrNil(doctorName)
        visit.reason = trimmedOrNil(reason)
        visit.notes = trimmedOrNil(notes)
        visit.medicationChangesSummary = trimmedOrNil(medicationChangesSummary)
        visit.nextVisitDate = hasNextVisitDate ? nextVisitDate : nil

        if editing == nil {
            store.addDoctorVisit(visit)
        } else {
            store.updateDoctorVisit(visit)
        }
        createNextVisitIfNeeded(from: visit)
        dismiss()
    }

    private var postVisitCaptureGuide: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(NSLocalizedString("Before you leave the clinic", comment: "Post visit capture guide title"), systemImage: "checklist")
                .appFont(.subheadline)
                .fontWeight(.semibold)
                .foregroundStyle(AppColor.textPrimary)
        }
        .padding(.vertical, 4)
    }

    private func trimmedOrNil(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private var showsAfterVisitFields: Bool {
        isCompleted || hasText(notes) || hasText(medicationChangesSummary) || hasNextVisitDate
    }

    private var createsFollowUpVisit: Bool {
        isCompleted && hasNextVisitDate && !store.hasDoctorVisit(on: nextVisitDate)
    }

    private func hasText(_ value: String) -> Bool {
        !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func createNextVisitIfNeeded(from completedVisit: DoctorVisit) {
        guard isCompleted, hasNextVisitDate else { return }
        guard !store.hasDoctorVisit(on: nextVisitDate) else { return }
        let next = DoctorVisit(
            scheduledDate: nextVisitDate,
            hospital: completedVisit.hospital,
            department: completedVisit.department,
            doctorName: completedVisit.doctorName,
            reason: NSLocalizedString("Follow-up", comment: "")
        )
        store.addDoctorVisit(next)
    }
}
