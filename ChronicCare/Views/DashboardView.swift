import SwiftUI
import UserNotifications

struct DashboardView: View {
    // V2 entry point injected from RootViewV2. When set, a weekly adherence
    // reflection card is appended below today's actionable content that
    // opens the adherence calendar directly.
    var onOpenCalendar: (() -> Void)? = nil
    var onLogMeasurement: ((MeasurementType) -> Void)? = nil
    var onOpenProfile: (() -> Void)? = nil

    @EnvironmentObject var store: DataStore
    @State private var showAddMedication = false
    @State private var reminderFixTarget: Medication? = nil
    @State private var notificationStatus: UNAuthorizationStatus = .notDetermined
    @State private var showTakenConfirmation = false
    @State private var takenMedName: String = ""
    @State private var pendingNoteItem: MedSchedule?
    @State private var showDuplicateAlert = false
    @State private var duplicateAlertMinutes: Int = 0
    @AppStorage("units.glucose") private var glucoseUnitRaw: String = GlucoseUnit.mgdL.rawValue
    @AppStorage("prefs.graceMinutes") private var graceMinutes: Int = 30
    @State private var tick = false
    @State private var showAllPRN = false
    @State private var showFullTodaySchedule = false
    @State private var showSymptomLog = false
    @State private var showDoctorVisitForm = false
    @State private var editingDoctorVisit: DoctorVisit?
    @State private var showVisitSnapshot = false
    @State private var quickFeelingConfirmation: String?
    private let refreshTimer = Timer.publish(every: 60, on: .main, in: .common).autoconnect()

    private struct MedSchedule: Identifiable {
        let id: String // medID_HH:MM
        let med: Medication
        let time: Date
        var scheduleKey: String {
            let comps = Calendar.current.dateComponents([.hour, .minute], from: time)
            return String(format: "%@_%02d:%02d", med.id.uuidString, comps.hour ?? 0, comps.minute ?? 0)
        }
    }

    private struct ScheduleLookupKey: Hashable {
        let medicationID: UUID
        let scheduleKey: String?
    }

    private enum TodayMedStatus {
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
            case .taken:   return "checkmark.circle.fill"
            case .skipped: return "xmark.circle.fill"
            case .snoozed: return "zzz"
            case .overdue: return "exclamationmark.circle.fill"
            case .dueSoon: return "clock.fill"
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

    private struct MissedDoseRecoveryGuidance {
        let title: String
        let message: String
        let compactText: String
        let icon: String
        let tint: Color
    }

    private enum HomeMode {
        case quietAccumulation
        case lightPrep(DoctorVisit, daysUntil: Int)
        case activePrep(DoctorVisit, daysUntil: Int)
        case visitDay(DoctorVisit)
        case postVisitCapture(DoctorVisit)
    }

    private enum QuickFeeling: String, CaseIterable, Identifiable {
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

    private struct TodayState {
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

    private func buildTodayState() -> TodayState {
        let schedules = todaySchedules()
        let statusLookup = latestTodayLogMap()
        let statusCache: [String: TodayMedStatus] = Dictionary(uniqueKeysWithValues: schedules.map { item in
            let s = status(for: item.med, at: item.time, lookup: statusLookup)
            let resolved: TodayMedStatus = {
                switch s {
                case .none:
                    let now = Date()
                    let graceMin = Double(graceMinutes)
                    if now > item.time.addingTimeInterval(graceMin * 60) { return .overdue }
                    else if now > item.time { return .dueSoon }
                    else { return s }
                default: return s
                }
            }()
            return (item.id, resolved)
        })
        let takenCount = statusCache.values.filter { if case .taken = $0 { return true } else { return false } }.count
        let skippedCount = statusCache.values.filter { if case .skipped = $0 { return true } else { return false } }.count
        let totalCount = schedules.count
        let actionableSchedules = schedules.filter { canLogDose(for: $0, status: statusCache[$0.id] ?? .none) }
        let nextUpcoming = schedules.first {
            let status = statusCache[$0.id] ?? .none
            return !canLogDose(for: $0, status: status) && !status.isFinal
        }
        let overdueCount = schedules.filter {
            if case .overdue = statusCache[$0.id] ?? .none { return true }
            return false
        }.count
        return TodayState(
            schedules: schedules,
            statusCache: statusCache,
            takenCount: takenCount,
            skippedCount: skippedCount,
            totalCount: totalCount,
            overdueCount: overdueCount,
            remainingCount: max(totalCount - takenCount - skippedCount, 0),
            actionableSchedules: actionableSchedules,
            currentAction: actionableSchedules.first,
            nextUpcoming: nextUpcoming,
            prnMeds: store.medications.filter { $0.isAsNeeded == true }
        )
    }

    var body: some View {
        let _ = tick // force re-render on timer
        NavigationStack {
            let state = buildTodayState()
            let schedules = state.schedules
            let statusCache = state.statusCache
            let takenCount = state.takenCount
            let totalCount = state.totalCount
            let currentAction = state.currentAction
            let nextUpcoming = state.nextUpcoming
            let prnMeds = state.prnMeds
            let mode = homeMode

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    homeHeader()

                    switch mode {
                    case .quietAccumulation:
                        dailyStatusHero(state: state)
                    case .lightPrep(let visit, let days):
                        lightPrepHero(visit: visit, daysUntil: days, state: state)
                        visitDataReadinessCard(visit: visit, mode: mode)
                    case .activePrep(let visit, let days):
                        lightPrepHero(visit: visit, daysUntil: days, state: state)
                        visitDataReadinessCard(visit: visit, mode: mode)
                    case .visitDay(let visit):
                        visitDayBoardingPass(visit: visit)
                    case .postVisitCapture(let visit):
                        postVisitCaptureCard(visit: visit)
                    }

                    if notificationStatus == .denied {
                        reminderRepairCard()
                    }

                    let safety = safetySummary
                    if safety.hasIssues {
                        safetyNoticeCard(summary: safety)
                    }

                    if let gap = daysSinceLastLog, gap >= 2, !store.medications.isEmpty {
                        inactivityWarningCard(daysSince: gap)
                    }

                    if store.medications.isEmpty {
                        Card {
                            EmptyStateView(
                                systemImage: "pills.circle.fill",
                                title: NSLocalizedString("No medications yet", comment: ""),
                                subtitle: NSLocalizedString("Add your first medication to start daily reminders and logging.", comment: ""),
                                actionTitle: NSLocalizedString("Add Medication", comment: ""),
                                action: { showAddMedication = true }
                            )
                        }
                    } else {
                        let allComplete = currentAction == nil && nextUpcoming == nil && totalCount > 0

                        if allComplete {
                            todayCompleteHero(
                                takenCount: takenCount,
                                skippedCount: state.skippedCount,
                                totalCount: totalCount,
                                mode: mode
                            )

                            if !schedules.isEmpty {
                                todayUnifiedList(
                                    schedules: schedules,
                                    statusCache: statusCache,
                                    currentActionID: nil,
                                    nextUpcomingID: nextUpcoming?.id,
                                    collapsedLimit: 3
                                )
                            }
                        } else if !schedules.isEmpty {
                            todayUnifiedList(
                                schedules: schedules,
                                statusCache: statusCache,
                                currentActionID: currentAction?.id,
                                nextUpcomingID: nextUpcoming?.id,
                                collapsedLimit: 3
                            )
                        }

                        if !prnMeds.isEmpty {
                            asNeededInlineSection(medications: prnMeds)
                        }
                    }

                    if notificationStatus != .denied && hasReminderSetupIssues {
                        reminderRepairCard()
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 10)
                .padding(.bottom, 24)
            }
            .sheet(isPresented: $showSymptomLog) {
                SymptomQuickLogSheet()
                    .environmentObject(store)
            }
            .sheet(isPresented: $showDoctorVisitForm) {
                NavigationStack {
                    DoctorVisitFormView()
                        .environmentObject(store)
                }
            }
            .sheet(item: $editingDoctorVisit) { visit in
                NavigationStack {
                    DoctorVisitFormView(editing: visit)
                        .environmentObject(store)
                }
            }
            .sheet(isPresented: $showVisitSnapshot) {
                NavigationStack {
                    ConsultationSnapshotView(visit: store.nextDoctorVisit)
                        .environmentObject(store)
                        .toolbar {
                            ToolbarItem(placement: .topBarTrailing) {
                                Button(NSLocalizedString("Done", comment: "")) {
                                    showVisitSnapshot = false
                                }
                            }
                        }
                }
            }
            .sheet(isPresented: $showAddMedication) {
                MedicationFormView(editing: nil, onSave: { med in
                    let result = store.addMedication(med)
                    if result == nil {
                        store.syncNotifications()
                    }
                    return result
                })
            }
            .sheet(item: $reminderFixTarget) { med in
                MedicationFormView(editing: med, onSave: { updated in
                    let result = store.updateMedication(updated)
                    if result == nil {
                        store.syncNotifications()
                        refreshNotificationStatus()
                    }
                    return result
                })
            }
            .refreshable {
                let now = Date()
                store.syncNotifications(now: now)
                refreshNotificationStatus()
                store.objectWillChange.send()
            }
            .toolbar(.hidden, for: .navigationBar)
            .onReceive(refreshTimer) { _ in tick.toggle() }
            // Rule 1: Duplicate taken confirmation
            .alert(NSLocalizedString("Already Taken", comment: ""), isPresented: $showDuplicateAlert) {
                Button(NSLocalizedString("Take Again", comment: ""), role: .destructive) {
                    commitTaken(note: nil)
                }
                Button(NSLocalizedString("Cancel", comment: ""), role: .cancel) {
                    pendingNoteItem = nil
                }
            } message: {
                Text(String(format: NSLocalizedString("You took this %lld minutes ago. Are you sure you want to log another dose?", comment: ""), duplicateAlertMinutes))
            }
            .overlay {
                if showTakenConfirmation {
                    TakenConfirmationOverlay(medicationName: takenMedName)
                        .transition(.opacity)
                        .zIndex(100)
                }
            }
            .onAppear {
                refreshNotificationStatus()
            }
        }
    }

