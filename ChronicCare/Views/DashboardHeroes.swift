import SwiftUI

// MARK: - Dashboard mode heroes
//
// The top-of-Home hero for each HomeMode, extracted from DashboardView. Each is
// a standalone view fed only the data and callbacks it needs; routing and store
// mutations stay with the dashboard via closures.

/// Light/active visit-prep hero: countdown + a tap into the visit report.
struct VisitPrepHero: View {
    let daysUntil: Int
    let supportingLine: String
    var onOpenReport: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: EditorialSpacing.lg) {
            AppDivider()

            VStack(alignment: .leading, spacing: EditorialSpacing.xs) {
                Text(NSLocalizedString("Preparing for your visit", comment: "Visit prep editorial title"))
                    .appFont(.micro)
                    .textCase(.uppercase)
                    .tracking(0.7)
                    .foregroundStyle(AppColor.textSecondary)

                Text(String(format: NSLocalizedString("%lld days", comment: "Visit countdown hero number"), daysUntil))
                    .appFontNumeric(.heroNumber)
                    .foregroundStyle(AppColor.primary)

                Text(supportingLine)
                    .appFont(.caption)
                    .foregroundStyle(AppColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Button {
                onOpenReport()
            } label: {
                HStack {
                    Text(NSLocalizedString("Open visit report", comment: "Visit prep summary action"))
                        .appFont(.subheadline)
                        .fontWeight(.medium)
                        .foregroundStyle(AppColor.textPrimary)
                    Spacer()
                    Image(systemName: "arrow.right")
                        .font(.system(size: 14, weight: .regular))
                        .foregroundStyle(AppColor.primary)
                }
                .padding(EditorialSpacing.md)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(AppColor.surface)
                        .shadow(color: .black.opacity(0.04), radius: 10, x: 0, y: 4)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(AppColor.divider.opacity(0.65), lineWidth: 0.8)
                )
            }
            .buttonStyle(.plain)
        }
    }
}

/// Shown for ~48h after an appointment until the doctor's plan is recorded.
struct PostVisitCaptureCard: View {
    let visit: DoctorVisit
    var onContinueCapture: () -> Void
    var onUpdateMedications: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: EditorialSpacing.lg) {
            VStack(alignment: .leading, spacing: EditorialSpacing.sm) {
                Text(NSLocalizedString("Record today's visit", comment: "Post visit capture title"))
                    .appFont(.displayTitle)
                    .fontWeight(.bold)
                    .foregroundStyle(EditorialPalette.textPrimary)
            }

            AppDivider()

            summary

            VStack(alignment: .leading, spacing: EditorialSpacing.sm) {
                Button {
                    onContinueCapture()
                } label: {
                    Label(NSLocalizedString("Continue visit record", comment: "Post visit capture action"), systemImage: "square.and.pencil")
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity, minHeight: 52)
                }
                .buttonStyle(.borderedProminent)
                .tint(EditorialPalette.primary)

                if visit.hasMedicationPlan {
                    Button {
                        onUpdateMedications()
                    } label: {
                        Label(NSLocalizedString("Update Medication List", comment: "Post visit medication action"), systemImage: "pills.fill")
                            .fontWeight(.semibold)
                            .frame(maxWidth: .infinity, minHeight: 48)
                    }
                    .buttonStyle(.bordered)
                    .tint(EditorialPalette.primary)
                }
            }
        }
        .padding(.vertical, EditorialSpacing.sm)
    }

    private var summary: some View {
        let missingItems = visit.postVisitMissingItems
        let text = missingItems.isEmpty
            ? NSLocalizedString("Post-visit plan saved.", comment: "Post visit capture complete state")
            : String(format: NSLocalizedString("Still needs: %@", comment: "Post visit capture missing summary"), missingItems.joined(separator: ", "))

        return Label {
            Text(text)
                .appFont(.body)
                .foregroundStyle(AppColor.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: missingItems.isEmpty ? "checkmark.circle.fill" : "checklist")
                .foregroundStyle(missingItems.isEmpty ? AppColor.success : AppColor.warning)
        }
        .padding(.vertical, EditorialSpacing.xs)
    }
}

/// Appointment-day hero: time + place, the report shortcut, a pre-visit
/// checklist (persisted per visit), and the post-visit capture handoff. Owns
/// its own checklist refresh state; routing is delegated via closures.
struct VisitDayBoardingPass: View {
    let visit: DoctorVisit
    var onOpenReport: () -> Void
    var onEditVisit: () -> Void
    var onMarkDoneAndCapture: () -> Void

