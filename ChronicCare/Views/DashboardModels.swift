import SwiftUI

// MARK: - Dashboard model types
//
// Value types shared across the Today dashboard and its extracted cards. These
// were previously private nested types inside DashboardView; lifting them to
// file scope lets standalone card views reference them without widening the
// dashboard's own surface. Pure data — no view state, no behavior change.

struct MedSchedule: Identifiable {
    let id: String // medID_HH:MM
    let med: Medication
    let time: Date
    var scheduleKey: String {
        let comps = Calendar.current.dateComponents([.hour, .minute], from: time)
        return String(format: "%@_%02d:%02d", med.id.uuidString, comps.hour ?? 0, comps.minute ?? 0)
    }
}

struct ScheduleLookupKey: Hashable {
    let medicationID: UUID
    let scheduleKey: String?
}

enum TodayMedStatus {
    case none
    case taken(Date)
    case skipped(Date)
    case snoozed(Date)
    case dueSoon // past scheduled time but within grace period
    case overdue

    var displayText: String {
        switch self {
        case .taken:   return NSLocalizedString("Taken", comment: "")
        case .skipped: return NSLocalizedString("Skipped", comment: "")
        case .snoozed: return NSLocalizedString("Snoozed", comment: "")
        case .overdue: return NSLocalizedString("Overdue", comment: "")
        case .dueSoon: return NSLocalizedString("Due now", comment: "")
        case .none:    return NSLocalizedString("Later", comment: "")
        }
    }

    var tint: Color {
        switch self {
        case .taken:   return AppColor.success
        case .skipped: return AppColor.textSecondary
        case .snoozed: return AppColor.primary
        case .overdue: return AppColor.warning
        case .dueSoon: return AppColor.warning
        case .none:    return AppColor.textSecondary
        }
    }

    var iconName: String {
        switch self {
        case .taken:   return "checkmark"
        case .skipped: return "xmark"
        case .snoozed: return "zzz"
        case .overdue: return "exclamationmark.triangle"
        case .dueSoon: return "clock"
        case .none:    return "clock"
        }
    }

    var isFinal: Bool {
        switch self {
        case .taken, .skipped: return true
        default: return false
        }
    }
}

struct MissedDoseRecoveryGuidance {
    let title: String
    let message: String
    let compactText: String
    let icon: String
    let tint: Color
}

enum HomeMode {
    case quietAccumulation
    case lightPrep(DoctorVisit, daysUntil: Int)
    case activePrep(DoctorVisit, daysUntil: Int)
    case visitDay(DoctorVisit)
    case postVisitCapture(DoctorVisit)
}

enum QuickFeeling: String, CaseIterable, Identifiable {
    case good
    case okay
    case unwell

    var id: String { rawValue }

    var title: String {
        switch self {
        case .good:
            return NSLocalizedString("Good", comment: "Quick feeling option")
        case .okay:
            return NSLocalizedString("Okay", comment: "Quick feeling option")
        case .unwell:
            return NSLocalizedString("Unwell", comment: "Quick feeling option")
        }
    }

    var iconName: String {
        switch self {
        case .good:
            return "face.smiling"
        case .okay:
            return "minus.circle"
        case .unwell:
            return "heart.text.square"
        }
    }

    var tint: Color {
        switch self {
        case .good:
            return AppColor.success
        case .okay:
            return AppColor.textSecondary
        case .unwell:
            return AppColor.warning
        }
    }

    var symptomTag: String {
        switch self {
        case .good:
            return NSLocalizedString("Felt good", comment: "Quick feeling symptom tag")
        case .okay:
            return NSLocalizedString("Felt okay", comment: "Quick feeling symptom tag")
        case .unwell:
            return NSLocalizedString("Felt unwell", comment: "Quick feeling symptom tag")
        }
    }
}

struct TodayState {
    let schedules: [MedSchedule]
    let statusCache: [String: TodayMedStatus]
    let takenCount: Int
    let skippedCount: Int
    let totalCount: Int
    let overdueCount: Int
    let remainingCount: Int
    let actionableSchedules: [MedSchedule]
    let currentAction: MedSchedule?
    let nextUpcoming: MedSchedule?
    let prnMeds: [Medication]
}