    private func homeHeader() -> some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(NSLocalizedString("Today", comment: "Home header eyebrow"))
                    .appFont(.micro)
                    .fontWeight(.semibold)
                    .foregroundStyle(EditorialPalette.textSecondary)
                    .textCase(.uppercase)
                    .tracking(0.8)
                Text(homeDateText)
                    .appFont(.headline)
                    .fontWeight(.semibold)
                    .foregroundStyle(.primary)
            }

            Spacer()

            Button {
                onOpenProfile?()
            } label: {
                Image(systemName: "person.crop.circle")
                    .font(.system(size: 22, weight: .regular))
                    .foregroundStyle(EditorialPalette.textPrimary)
                    .frame(width: 42, height: 42)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(NSLocalizedString("Profile", comment: ""))
        }
        .padding(.bottom, 4)
    }

    private var homeDateText: String {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("MMMEd")
        return formatter.string(from: Date())
    }
}

// MARK: - Taken Confirmation Overlay
private struct TakenConfirmationOverlay: View {
    let medicationName: String
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 72, weight: .bold))
                .foregroundStyle(AppColor.success)
                .symbolRenderingMode(.hierarchical)
            Text(medicationName)
                .appFont(.headline)
                .foregroundStyle(.primary)
            Text(NSLocalizedString("Taken!", comment: ""))
                .appFont(.title)
                .fontWeight(.bold)
                .foregroundStyle(AppColor.success)
        }
        .padding(40)
        .background(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(.ultraThickMaterial)
                .shadow(color: .black.opacity(0.15), radius: 20, y: 10)
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black.opacity(0.25).ignoresSafeArea())
    }
}

private extension DashboardView {
    private enum VisitPrepPriority {
        case pinned
        case secondary
    }

    private enum ReadinessStatus {
        case ready
        case needsAction
        case optional

        var iconName: String {
            switch self {
            case .ready: return "checkmark"
            case .needsAction: return "exclamationmark"
            case .optional: return "minus"
            }
        }

        var tint: Color {
            switch self {
            case .ready: return EditorialPalette.primary
            case .needsAction: return EditorialPalette.warning
            case .optional: return EditorialPalette.textTertiary
            }
        }
    }

    private struct VisitReadinessItem {
        let title: String
        let detail: String
        let status: ReadinessStatus
        let countsTowardScore: Bool
        let action: () -> Void
    }

    private var untimedScheduledMeds: [Medication] {
        store.medications.filter { $0.isAsNeeded != true && $0.timesOfDay.isEmpty }
    }

    private var disabledReminderMeds: [Medication] {
        store.medications.filter { $0.isAsNeeded != true && !$0.timesOfDay.isEmpty && !$0.remindersEnabled }
    }

    private var hasReminderSetupIssues: Bool {
        notificationStatus == .denied || !untimedScheduledMeds.isEmpty || !disabledReminderMeds.isEmpty
    }

    private var homeMode: HomeMode {
        if let visit = recentCompletedVisitForCapture {
            return .postVisitCapture(visit)
        }

        guard let visit = store.nextDoctorVisit,
              let days = visit.daysUntil() else {
            return .quietAccumulation
        }

        if days == 0 { return .visitDay(visit) }
        if days <= 3 { return .activePrep(visit, daysUntil: days) }
        if days <= 7 { return .lightPrep(visit, daysUntil: days) }
        return .quietAccumulation
    }

    private var recentCompletedVisitForCapture: DoctorVisit? {
        let now = Date()
        return store.completedDoctorVisits.first { visit in
            guard let completedDate = visit.completedDate else { return false }
            guard now.timeIntervalSince(completedDate) <= 48 * 60 * 60 else { return false }
            return needsPostVisitCapture(visit)
        }
    }

    private func needsPostVisitCapture(_ visit: DoctorVisit) -> Bool {
        let notesEmpty = visit.notes?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true
        let changesEmpty = visit.medicationChangesSummary?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true
        return notesEmpty || changesEmpty || visit.nextVisitDate == nil
    }

    /// How many days since the last intake log for any scheduled medication. Nil if no scheduled meds.
    private var daysSinceLastLog: Int? {
        let scheduledMeds = store.medications.filter { $0.isAsNeeded != true && $0.remindersEnabled && !$0.timesOfDay.isEmpty }
        guard !scheduledMeds.isEmpty else { return nil }
        let scheduledIDs = Set(scheduledMeds.map { $0.id })
        let latestLog = store.intakeLogs
            .filter { scheduledIDs.contains($0.medicationID) }
            .max(by: { $0.date < $1.date })
        guard let latestLog else { return nil }
        let cal = Calendar.current
        return cal.dateComponents([.day], from: cal.startOfDay(for: latestLog.date), to: cal.startOfDay(for: Date())).day
    }

    private func dailyStatusHero(state: TodayState) -> some View {
        VStack(alignment: .leading, spacing: EditorialSpacing.lg) {
            editorialDivider()

            VStack(alignment: .leading, spacing: EditorialSpacing.sm) {
                Text(NSLocalizedString("Today", comment: "Dashboard daily status title"))
                    .appFont(.headline)
                    .foregroundStyle(EditorialPalette.textPrimary)

                HStack(alignment: .firstTextBaseline, spacing: EditorialSpacing.md) {
                    Text("\(state.takenCount + state.skippedCount)")
                        .appFontNumeric(.heroNumber)
                        .foregroundStyle(EditorialPalette.textPrimary)

                    VStack(alignment: .leading, spacing: EditorialSpacing.xs) {
                        Rectangle()
                            .fill(EditorialPalette.textPrimary)
                            .frame(width: 48, height: 1)
                        Text(String(format: NSLocalizedString("of %lld items", comment: "Daily dose progress denominator"), state.totalCount))
                            .appFont(.caption)
                            .foregroundStyle(EditorialPalette.textSecondary)
                    }
                }

                if let current = state.currentAction ?? state.nextUpcoming {
                    nextDoseEditorialLine(item: current, isActionable: state.currentAction != nil)
                } else {
                    Text(dailyStatusTitle(state: state))
                        .appFont(.caption)
                        .foregroundStyle(EditorialPalette.textSecondary)
                }
            }

            editorialDivider()

            dailyMeasurementInlineSection()

            editorialDivider()

            dailyFeelingCheckIn()
        }
    }

    private func nextDoseEditorialLine(item: MedSchedule, isActionable: Bool) -> some View {
        VStack(alignment: .leading, spacing: EditorialSpacing.sm) {
            Text(String(format: NSLocalizedString("Next item %@", comment: "Dashboard next dose label"), item.time.formatted(date: .omitted, time: .shortened)))
                .appFont(.micro)
                .textCase(.uppercase)
                .tracking(0.6)
                .foregroundStyle(EditorialPalette.textSecondary)

            Text(item.med.name)
                .appFont(.headline)
                .foregroundStyle(EditorialPalette.textPrimary)

            Text(item.med.dose)
                .appFont(.caption)
                .foregroundStyle(EditorialPalette.textSecondary)

            if isActionable {
                HStack(spacing: EditorialSpacing.sm) {
                    EditorialButton(NSLocalizedString("Take", comment: ""), kind: .primary) {
                        beginTakeFlow(for: item)
                    }

                    EditorialButton(NSLocalizedString("Skip", comment: ""), kind: .secondary) {
                        skipDose(for: item)
                    }
                }
                .padding(.top, EditorialSpacing.xs)
            }
        }
    }