    @State private var checklistRevision = 0

    private struct ChecklistItem {
        let id: String
        let title: String
        let detail: String
        let systemImage: String
    }

    var body: some View {
        VStack(alignment: .leading, spacing: EditorialSpacing.lg) {
            VStack(alignment: .leading, spacing: EditorialSpacing.sm) {
                Text(NSLocalizedString("Today is your appointment", comment: "Visit day hero title"))
                    .appFont(.displayTitle)
                    .fontWeight(.bold)
                    .foregroundStyle(EditorialPalette.textPrimary)
                Text(visit.scheduledDate.formatted(date: .omitted, time: .shortened))
                    .appFontNumeric(.heroNumber)
                    .foregroundStyle(AppColor.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
            }

            AppDivider()

            placeSummary

            Button {
                onOpenReport()
            } label: {
                Label(NSLocalizedString("Show Visit Report", comment: "Visit day primary action"), systemImage: "doc.text.magnifyingglass")
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity, minHeight: 52)
            }
            .buttonStyle(.borderedProminent)
            .tint(EditorialPalette.primary)

            VStack(alignment: .leading, spacing: EditorialSpacing.sm) {
                Text(NSLocalizedString("Before you leave", comment: "Visit day checklist title"))
                    .appFont(.micro)
                    .textCase(.uppercase)
                    .tracking(0.7)
                    .foregroundStyle(AppColor.textSecondary)

                ForEach(Array(checklistItems.enumerated()), id: \.element.id) { index, item in
                    checklistRow(item)
                    if index < checklistItems.count - 1 {
                        AppDivider()
                    }
                }
            }

            AppDivider()

            VStack(spacing: EditorialSpacing.sm) {
                Button {
                    onMarkDoneAndCapture()
                } label: {
                    Label(NSLocalizedString("After the visit, record doctor's plan", comment: "Visit day post appointment action"), systemImage: "square.and.pencil")
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity, minHeight: 46)
                }
                .buttonStyle(.bordered)
                .tint(EditorialPalette.primary)
            }
        }
        .padding(.vertical, EditorialSpacing.sm)
    }

    @ViewBuilder
    private var placeSummary: some View {
        let place = [visit.hospital, visit.department, visit.doctorName]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: ", ")

        if place.isEmpty {
            Button {
                onEditVisit()
            } label: {
                Label(NSLocalizedString("Add clinic details", comment: "Visit day missing appointment details"), systemImage: "square.and.pencil")
                    .appFont(.body)
                    .foregroundStyle(AppColor.primary)
            }
            .buttonStyle(.plain)
        } else {
            Label(place, systemImage: "building.2")
                .appFont(.body)
                .fontWeight(.semibold)
                .foregroundStyle(AppColor.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var checklistItems: [ChecklistItem] {
        [
            ChecklistItem(
                id: "cards",
                title: NSLocalizedString("ID and insurance card", comment: "Visit day checklist item"),
                detail: "",
                systemImage: "person.text.rectangle"
            ),
            ChecklistItem(
                id: "meds",
                title: NSLocalizedString("Medication list", comment: "Visit day checklist item"),
                detail: "",
                systemImage: "pills"
            ),
            ChecklistItem(
                id: "readings",
                title: NSLocalizedString("Home readings", comment: "Visit day checklist item"),
                detail: "",
                systemImage: "waveform.path.ecg"
            )
        ]
    }

    private func checklistRow(_ item: ChecklistItem) -> some View {
        let _ = checklistRevision
        let isDone = checklistDone(itemID: item.id)

        return Button {
            setChecklistDone(!isDone, itemID: item.id)
        } label: {
            HStack(alignment: .top, spacing: EditorialSpacing.sm) {
                Image(systemName: isDone ? "checkmark" : item.systemImage)
                    .font(.system(size: 15, weight: .regular))
                    .foregroundStyle(isDone ? AppColor.success : AppColor.primary)
                    .frame(width: 22, alignment: .center)

                VStack(alignment: .leading, spacing: 2) {
                    Text(item.title)
                        .appFont(.body)
                        .fontWeight(.semibold)
                        .foregroundStyle(AppColor.textPrimary)
                    if !item.detail.isEmpty {
                        Text(item.detail)
                            .appFont(.caption)
                            .foregroundStyle(AppColor.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: EditorialSpacing.sm)
            }
            .padding(.vertical, EditorialSpacing.xs)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func checklistDone(itemID: String) -> Bool {
        UserDefaults.standard.bool(forKey: checklistKey(itemID: itemID))
    }

    private func setChecklistDone(_ done: Bool, itemID: String) {
        UserDefaults.standard.set(done, forKey: checklistKey(itemID: itemID))
        checklistRevision += 1
    }

    private func checklistKey(itemID: String) -> String {
        "visitDayChecklist.\(visit.id.uuidString).\(itemID)"
    }
}

// MARK: - Daily status hero sub-sections

/// The two daily measurement prompts (BP, glucose) shown in the quiet hero.
/// Status strings are computed by the caller; logging is delegated.
struct MeasurementInlineSection: View {
    let bloodPressureStatus: String
    let bloodGlucoseStatus: String
    var onLog: (MeasurementType) -> Void

    var body: some View {
        VStack(spacing: EditorialSpacing.sm) {
            row(
                title: NSLocalizedString("Blood pressure", comment: "Measurement quick prompt"),
                value: bloodPressureStatus,
                type: .bloodPressure
            )
            row(
                title: NSLocalizedString("Blood glucose", comment: "Measurement quick prompt"),
                value: bloodGlucoseStatus,
                type: .bloodGlucose
            )
        }
    }

    private func row(title: String, value: String, type: MeasurementType) -> some View {
        Button {
            Haptics.impact(.light)
            onLog(type)
        } label: {
            HStack {
                Text(title)
                    .appFont(.body)
                    .foregroundStyle(EditorialPalette.textPrimary)
                Spacer()
                Text(value)
                    .appFont(.caption)
                    .foregroundStyle(EditorialPalette.textSecondary)
                Image(systemName: "plus")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(EditorialPalette.primary)
                    .frame(width: 32, height: 32)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(EditorialPalette.divider, lineWidth: 1)
                    )
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// One-tap daily feeling check-in (Good / Okay / Unwell) plus a detail shortcut.
/// Selection handling and the confirmation string live with the caller.
struct FeelingCheckIn: View {
    let symptomLoggedToday: Bool
    let confirmation: String?
    var onAddDetail: () -> Void
    var onSelectFeeling: (QuickFeeling) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: EditorialSpacing.md) {
            HStack {
                Text(NSLocalizedString("Body check-in", comment: "Quick daily feeling header"))
                    .appFont(.headline)
                    .fontWeight(.semibold)
                    .foregroundStyle(EditorialPalette.textPrimary)

                Spacer()

                HStack(spacing: EditorialSpacing.sm) {
                    if symptomLoggedToday {
                        Text(NSLocalizedString("Logged today", comment: "Quick feeling logged status"))
                            .appFont(.caption)
                            .foregroundStyle(EditorialPalette.textSecondary)
                    }

                    Button {
                        Haptics.impact(.light)
                        onAddDetail()
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(EditorialPalette.primary)
                            .frame(width: 34, height: 34)
                            .overlay(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .stroke(EditorialPalette.divider, lineWidth: 1)
                            )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(NSLocalizedString("Add symptom detail", comment: "Body check-in detail action"))
                }
            }

            HStack(spacing: EditorialSpacing.sm) {
                ForEach(QuickFeeling.allCases) { feeling in
                    feelingButton(feeling)
                }
            }

            if let confirmation {
                Text(confirmation)
                    .appFont(.caption)
                    .foregroundStyle(EditorialPalette.textSecondary)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    private func feelingButton(_ feeling: QuickFeeling) -> some View {
        Button {
            Haptics.impact(.light)
            onSelectFeeling(feeling)
        } label: {
            HStack(spacing: EditorialSpacing.sm) {
                Image(systemName: feeling.iconName)
                    .font(.system(size: 16, weight: .regular))
                    .foregroundStyle(feeling.tint)
                Text(feeling.title)
                    .appFont(.body)
                    .fontWeight(.medium)
                    .lineLimit(1)
            }
            .foregroundStyle(EditorialPalette.textPrimary)
            .frame(maxWidth: .infinity, minHeight: 46, alignment: .center)
            .padding(.horizontal, EditorialSpacing.sm)
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(EditorialPalette.divider, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(feeling.title)
    }
}