    private func dailyMeasurementInlineSection() -> some View {
        VStack(spacing: EditorialSpacing.sm) {
            measurementPromptRow(
                title: NSLocalizedString("Blood pressure", comment: "Measurement quick prompt"),
                value: todayMeasurementStatus(for: .bloodPressure),
                type: .bloodPressure
            )
            measurementPromptRow(
                title: NSLocalizedString("Blood glucose", comment: "Measurement quick prompt"),
                value: todayMeasurementStatus(for: .bloodGlucose),
                type: .bloodGlucose
            )
        }
    }

    private func measurementPromptRow(title: String, value: String, type: MeasurementType) -> some View {
        Button {
            Haptics.impact(.light)
            onLogMeasurement?(type)
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

    private func editorialDivider() -> some View {
        AppDivider()
    }

    private func dailyFeelingCheckIn() -> some View {
        VStack(alignment: .leading, spacing: EditorialSpacing.md) {
            HStack {
                Text(NSLocalizedString("Body check-in", comment: "Quick daily feeling header"))
                    .appFont(.headline)
                    .fontWeight(.semibold)
                    .foregroundStyle(EditorialPalette.textPrimary)

                Spacer()

                HStack(spacing: EditorialSpacing.sm) {
                    if todaySymptomCount > 0 {
                        Text(NSLocalizedString("Logged today", comment: "Quick feeling logged status"))
                            .appFont(.caption)
                            .foregroundStyle(EditorialPalette.textSecondary)
                    }

                    Button {
                        Haptics.impact(.light)
                        showSymptomLog = true
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
                    quickFeelingButton(feeling)
                }
            }

            if let quickFeelingConfirmation {
                Text(quickFeelingConfirmation)
                    .appFont(.caption)
                    .foregroundStyle(EditorialPalette.textSecondary)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    private func quickFeelingButton(_ feeling: QuickFeeling) -> some View {
        Button {
            Haptics.impact(.light)
            handleQuickFeeling(feeling)
        } label: {
            HStack(spacing: EditorialSpacing.sm) {
                Image(systemName: "circle")
                    .font(.system(size: 16, weight: .regular))
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

    private func dailyMetricPill(value: String, label: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .appFont(.headline)
                .fontWeight(.bold)
                .foregroundStyle(EditorialPalette.textPrimary)
                .monospacedDigit()
            Text(label)
                .appFont(.caption)
                .foregroundStyle(EditorialPalette.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, EditorialSpacing.sm)
    }

    private var todayMeasurementCount: Int {
        store.measurements.filter { Calendar.current.isDateInToday($0.date) }.count
    }

    private func todayMeasurementStatus(for type: MeasurementType) -> String {
        let hasLogged = store.measurements.contains {
            $0.type == type && Calendar.current.isDateInToday($0.date)
        }
        return hasLogged
            ? NSLocalizedString("Logged", comment: "Measurement logged status")
            : NSLocalizedString("Not measured", comment: "Measurement missing status")
    }

    private var todaySymptomCount: Int {
        store.symptomEntries.filter { Calendar.current.isDateInToday($0.date) }.count
    }

    private func handleQuickFeeling(_ feeling: QuickFeeling) {
        if feeling == .unwell {
            showSymptomLog = true
            return
        }

        let quickTags = Set(QuickFeeling.allCases.map(\.symptomTag))
        let now = Date()
        let entry = SymptomEntry(
            date: now,
            tags: [feeling.symptomTag],
            severity: .mild,
            note: nil,
            relatedMedicationIDs: nil
        )

        if let existing = store.symptomEntries.first(where: { existing in
            Calendar.current.isDateInToday(existing.date)
                && existing.tags.contains(where: { quickTags.contains($0) })
                && (existing.note?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
        }) {
            var updated = existing
            updated.date = now
            updated.tags = entry.tags
            updated.severity = entry.severity
            store.updateSymptomEntry(updated)
        } else {
            store.addSymptomEntry(entry)
        }

        let message = String(format: NSLocalizedString("Saved: %@", comment: "Quick feeling saved confirmation"), feeling.title)
        withAnimation(.easeInOut(duration: 0.2)) {
            quickFeelingConfirmation = message
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            if quickFeelingConfirmation == message {
                withAnimation(.easeInOut(duration: 0.2)) {
                    quickFeelingConfirmation = nil
                }
            }
        }
    }

    private func dailyStatusTitle(state: TodayState) -> String {
        if state.overdueCount > 0 {
            return String(format: NSLocalizedString("%lld doses need attention", comment: "Daily status title"), state.overdueCount)
        }
        if state.currentAction != nil {
            return NSLocalizedString("One thing to handle now", comment: "Daily status title")
        }
        if state.totalCount == 0 {
            return NSLocalizedString("Start today's health log", comment: "Daily status title")
        }
        if state.remainingCount == 0 {
            return NSLocalizedString("Today is documented", comment: "Daily status title")
        }
        return String(format: NSLocalizedString("%lld doses left today", comment: "Daily status title"), state.remainingCount)
    }

    private func dailyStatusIconName(state: TodayState) -> String {
        if state.overdueCount > 0 { return "exclamationmark.triangle.fill" }
        if state.currentAction != nil { return "clock.badge.exclamationmark.fill" }
        if state.remainingCount == 0, state.totalCount > 0 { return "checkmark.seal.fill" }
        return "heart.text.square.fill"
    }

    private func dailyStatusTint(state: TodayState) -> Color {
        if state.overdueCount > 0 { return EditorialPalette.warning }
        if state.currentAction != nil { return EditorialPalette.primary }
        if state.remainingCount == 0, state.totalCount > 0 { return EditorialPalette.success }
        return EditorialPalette.primary
    }

    private func lightPrepHero(visit: DoctorVisit, daysUntil: Int, state: TodayState) -> some View {
        VStack(alignment: .leading, spacing: EditorialSpacing.lg) {
            editorialDivider()

            VStack(alignment: .leading, spacing: EditorialSpacing.xs) {
                Text(NSLocalizedString("Appointment countdown", comment: "Visit prep editorial title"))
                    .appFont(.micro)
                    .textCase(.uppercase)
                    .tracking(0.7)
                    .foregroundStyle(AppColor.textSecondary)

                Text(String(format: NSLocalizedString("%lld days", comment: "Visit countdown hero number"), daysUntil))
                    .appFontNumeric(.heroNumber)
                    .foregroundStyle(AppColor.primary)

                Text(visitSupportingLine(visit))
                    .appFont(.caption)
                    .foregroundStyle(AppColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Button {
                showVisitSnapshot = true
            } label: {
                HStack {
                    Text(NSLocalizedString("Open visit summary", comment: "Visit prep summary action"))
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

    private func visitDayBoardingPass(visit: DoctorVisit) -> some View {
        TintedCard(tint: EditorialPalette.primary) {
            VStack(alignment: .leading, spacing: EditorialSpacing.lg) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(NSLocalizedString("Today is your appointment", comment: "Visit day hero title"))
                        .appFont(.displayTitle)
                        .fontWeight(.bold)
                        .foregroundStyle(EditorialPalette.textPrimary)
                    Text(visitSupportingLine(visit))
                        .appFont(.subheadline)
                        .foregroundStyle(EditorialPalette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Button {
                    showVisitSnapshot = true
                } label: {
                    Label(NSLocalizedString("Show Doctor Snapshot", comment: "Visit day primary action"), systemImage: "doc.text.magnifyingglass")
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity, minHeight: 52)
                }
                .buttonStyle(.borderedProminent)
                .tint(EditorialPalette.primary)

                InsetPanel(tint: nil) {
                    VStack(alignment: .leading, spacing: 8) {
                        Label(NSLocalizedString("Bring ID, insurance card, and your medication list.", comment: "Visit day reminder"), systemImage: "checklist")
                            .appFont(.caption)
                            .foregroundStyle(EditorialPalette.textSecondary)
                        Button {
                            editingDoctorVisit = visit
                        } label: {
                            Label(NSLocalizedString("Record doctor notes after the visit", comment: "Visit day secondary action"), systemImage: "square.and.pencil")
                                .appFont(.caption)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private func postVisitCaptureCard(visit: DoctorVisit) -> some View {
        TintedCard(tint: EditorialPalette.primary) {
            VStack(alignment: .leading, spacing: EditorialSpacing.lg) {
                VStack(alignment: .leading, spacing: EditorialSpacing.sm) {
                    Text(NSLocalizedString("Capture what the doctor said", comment: "Post visit capture title"))
                        .appFont(.displayTitle)
                        .fontWeight(.bold)
                        .foregroundStyle(EditorialPalette.textPrimary)
                    Text(NSLocalizedString("The first 48 hours after a visit are the best time to record instructions, medication changes, and the next appointment.", comment: "Post visit capture subtitle"))
                        .appFont(.caption)
                        .foregroundStyle(EditorialPalette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                VStack(alignment: .leading, spacing: EditorialSpacing.sm) {
                    readinessRow(
                        title: NSLocalizedString("Doctor instructions", comment: "Post visit checklist"),
                        detail: visit.notes?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
                            ? NSLocalizedString("Saved", comment: "")
                            : NSLocalizedString("Not recorded yet", comment: ""),
                        isReady: visit.notes?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false,
                        action: { editingDoctorVisit = visit }
                    )
                    readinessRow(
                        title: NSLocalizedString("Medication changes", comment: "Post visit checklist"),
                        detail: visit.medicationChangesSummary?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
                            ? NSLocalizedString("Saved", comment: "")
                            : NSLocalizedString("Not recorded yet", comment: ""),
                        isReady: visit.medicationChangesSummary?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false,
                        action: { editingDoctorVisit = visit }
                    )
                    readinessRow(
                        title: NSLocalizedString("Next appointment", comment: "Post visit checklist"),
                        detail: visit.nextVisitDate?.formatted(date: .abbreviated, time: .omitted) ?? NSLocalizedString("Not scheduled yet", comment: ""),
                        isReady: visit.nextVisitDate != nil,
                        action: { editingDoctorVisit = visit }
                    )
                }

                Button {
                    editingDoctorVisit = visit
                } label: {
                    Label(NSLocalizedString("Record Visit Notes", comment: "Post visit capture action"), systemImage: "square.and.pencil")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(EditorialPalette.primary)
            }
        }
    }

    private func visitDataReadinessCard(visit: DoctorVisit, mode: HomeMode) -> some View {
        let items = visitReadinessItems(for: visit)
        let requiredItems = items.filter(\.countsTowardScore)
        let readinessCount = requiredItems.filter { $0.status == .ready }.count
        let readinessTotal = requiredItems.count

        return VStack(alignment: .leading, spacing: EditorialSpacing.md) {
            HStack(alignment: .firstTextBaseline) {
                Text(NSLocalizedString("Data readiness", comment: "Visit prep readiness card title"))
                    .appFont(.headline)
                    .foregroundStyle(AppColor.textPrimary)
                Spacer()
                Text(String(format: NSLocalizedString("%lld / %lld", comment: "Data readiness score"), readinessCount, readinessTotal))
                    .appFontNumeric(.caption)
                    .foregroundStyle(AppColor.textSecondary)
            }

            AppDivider()

            VStack(spacing: EditorialSpacing.sm) {
                ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                    readinessRow(
                        title: item.title,
                        detail: item.detail,
                        status: item.status,
                        action: item.action
                    )
                    if index < items.count - 1 {
                        AppDivider()
                    }
                }
            }
        }
    }

    private func visitReadinessItems(for visit: DoctorVisit) -> [VisitReadinessItem] {
        var items: [VisitReadinessItem] = []
        let medCount = store.medications.count
        let needsBloodPressure = store.medications.contains { $0.category == .antihypertensive }
        let needsBloodGlucose = store.medications.contains { $0.category == .antidiabetic }
        let bloodPressureCount = recentMeasurementCount(type: .bloodPressure, days: 30)
        let bloodGlucoseCount = recentMeasurementCount(type: .bloodGlucose, days: 30)
        let symptomCount = recentSymptomCount(days: 30)

        items.append(
            VisitReadinessItem(
                title: NSLocalizedString("Medication records", comment: "Visit prep readiness item"),
                detail: medCount == 0
                    ? NSLocalizedString("Add current medications", comment: "")
                    : String(format: NSLocalizedString("%lld current medications", comment: "Visit prep medication readiness detail"), medCount),
                status: medCount > 0 ? .ready : .needsAction,
                countsTowardScore: true,
                action: { showAddMedication = true }
            )
        )

        if needsBloodPressure {
            items.append(measurementReadinessItem(
                title: NSLocalizedString("Blood pressure", comment: "Visit prep readiness item"),
                type: .bloodPressure,
                count: bloodPressureCount,
                emptyDetail: NSLocalizedString("Needed for blood pressure medications", comment: "Visit prep measurement reason")
            ))
        }

        if needsBloodGlucose {
            items.append(measurementReadinessItem(
                title: NSLocalizedString("Blood glucose", comment: "Visit prep readiness item"),
                type: .bloodGlucose,
                count: bloodGlucoseCount,
                emptyDetail: NSLocalizedString("Needed for diabetes medications", comment: "Visit prep measurement reason")
            ))
        }

        if !needsBloodPressure && !needsBloodGlucose {
            items.append(
                VisitReadinessItem(
                    title: NSLocalizedString("Home measurements", comment: "Visit prep readiness item"),
                    detail: NSLocalizedString("Add only if your doctor asked you to track a value.", comment: "Visit prep optional measurement detail"),
                    status: .optional,
                    countsTowardScore: false,
                    action: { onLogMeasurement?(.bloodPressure) }
                )
            )
        }

        items.append(
            VisitReadinessItem(
                title: NSLocalizedString("Symptoms or concerns", comment: "Visit prep readiness item"),
                detail: symptomCount == 0
                    ? NSLocalizedString("No concerns recorded; fine if nothing changed.", comment: "Visit prep optional symptom detail")
                    : String(format: NSLocalizedString("%lld entries in last 30 days", comment: "Visit prep entries count"), symptomCount),
                status: symptomCount > 0 ? .ready : .optional,
                countsTowardScore: false,
                action: { showSymptomLog = true }
            )
        )

        let previousVisit = latestCompletedVisit(before: visit.scheduledDate)
        let previousChangeSaved = previousVisit?.medicationChangesSummary?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
        items.append(
            VisitReadinessItem(
                title: NSLocalizedString("Last dose adjustment", comment: "Visit prep readiness item"),
                detail: previousChangeSaved
                    ? NSLocalizedString("Saved from last visit", comment: "Visit prep prior medication change detail")
                    : NSLocalizedString("No prior adjustment recorded.", comment: "Visit prep prior medication change detail"),
                status: previousChangeSaved ? .ready : .optional,
                countsTowardScore: false,
                action: { editingDoctorVisit = previousVisit ?? visit }
            )
        )

        items.append(
            VisitReadinessItem(
                title: NSLocalizedString("Appointment details", comment: "Visit prep readiness item"),
                detail: visit.displayTitle,
                status: .ready,
                countsTowardScore: true,
                action: { editingDoctorVisit = visit }
            )
        )

        return items
    }

    private func measurementReadinessItem(title: String, type: MeasurementType, count: Int, emptyDetail: String) -> VisitReadinessItem {
        VisitReadinessItem(
            title: title,
            detail: count == 0
                ? emptyDetail
                : String(format: NSLocalizedString("%lld entries in last 30 days", comment: "Visit prep entries count"), count),
            status: count > 0 ? .ready : .needsAction,
            countsTowardScore: true,
            action: { onLogMeasurement?(type) }
        )
    }

    private func latestCompletedVisit(before date: Date) -> DoctorVisit? {
        store.completedDoctorVisits.first { visit in
            (visit.completedDate ?? visit.scheduledDate) < date
        }
    }

    private func readinessRow(title: String, detail: String, isReady: Bool, action: @escaping () -> Void) -> some View {
        readinessRow(title: title, detail: detail, status: isReady ? .ready : .needsAction, action: action)
    }

    private func readinessRow(title: String, detail: String, status: ReadinessStatus, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: status.iconName)
                    .font(.system(size: 14, weight: .regular))
                    .foregroundStyle(status.tint)
                    .frame(width: 24)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .appFont(.subheadline)
                        .foregroundStyle(EditorialPalette.textPrimary)
                    Text(detail)
                        .appFont(.caption)
                        .foregroundStyle(EditorialPalette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 6)
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func visitSupportingLine(_ visit: DoctorVisit) -> String {
        let time = visit.scheduledDate.formatted(date: .omitted, time: .shortened)
        let place = [Optional(visit.displayTitle), visit.hospital]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " · ")
        if place.isEmpty { return time }
        return "\(time) · \(place)"
    }

    private func recentMeasurementCount(days: Int) -> Int {
        let cutoff = Calendar.current.date(byAdding: .day, value: -days, to: Date()) ?? Date()
        return store.measurements.filter { $0.date >= cutoff }.count
    }

    private func recentMeasurementCount(type: MeasurementType, days: Int) -> Int {
        let cutoff = Calendar.current.date(byAdding: .day, value: -days, to: Date()) ?? Date()
        return store.measurements.filter { $0.type == type && $0.date >= cutoff }.count
    }

    private func recentSymptomCount(days: Int) -> Int {
        let cutoff = Calendar.current.date(byAdding: .day, value: -days, to: Date()) ?? Date()
        return store.symptomEntries.filter { $0.date >= cutoff }.count
    }

    private func preVisitPrepCard(priority: VisitPrepPriority) -> some View {
        let visit = store.nextDoctorVisit
        let tint = visit.map(visitPrepTint) ?? EditorialPalette.textSecondary
        return TintedCard(tint: tint) {
            VStack(alignment: .leading, spacing: EditorialSpacing.lg) {
                VStack(alignment: .leading, spacing: EditorialSpacing.sm) {
                    Text(visit.map { visitPrepTitle($0, priority: priority) } ?? NSLocalizedString("Plan your next appointment", comment: ""))
                        .appFont(priority == .pinned ? .displayTitle : .headline)
                        .fontWeight(priority == .pinned ? .bold : .semibold)
                        .foregroundStyle(priority == .pinned ? tint : EditorialPalette.textPrimary)
                    Text(visit.map { visitPrepSubtitle($0, priority: priority) } ?? NSLocalizedString("Add a visit date when you know your next appointment.", comment: ""))
                        .appFont(.caption)
                        .foregroundStyle(EditorialPalette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                HStack(spacing: 10) {
                    visitPrimaryActionButton(visit: visit, priority: priority)

                    if visit != nil {
                        Button {
                            showDoctorVisitForm = true
                        } label: {
                            Image(systemName: "calendar.badge.plus")
                                .frame(width: 42)
                        }
                        .buttonStyle(.bordered)
                        .accessibilityLabel(NSLocalizedString("Add Visit", comment: ""))
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func visitPrimaryActionButton(visit: DoctorVisit?, priority: VisitPrepPriority) -> some View {
        if priority == .pinned {
            Button {
                openVisitPrimaryAction(visit: visit)
            } label: {
                visitPrimaryActionLabel(visit: visit, priority: priority)
            }
            .buttonStyle(.borderedProminent)
        } else {
            Button {
                openVisitPrimaryAction(visit: visit)
            } label: {
                visitPrimaryActionLabel(visit: visit, priority: priority)
            }
            .buttonStyle(.bordered)
        }
    }

    private func visitPrimaryActionLabel(visit: DoctorVisit?, priority: VisitPrepPriority) -> some View {
        Label(visit == nil ? NSLocalizedString("Add Visit", comment: "") : primaryVisitActionTitle(for: priority),
              systemImage: visit == nil ? "plus" : "doc.text.magnifyingglass")
            .frame(maxWidth: .infinity)
    }

    private func openVisitPrimaryAction(visit: DoctorVisit?) {
        if visit == nil {
            showDoctorVisitForm = true
        } else {
            showVisitSnapshot = true
        }
    }

    private func visitIconName(for priority: VisitPrepPriority, visit: DoctorVisit?) -> String {
        guard let visit else { return "calendar.badge.plus" }
        guard let days = visit.daysUntil() else { return "calendar" }
        if days <= 0 { return "stethoscope" }
        return priority == .pinned ? "stethoscope" : "calendar.badge.clock"
    }

    private func primaryVisitActionTitle(for priority: VisitPrepPriority) -> String {
        priority == .pinned
            ? NSLocalizedString("Open Doctor Snapshot", comment: "")
            : NSLocalizedString("Review Snapshot", comment: "")
    }

    private func visitPrepTitle(_ visit: DoctorVisit, priority: VisitPrepPriority) -> String {
        guard let days = visit.daysUntil() else {
            return NSLocalizedString("Visit completed", comment: "")
        }
        if days == 0 { return NSLocalizedString("Appointment today", comment: "") }
        if days < 0 { return String(format: NSLocalizedString("%lld days overdue", comment: ""), abs(days)) }
        if priority == .secondary {
            return NSLocalizedString("Next appointment planned", comment: "")
        }
        if days > 0 {
            return String(format: NSLocalizedString("%lld days until appointment", comment: ""), days)
        }
        return NSLocalizedString("Next appointment planned", comment: "")
    }

    private func visitPrepSubtitle(_ visit: DoctorVisit, priority: VisitPrepPriority) -> String {
        let title = visit.displayTitle
        if priority == .secondary, let days = visit.daysUntil(), days > 3 {
            return String(format: NSLocalizedString("%@ · %@. Keep logging quietly until the visit gets close.", comment: ""), title, visit.scheduledDate.formatted(date: .abbreviated, time: .omitted))
        }
        if let reason = visit.reason, !reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "\(title) · \(reason)"
        }
        if let days = visit.daysUntil(), days <= 3 {
            return String(format: NSLocalizedString("%@ · prepare the doctor snapshot now.", comment: ""), title)
        }
        return String(format: NSLocalizedString("%@ · keep logging doses, symptoms, and measurements.", comment: ""), title)
    }

    private func visitPrepTint(_ visit: DoctorVisit) -> Color {
        guard let days = visit.daysUntil() else { return EditorialPalette.textSecondary }
        if days < 0 { return EditorialPalette.warning }
        return days <= 3 ? EditorialPalette.primary : EditorialPalette.textSecondary
    }

    private func inactivityWarningCard(daysSince: Int) -> some View {
        TintedCard(tint: AppColor.warning) {
            HStack(alignment: .center, spacing: 12) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 18, weight: .regular))
                    .foregroundStyle(AppColor.warning)
                VStack(alignment: .leading, spacing: 4) {
                    Text(NSLocalizedString("No recent activity", comment: ""))
                        .appFont(.headline)
                    Text(String(format: NSLocalizedString("No doses recorded in the last %lld days. Are reminders working?", comment: ""), daysSince))
                        .appFont(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 4)
            }
        }
    }

    private func todaySchedules() -> [MedSchedule] {
        let cal = Calendar.current
        let now = Date()
        var items: [MedSchedule] = []
        for med in store.medications where med.remindersEnabled && med.isAsNeeded != true {
            for t in med.timesOfDay {
                guard let h = t.hour, let m = t.minute else { continue }
                if let date = cal.date(bySettingHour: h, minute: m, second: 0, of: now) {
                    guard med.isDoseActive(on: date) else { continue }
                    let id = String(format: "%@_%02d:%02d", med.id.uuidString, h, m)
                    items.append(MedSchedule(id: id, med: med, time: date))
                }
            }
        }
        return items.sorted { $0.time < $1.time }
    }

    private func todayCompleteHero(takenCount: Int, skippedCount: Int, totalCount: Int, mode: HomeMode) -> some View {
        return Card {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 14) {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 36))
                        .foregroundStyle(AppColor.success)
                        .symbolRenderingMode(.hierarchical)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(NSLocalizedString("Today complete", comment: ""))
                            .appFont(.headline)
                        Text(todayCompleteSummary(taken: takenCount, skipped: skippedCount, total: totalCount, mode: mode))
                            .appFont(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                if let tomorrowText = tomorrowsFirstDoseText() {
                    Divider()
                    HStack(spacing: 6) {
                        Image(systemName: "sunrise")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                        Text(String(format: NSLocalizedString("Tomorrow: %@", comment: ""), tomorrowText))
                            .appFont(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    /// Unified time-sorted list for Today. Pending rows surface inline at the
    /// top; the first pending dose (if any) is emphasized with a left accent
    /// bar and inline Take/Skip/Snooze controls. Completed doses collapse to
    /// dimmed strike-through rows so the day reads as a single narrative.
    private func todayUnifiedList(
        schedules: [MedSchedule],
        statusCache: [String: TodayMedStatus],
        currentActionID: String?,
        nextUpcomingID: String?,
        collapsedLimit: Int
    ) -> some View {
        let visibleSchedules = showFullTodaySchedule || schedules.count <= collapsedLimit
            ? schedules
            : previewSchedules(
                schedules: schedules,
                statusCache: statusCache,
                currentActionID: currentActionID,
                nextUpcomingID: nextUpcomingID,
                limit: collapsedLimit
            )
        let isCollapsed = visibleSchedules.count < schedules.count

        return VStack(alignment: .leading, spacing: EditorialSpacing.md) {
            AppDivider()

            HStack(alignment: .firstTextBaseline) {
                Text(NSLocalizedString("Today schedule", comment: "Unified schedule section title"))
                    .appFont(.headline)
                    .foregroundStyle(EditorialPalette.textPrimary)
                Spacer()
                if schedules.count > collapsedLimit {
                    Text(String(format: NSLocalizedString("%lld total", comment: "Schedule total count"), schedules.count))
                        .appFont(.caption)
                        .foregroundStyle(EditorialPalette.textSecondary)
                }
            }

            VStack(spacing: 0) {
                ForEach(Array(visibleSchedules.enumerated()), id: \.element.id) { index, item in
                    let status = statusCache[item.id] ?? .none
                    let isCurrent = item.id == currentActionID
                    let isNextUpcoming = item.id == nextUpcomingID

                    if isCurrent {
                        emphasizedPendingRow(item: item, status: status)
                            .padding(.vertical, EditorialSpacing.sm)
                    } else {
                        compactUnifiedRow(item: item, status: status, isNextUpcoming: isNextUpcoming)
                            .padding(.vertical, EditorialSpacing.sm)
                    }

                    if index < visibleSchedules.count - 1 {
                        AppDivider()
                    }
                }
            }

            if schedules.count > collapsedLimit {
                AppDivider()

                Button {
                    Haptics.impact(.light)
                    withAnimation(.easeInOut(duration: 0.25)) {
                        showFullTodaySchedule.toggle()
                    }
                } label: {
                    HStack(spacing: EditorialSpacing.sm) {
                        Text(isCollapsed
                             ? NSLocalizedString("Show full schedule", comment: "")
                             : NSLocalizedString("Show key items only", comment: ""))
                            .appFont(.footnote)
                            .fontWeight(.medium)
                        Image(systemName: isCollapsed ? "chevron.down" : "chevron.up")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .foregroundStyle(AppColor.primary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, EditorialSpacing.xs)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func previewSchedules(
        schedules: [MedSchedule],
        statusCache: [String: TodayMedStatus],
        currentActionID: String?,
        nextUpcomingID: String?,
        limit: Int
    ) -> [MedSchedule] {
        var selectedIDs = Set<String>()

        func select(_ item: MedSchedule?) {
            guard let item, selectedIDs.count < limit else { return }
            selectedIDs.insert(item.id)
        }

        select(schedules.first { $0.id == currentActionID })
        for item in schedules where selectedIDs.count < limit {
            if case .overdue = statusCache[item.id] ?? .none {
                select(item)
            }
        }
        for item in schedules where selectedIDs.count < limit {
            switch statusCache[item.id] ?? .none {
            case .dueSoon, .snoozed:
                select(item)
            default:
                break
            }
        }
        select(schedules.first { $0.id == nextUpcomingID })
        for item in schedules where selectedIDs.count < limit {
            if !(statusCache[item.id] ?? .none).isFinal {
                select(item)
            }
        }
        for item in schedules where selectedIDs.count < limit {
            select(item)
        }

        // Keep the visible subset in the same chronological order as the full
        // schedule so expanding does not reshuffle rows under the user's finger.
        return schedules.filter { selectedIDs.contains($0.id) }
    }

    private func emphasizedPendingRow(item: MedSchedule, status: TodayMedStatus) -> some View {
        let accent = statusBadgeTint(for: status)
        return HStack(alignment: .top, spacing: 12) {
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(accent)
                .frame(width: 4)
                .frame(maxHeight: .infinity)

            VStack(alignment: .leading, spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    if let label = actionStatusLabel(for: status) {
                        Text(label.uppercased())
                            .font(.caption2)
                            .fontWeight(.semibold)
                            .foregroundStyle(accent)
                            .tracking(0.5)
                    }
                    HStack(alignment: .top, spacing: 12) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(item.med.name)
                                .appFont(.headline)
                                .fontWeight(.semibold)
                            Text("\(item.med.dose) · \(item.time.formatted(date: .omitted, time: .shortened))")
                                .appFont(.caption)
                                .foregroundStyle(.secondary)
                            if let fi = item.med.foodInstruction {
                                Label(fi.displayName, systemImage: "fork.knife")
                                    .appFont(.caption)
                                    .foregroundStyle(AppColor.textSecondary)
                            }
                        }
                        Spacer(minLength: 0)
                        if let path = item.med.imagePath, let ui = loadMedicationImage(path: path) {
                            Image(uiImage: ui)
                                .resizable()
                                .scaledToFill()
                                .frame(width: 52, height: 52)
                                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                                .accessibilityLabel(String(format: NSLocalizedString("%@ photo", comment: "Medication thumbnail accessibility"), item.med.name))
                        }
                    }
                }

                if let guidance = missedDoseRecovery(for: item, status: status) {
                    missedDoseRecoveryNotice(guidance)
                }

                VStack(spacing: 8) {
                    Button {
                        beginTakeFlow(for: item)
                    } label: {
                        Text(NSLocalizedString("Take", comment: ""))
                            .fontWeight(.semibold)
                            .frame(maxWidth: .infinity, minHeight: 48)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(AppColor.primary)

                    HStack(spacing: 8) {
                        Button {
                            snoozeDose(for: item)
                        } label: {
                            Text(snoozeButtonLabel(for: item))
                                .frame(maxWidth: .infinity, minHeight: 40)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .tint(snoozeButtonTint(for: item))

                        Button {
                            skipDose(for: item)
                        } label: {
                            Text(NSLocalizedString("Skip", comment: ""))
                                .frame(maxWidth: .infinity, minHeight: 40)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .tint(.secondary)
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }

    private func compactUnifiedRow(
        item: MedSchedule,
        status: TodayMedStatus,
        isNextUpcoming: Bool
    ) -> some View {
        HStack(alignment: .center, spacing: 12) {
            Button {
                if canLogDose(for: item, status: status) {
                    beginTakeFlow(for: item)
                }
            } label: {
                statusDot(for: status)
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
            .disabled(!canLogDose(for: item, status: status))

            VStack(alignment: .leading, spacing: 2) {
                Text(item.med.name)
                    .appFont(.body)
                    .strikethrough(status.isFinal, color: .secondary)
                    .foregroundStyle(status.isFinal ? .secondary : .primary)
                Text("\(item.med.dose) · \(item.time.formatted(date: .omitted, time: .shortened))")
                    .appFont(.caption)
                    .foregroundStyle(.secondary)
                if let guidance = missedDoseRecovery(for: item, status: status) {
                    Label(guidance.compactText, systemImage: guidance.icon)
                        .font(.caption2)
                        .foregroundStyle(guidance.tint)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer(minLength: 4)

            if status.isFinal {
                Text(status.displayText)
                    .appFont(.caption)
                    .foregroundStyle(.secondary)
            } else if isNextUpcoming {
                VStack(alignment: .trailing, spacing: 2) {
                    Text(timeUntilText(item.time))
                        .appFont(.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(AppColor.primary)
                        .monospacedDigit()
                    Text(NSLocalizedString("up next", comment: "Countdown label for the next medication in today's list"))
                        .appFont(.caption)
                        .foregroundStyle(.secondary)
                }
            } else if let label = actionStatusLabel(for: status) {
                AppBadge(
                    text: label,
                    tint: statusBadgeTint(for: status),
                    icon: statusBadgeIcon(for: status)
                )
            }
        }
        .opacity(status.isFinal ? 0.55 : 1.0)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(item.med.name), \(item.med.dose), \(item.time.formatted(date: .omitted, time: .shortened)), \(status.displayText)")
    }

    private func missedDoseRecovery(for item: MedSchedule, status: TodayMedStatus) -> MissedDoseRecoveryGuidance? {
        guard case .overdue = status else { return nil }
        let comps = Calendar.current.dateComponents([.hour, .minute], from: item.time)
        let result = MedicationRules.checkMakeupDose(
            medication: item.med,
            missedTime: comps,
            now: Date()
        )

        switch result {
        case .canTakeLate:
            return MissedDoseRecoveryGuidance(
                title: NSLocalizedString("Recovery window open", comment: "Missed dose recovery title"),
                message: NSLocalizedString("If you are sure this dose was missed, you can log it now. Do not take extra doses beyond the schedule unless your clinician told you to.", comment: "Missed dose recovery guidance"),
                compactText: NSLocalizedString("Can log late dose", comment: "Compact missed dose recovery guidance"),
                icon: "arrow.uturn.backward.circle.fill",
                tint: AppColor.warning
            )
        case .tooCloseToNext(let next):
            let nextText = next.formatted(date: .omitted, time: .shortened)
            return MissedDoseRecoveryGuidance(
                title: NSLocalizedString("Too close to next dose", comment: "Missed dose recovery title"),
                message: String(format: NSLocalizedString("Next scheduled dose is at %@. Avoid doubling up; skip this missed dose unless your clinician told you otherwise.", comment: "Missed dose recovery guidance"), nextText),
                compactText: NSLocalizedString("Near next dose; avoid doubling up", comment: "Compact missed dose recovery guidance"),
                icon: "exclamationmark.triangle.fill",
                tint: AppColor.warning
            )
        case .noNextDose:
            return MissedDoseRecoveryGuidance(
                title: NSLocalizedString("Check before logging", comment: "Missed dose recovery title"),
                message: NSLocalizedString("No next scheduled dose was found. Log this only if you actually took it.", comment: "Missed dose recovery guidance"),
                compactText: NSLocalizedString("Confirm before logging", comment: "Compact missed dose recovery guidance"),
                icon: "questionmark.circle.fill",
                tint: AppColor.textSecondary
            )
        }
    }

    private func missedDoseRecoveryNotice(_ guidance: MissedDoseRecoveryGuidance) -> some View {
        InsetPanel(tint: guidance.tint) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: guidance.icon)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(guidance.tint)
                    .frame(width: 24)

                VStack(alignment: .leading, spacing: 3) {
                    Text(guidance.title)
                        .appFont(.subheadline)
                        .fontWeight(.semibold)
                    Text(guidance.message)
                        .appFont(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private func asNeededInlineSection(medications: [Medication]) -> some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text(NSLocalizedString("As Needed", comment: ""))
                        .appFont(.headline)
                }

                let visible = showAllPRN ? medications : Array(medications.prefix(3))
                ForEach(visible) { med in
                    VStack(spacing: 0) {
                        prnMedRow(med: med)
                        if med.id != visible.last?.id {
                            Divider()
                        }
                    }
                    .transition(.opacity)
                }

                if medications.count > 3 {
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) { showAllPRN.toggle() }
                    } label: {
                        HStack(spacing: 4) {
                            Text(showAllPRN
                                 ? NSLocalizedString("Show Less", comment: "")
                                 : String(format: NSLocalizedString("Show All %lld", comment: ""), medications.count))
                                .appFont(.footnote)
                                .fontWeight(.medium)
                            Image(systemName: showAllPRN ? "chevron.up" : "chevron.down")
                                .font(.system(size: 10, weight: .semibold))
                        }
                        .foregroundStyle(AppColor.primary)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 2)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }


    private func tomorrowsFirstDoseText() -> String? {
        let cal = Calendar.current
        let tomorrow = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: Date()))
        guard let tomorrow else { return nil }
        let upcoming = store.medications
            .filter { $0.isAsNeeded != true && $0.remindersEnabled }
            .flatMap { med in
                med.timesOfDay.compactMap { comps -> (Medication, Date)? in
                    guard let hour = comps.hour,
                          let minute = comps.minute,
                          let date = cal.date(bySettingHour: hour, minute: minute, second: 0, of: tomorrow),
                          med.isDoseActive(on: date) else { return nil }
                    return (med, date)
                }
            }
            .sorted { $0.1 < $1.1 }
            .first

        guard let upcoming else { return nil }
        return "\(upcoming.0.name) • \(upcoming.1.formatted(date: .omitted, time: .shortened))"
    }

    private func skipDose(for item: MedSchedule) {
        let comps = Calendar.current.dateComponents([.hour, .minute], from: item.time)
        if Calendar.current.isDateInToday(item.time) {
            NotificationManager.shared.suppressToday(for: item.med.id, timeComponents: comps)
        }
        store.upsertIntake(
            medicationID: item.med.id,
            status: .skipped,
            scheduleTime: comps,
            at: item.time,
            scheduledDate: item.time
        )
        NotificationManager.shared.cancelDoseNotifications(for: item.med.id, timeComponents: comps, scheduledDate: item.time, now: item.time)
        store.syncNotifications()
        Haptics.notification(.warning)
    }

    private func snoozeDose(for item: MedSchedule) {
        let comps = Calendar.current.dateComponents([.hour, .minute], from: item.time)
        let count = NotificationManager.shared.snoozeCount(for: item.med.id, scheduleTime: comps)
        let result = MedicationRules.nextSnooze(for: item.med.id, currentSnoozeCount: count)

        switch result {
        case .snooze(let minutes):
            NotificationManager.shared.cancelFollowUps(for: item.med.id, timeComponents: comps, scheduledDate: item.time)
            NotificationManager.shared.incrementSnoozeCount(for: item.med.id, scheduleTime: comps)
            NotificationManager.shared.scheduleSnooze(for: item.med, minutes: minutes, scheduleTime: comps, scheduledDate: item.time)
            if Calendar.current.isDateInToday(item.time) {
                NotificationManager.shared.suppressToday(for: item.med.id, timeComponents: comps)
            }
            store.upsertIntake(
                medicationID: item.med.id,
                status: .snoozed,
                scheduleTime: comps,
                at: item.time,
                scheduledDate: item.time
            )
            NotificationManager.shared.updateBadge(store: store)
            Haptics.impact(.soft)
        case .exhausted:
            skipDose(for: item)
        }
    }


    private func reminderRepairCard() -> some View {
        let issueText: String = {
            if notificationStatus == .denied {
                return NSLocalizedString("System notifications are blocked. Scheduled medication reminders cannot fire.", comment: "")
            }
            if let first = untimedScheduledMeds.first {
                return String(format: NSLocalizedString("%@ needs a reminder time before it can notify you.", comment: ""), first.name)
            }
            if disabledReminderMeds.count == 1, let first = disabledReminderMeds.first {
                return String(format: NSLocalizedString("%@ has reminder times, but reminders are turned off.", comment: ""), first.name)
            }
            return String(format: NSLocalizedString("%lld medications have reminders turned off.", comment: ""), disabledReminderMeds.count)
        }()

        let actionTitle: String = {
            if notificationStatus == .denied {
                return NSLocalizedString("Open Settings", comment: "")
            }
            if !untimedScheduledMeds.isEmpty {
                return NSLocalizedString("Set Time", comment: "")
            }
            return NSLocalizedString("Turn On", comment: "")
        }()

        return TintedCard(tint: AppColor.warning) {
            HStack(alignment: .center, spacing: 12) {
                Image(systemName: "bell.badge")
                    .font(.system(size: 18, weight: .regular))
                    .foregroundStyle(AppColor.warning)
                    .frame(width: 24, height: 24)

                VStack(alignment: .leading, spacing: 4) {
                    Text(NSLocalizedString("Reminder Setup Needs Attention", comment: ""))
                        .appFont(.headline)
                    Text(issueText)
                        .appFont(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 8)

                Button(actionTitle) {
                    handleReminderRepair()
                }
                .buttonStyle(.borderedProminent)
                .tint(AppColor.warning)
                .controlSize(.small)
            }
        }
    }

    private func latestTodayLogMap(now: Date = Date()) -> [ScheduleLookupKey: IntakeLog] {
        let cal = Calendar.current
        let start = cal.startOfDay(for: now)
        let end = cal.date(byAdding: .day, value: 1, to: start)!
        let todaysLogs = store.intakeLogs
            .filter { $0.date >= start && $0.date < end }
            .sorted { $0.date > $1.date }
        var result: [ScheduleLookupKey: IntakeLog] = [:]
        for log in todaysLogs {
            let key = ScheduleLookupKey(medicationID: log.medicationID, scheduleKey: log.scheduleKey)
            if result[key] == nil {
                result[key] = log
            }
        }
        return result
    }

    private func status(for med: Medication, at time: Date, lookup: [ScheduleLookupKey: IntakeLog]) -> TodayMedStatus {
        let cal = Calendar.current
        let comps = cal.dateComponents([.hour, .minute], from: time)
        let key = String(format: "%02d:%02d", comps.hour ?? 0, comps.minute ?? 0)
        let directKey = ScheduleLookupKey(medicationID: med.id, scheduleKey: key)
        let allowNil = med.timesOfDay.count <= 1
        let fallbackKey = allowNil ? ScheduleLookupKey(medicationID: med.id, scheduleKey: nil) : nil
        let log = lookup[directKey] ?? (fallbackKey.flatMap { lookup[$0] })
        guard let entry = log else { return .none }
        switch entry.status {
        case .taken:
            return .taken(entry.date)
        case .skipped:
            return .skipped(entry.date)
        case .snoozed:
            return .snoozed(entry.date)
        }
    }

    private func actionStatusLabel(for status: TodayMedStatus) -> String? {
        switch status {
        case .overdue:
            return NSLocalizedString("Overdue", comment: "")
        case .dueSoon:
            return NSLocalizedString("Due now", comment: "")
        case .snoozed:
            return NSLocalizedString("Snoozed", comment: "")
        default:
            return nil
        }
    }

    private func statusBadgeTint(for status: TodayMedStatus) -> Color {
        switch status {
        case .overdue:
            return AppColor.warning
        case .dueSoon:
            return AppColor.warning
        case .snoozed:
            return AppColor.primary
        default:
            return AppColor.textSecondary
        }
    }

    private func statusBadgeIcon(for status: TodayMedStatus) -> String {
        switch status {
        case .overdue:
            return "exclamationmark.circle.fill"
        case .dueSoon:
            return "clock.fill"
        case .snoozed:
            return "zzz"
        case .none:
            return "clock"
        case .taken:
            return "checkmark.circle.fill"
        case .skipped:
            return "xmark.circle.fill"
        }
    }

    private func todayCompleteSummary(taken: Int, skipped: Int, total: Int, mode: HomeMode) -> String {
        if case .lightPrep(_, let days) = mode {
            return String(format: NSLocalizedString("Today complete. Appointment in %lld days; your records are getting ready.", comment: "Complete summary with light visit prep"), days)
        }
        if case .activePrep(_, let days) = mode {
            if days < 0 {
                return NSLocalizedString("Today complete. This appointment is overdue; update it after the visit.", comment: "Complete summary with overdue visit")
            }
            return String(format: NSLocalizedString("Today complete. Appointment in %lld days; review the doctor snapshot next.", comment: "Complete summary with active visit prep"), days)
        }
        if case .visitDay = mode {
            return NSLocalizedString("Today complete. Keep the doctor snapshot ready for the appointment.", comment: "Complete summary on visit day")
        }
        if skipped > 0 {
            return String(format: NSLocalizedString("%lld taken, %lld skipped out of %lld", comment: "complete summary"), taken, skipped, total)
        }
        return String(format: NSLocalizedString("All %lld doses taken", comment: "complete summary all taken"), total)
    }

    private func beginTakeFlow(for item: MedSchedule) {
        let comps = Calendar.current.dateComponents([.hour, .minute], from: item.time)
        let dupCheck = MedicationRules.checkDuplicateTaken(
            medicationID: item.med.id,
            scheduleTime: comps,
            intakeLogs: store.intakeLogs
        )
        if case .blocked(let mins) = dupCheck {
            pendingNoteItem = item
            duplicateAlertMinutes = mins
            showDuplicateAlert = true
            Haptics.notification(.warning)
        } else {
            pendingNoteItem = item
            commitTaken(note: nil)
        }
    }

    private func prnMedRow(med: Medication) -> some View {
        let cal = Calendar.current
        let dayStart = cal.startOfDay(for: Date())
        let dayEnd = cal.date(byAdding: .day, value: 1, to: dayStart)!
        let todayCount = store.intakeLogs.filter {
            $0.medicationID == med.id && $0.date >= dayStart && $0.date < dayEnd && $0.status == .taken
        }.count

        return HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(med.name)
                    .appFont(.body)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                Text(med.dose)
                    .appFont(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
            .layoutPriority(1)

            Spacer(minLength: 4)

            if todayCount > 0 {
                Text(String(format: NSLocalizedString("Taken %lld×", comment: ""), todayCount))
                    .appFont(.caption)
                    .foregroundStyle(AppColor.success)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                    .fixedSize()
            }

            Button {
                let now = Date()
                let comps = cal.dateComponents([.hour, .minute], from: now)
                store.recordTakenDose(
                    medicationID: med.id,
                    scheduleTime: comps,
                    scheduledDate: now,
                    scheduleKeyOverride: "prn_\(now.timeIntervalSince1970)"
                )
                Haptics.success()
            } label: {
                Text(NSLocalizedString("Take Now", comment: ""))
                    .appFont(.caption)
                    .fontWeight(.semibold)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
            }
            .buttonStyle(.borderedProminent)
            .tint(AppColor.primary)
            .controlSize(.small)
            .fixedSize()
        }
        .contentShape(Rectangle())
    }



    private func commitTaken(note: String?) {
        guard let item = pendingNoteItem else { return }
        let comps = Calendar.current.dateComponents([.hour, .minute], from: item.time)
        store.recordTakenDose(
            medicationID: item.med.id,
            scheduleTime: comps,
            scheduledDate: item.time,
            note: note
        )
        NotificationManager.shared.suppressToday(for: item.med.id, timeComponents: comps)
        NotificationManager.shared.cancelDoseNotifications(for: item.med.id, timeComponents: comps, scheduledDate: item.time, now: item.time)
        store.syncNotifications()
        Haptics.success()
        takenMedName = item.med.name
        withAnimation(.easeInOut(duration: 0.25)) { showTakenConfirmation = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.3) {
            withAnimation(.easeInOut(duration: 0.3)) { showTakenConfirmation = false }
        }
        pendingNoteItem = nil
    }

    private func handleReminderRepair() {
        if notificationStatus == .denied {
            if let url = URL(string: UIApplication.openSettingsURLString) {
                UIApplication.shared.open(url)
            }
            return
        }

        if let med = untimedScheduledMeds.first {
            reminderFixTarget = med
            return
        }

        if !disabledReminderMeds.isEmpty {
            Task {
                let granted = await NotificationManager.shared.ensureAuthorization()
                await MainActor.run {
                    guard granted else {
                        refreshNotificationStatus()
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                        return
                    }
                    for med in disabledReminderMeds {
                        var updated = med
                        updated.remindersEnabled = true
                        store.updateMedication(updated)
                    }
                    store.syncNotifications()
                    refreshNotificationStatus()
                    Haptics.success()
                }
            }
        }
    }

    private func refreshNotificationStatus() {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            DispatchQueue.main.async {
                notificationStatus = settings.authorizationStatus
            }
        }
    }

    @ViewBuilder
    private func statusDot(for status: TodayMedStatus) -> some View {
        switch status {
        case .taken:
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(AppColor.success)
        case .skipped:
            Image(systemName: "xmark.circle")
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(AppColor.textSecondary)
        case .snoozed:
            Image(systemName: "zzz")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(AppColor.primary)
                .frame(width: 24)
        case .overdue:
            Image(systemName: "exclamationmark.circle")
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(AppColor.warning)
        case .dueSoon:
            Image(systemName: "clock")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(AppColor.warning)
                .frame(width: 24)
        case .none:
            Image(systemName: "circle")
                .font(.system(size: 24, weight: .regular))
                .foregroundStyle(.secondary.opacity(0.5))
        }
    }

    private func canLogDose(for item: MedSchedule, status: TodayMedStatus) -> Bool {
        guard !status.isFinal else { return false }
        switch status {
        case .dueSoon, .overdue, .snoozed:
            return true
        case .none, .taken, .skipped:
            return false
        }
    }

    private var safetySummary: MedicationRules.DailySafetySummary {
        MedicationRules.dailySafetyCheck(
            medications: store.medications,
            intakeLogs: store.intakeLogs,
            consecutiveMissedDaysProvider: { store.consecutiveMissedDays(for: $0) }
        )
    }

    @ViewBuilder
    private func safetyNoticeCard(summary: MedicationRules.DailySafetySummary) -> some View {
        let items = summary.missEscalations + summary.timingConflicts
        let tint: Color = AppColor.warning
        let title = summary.missEscalations.isEmpty
            ? NSLocalizedString("Schedule overlap", comment: "")
            : NSLocalizedString("Needs attention", comment: "")

        TintedCard(tint: tint) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 18, weight: .regular))
                    .foregroundStyle(tint)
                    .frame(width: 24, height: 24)

                VStack(alignment: .leading, spacing: 6) {
                    Text(title).appFont(.headline)
                    ForEach(items, id: \.self) { item in
                        Text("• \(item)")
                            .appFont(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 0)
            }
        }
    }

    private func snoozeButtonLabel(for item: MedSchedule) -> String {
        let comps = Calendar.current.dateComponents([.hour, .minute], from: item.time)
        let count = NotificationManager.shared.snoozeCount(for: item.med.id, scheduleTime: comps)
        let result = MedicationRules.nextSnooze(for: item.med.id, currentSnoozeCount: count)
        switch result {
        case .snooze(let minutes):
            return String(format: NSLocalizedString("%lld min", comment: "Snooze button label"), minutes)
        case .exhausted:
            return NSLocalizedString("Skip", comment: "Snooze exhausted")
        }
    }

    private func timeUntilText(_ target: Date) -> String {
        let interval = target.timeIntervalSince(Date())
        guard interval > 0 else { return NSLocalizedString("now", comment: "") }
        let hours = Int(interval) / 3600
        let minutes = (Int(interval) % 3600) / 60
        if hours > 0 {
            return String(format: NSLocalizedString("%lldh %lldm", comment: ""), hours, minutes)
        }
        return String(format: NSLocalizedString("%lldm", comment: ""), max(minutes, 1))
    }

    private func snoozeButtonTint(for item: MedSchedule) -> Color {
        let comps = Calendar.current.dateComponents([.hour, .minute], from: item.time)
        let count = NotificationManager.shared.snoozeCount(for: item.med.id, scheduleTime: comps)
        let result = MedicationRules.nextSnooze(for: item.med.id, currentSnoozeCount: count)
        if result.isExhausted { return AppColor.warning }
        return count >= 1 ? AppColor.warning : Color(.secondaryLabel)
    }

}

#Preview {
    DashboardView().environmentObject(DataStore())
}
