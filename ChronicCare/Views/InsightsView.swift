import SwiftUI
import UserNotifications

struct InsightsView: View {
    @EnvironmentObject var store: DataStore
    @State private var showAddMeasurement = false
    @State private var notificationStatus: UNAuthorizationStatus = .notDetermined

    private var adherence7: Double {
        store.adherencePercent(days: 7)
    }

    private var adherence30: Double {
        store.adherencePercent(days: 30)
    }

    private var scheduledMedicationCount: Int {
        store.medications.filter { $0.isAsNeeded != true }.count
    }

    private var reminderGapCount: Int {
        store.medications.filter {
            $0.isAsNeeded != true && ($0.timesOfDay.isEmpty || !$0.remindersEnabled)
        }.count + (notificationStatus == .denied ? 1 : 0)
    }

    private var reminderStateText: String {
        reminderGapCount > 0
            ? NSLocalizedString("Needs Review", comment: "")
            : NSLocalizedString("Healthy", comment: "")
    }

    private var reminderStateTint: Color {
        reminderGapCount > 0 ? .orange : .green
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    overviewHeader
                    snapshotSection
                    latestMeasurementSection
                    toolsSection
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 28)
            }
            .navigationTitle(NSLocalizedString("Insights", comment: ""))
            .navigationBarTitleDisplayMode(.large)
            .sheet(isPresented: $showAddMeasurement) {
                AddMeasurementView { measurement in
                    store.addMeasurement(measurement)
                    Haptics.success()
                }
                .presentationDetents([.medium, .large])
            }
            .onAppear(perform: refreshNotificationStatus)
        }
    }

    private var overviewHeader: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(NSLocalizedString("Review Snapshot", comment: ""))
                        .appFont(.title)
                        .fontWeight(.bold)
                    Text(NSLocalizedString("See adherence, measurements, and reminder health in one place.", comment: ""))
                        .appFont(.footnote)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 12)

                AppBadge(
                    text: reminderStateText,
                    tint: reminderStateTint,
                    icon: reminderGapCount > 0 ? "exclamationmark.circle.fill" : "checkmark.circle.fill"
                )
            }

            if reminderGapCount > 0 {
                Text(String(format: NSLocalizedString("%lld reminder issues still need attention.", comment: ""), reminderGapCount))
                    .appFont(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                Text(NSLocalizedString("Your scheduled medications currently look covered.", comment: ""))
                    .appFont(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var snapshotSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionLabel(
                title: NSLocalizedString("Adherence & Coverage", comment: ""),
                subtitle: NSLocalizedString("Use these numbers to spot missed doses and reminder gaps quickly.", comment: "")
            )

            LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                snapshotTile(
                    value: String(format: "%.0f%%", adherence7 * 100),
                    label: NSLocalizedString("7-day adherence", comment: ""),
                    tint: adherence7 >= 0.8 ? .green : adherence7 >= 0.5 ? .orange : .red
                )
                snapshotTile(
                    value: String(format: "%.0f%%", adherence30 * 100),
                    label: NSLocalizedString("30-day adherence", comment: ""),
                    tint: adherence30 >= 0.8 ? .green : adherence30 >= 0.5 ? .orange : .red
                )
                snapshotTile(
                    value: "\(scheduledMedicationCount)",
                    label: NSLocalizedString("Scheduled meds", comment: ""),
                    tint: .blue
                )
                snapshotTile(
                    value: "\(max(reminderGapCount, 0))",
                    label: NSLocalizedString("Reminder gaps", comment: ""),
                    tint: reminderStateTint
                )
            }
        }
    }

    @ViewBuilder
    private var latestMeasurementSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                sectionLabel(
                    title: NSLocalizedString("Latest Measurement", comment: ""),
                    subtitle: NSLocalizedString("Keep the most recent reading visible so trends always have context.", comment: "")
                )

                Spacer(minLength: 12)

                Button {
                    showAddMeasurement = true
                } label: {
                    Label(NSLocalizedString("Log", comment: ""), systemImage: "plus.circle.fill")
                        .fontWeight(.semibold)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }

            if let latest = store.measurements.first {
                InsetPanel(tint: latest.type.tint) {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 10) {
                            Circle()
                                .fill(latest.type.tint)
                                .frame(width: 8, height: 8)
                            Text(latest.type.displayName)
                                .appFont(.subheadline)
                                .fontWeight(.semibold)
                            Spacer()
                            measurementValueText(latest)
                        }

                        HStack(spacing: 10) {
                            Text(latest.date.formatted(date: .abbreviated, time: .shortened))
                                .appFont(.footnote)
                                .foregroundStyle(.secondary)

                            if let note = latest.note, !note.isEmpty {
                                Text(note)
                                    .appFont(.footnote)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                            }
                        }
                    }
                }
            } else {
                InsetPanel {
                    EmptyStateView(
                        systemImage: "waveform.path.ecg",
                        title: NSLocalizedString("No measurements yet", comment: ""),
                        subtitle: NSLocalizedString("Log blood pressure, glucose, weight, or heart rate to unlock trend review.", comment: ""),
                        actionTitle: NSLocalizedString("Log Measurement", comment: ""),
                        action: { showAddMeasurement = true }
                    )
                }
            }
        }
    }

    private var toolsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionLabel(
                title: NSLocalizedString("Review Tools", comment: ""),
                subtitle: NSLocalizedString("Open the detailed views only when you want to inspect history more closely.", comment: "")
            )

            VStack(spacing: 10) {
                NavigationLink {
                    EnhancedTrendsView()
                        .environmentObject(store)
                } label: {
                    toolRow(
                        title: NSLocalizedString("Trends", comment: ""),
                        subtitle: NSLocalizedString("Review blood pressure, glucose, weight, and heart rate over time.", comment: ""),
                        systemImage: "chart.line.uptrend.xyaxis",
                        tint: .blue
                    )
                }
                .buttonStyle(.plain)

                NavigationLink {
                    AdherenceCalendarView()
                } label: {
                    toolRow(
                        title: NSLocalizedString("Adherence Calendar", comment: ""),
                        subtitle: NSLocalizedString("See which days were taken, skipped, or missed.", comment: ""),
                        systemImage: "calendar",
                        tint: .green
                    )
                }
                .buttonStyle(.plain)

                NavigationLink {
                    ReminderDiagnosticsView(
                        notificationStatus: notificationStatus,
                        scheduledWithoutRemindersCount: store.medications.filter { $0.isAsNeeded != true && !$0.timesOfDay.isEmpty && !$0.remindersEnabled }.count,
                        untimedScheduledCount: store.medications.filter { $0.isAsNeeded != true && $0.timesOfDay.isEmpty }.count
                    )
                    .environmentObject(store)
                } label: {
                    toolRow(
                        title: NSLocalizedString("Reminder Diagnostics", comment: ""),
                        subtitle: NSLocalizedString("Check permission, schedule times, and reminder reliability.", comment: ""),
                        systemImage: "bell.badge.fill",
                        tint: reminderStateTint,
                        badgeText: reminderGapCount > 0 ? "\(reminderGapCount)" : nil
                    )
                }
                .buttonStyle(.plain)
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

    private func sectionLabel(title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .appFont(.headline)
            Text(subtitle)
                .appFont(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func snapshotTile(value: String, label: String, tint: Color) -> some View {
        InsetPanel(tint: tint) {
            VStack(alignment: .leading, spacing: 6) {
                Text(value)
                    .appFont(.largeTitle)
                    .fontWeight(.bold)
                    .foregroundStyle(tint)
                    .monospacedDigit()
                    .minimumScaleFactor(0.8)
                Text(label)
                    .appFont(.footnote)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, minHeight: 82, alignment: .topLeading)
        }
    }

    private func toolRow(
        title: String,
        subtitle: String,
        systemImage: String,
        tint: Color,
        badgeText: String? = nil
    ) -> some View {
        InsetPanel {
            HStack(alignment: .center, spacing: 12) {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(tint.opacity(0.14))
                    .frame(width: 42, height: 42)
                    .overlay(
                        Image(systemName: systemImage)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(tint)
                    )

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .appFont(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundStyle(.primary)
                    Text(subtitle)
                        .appFont(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()

                if let badgeText {
                    AppBadge(text: badgeText, tint: tint)
                }

                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private func measurementValueText(_ measurement: Measurement) -> some View {
        Group {
            if measurement.type == .bloodPressure, let dia = measurement.diastolic {
                Text("\(Int(measurement.value))/\(Int(dia)) \(measurement.type.unit)")
            } else if measurement.type == .bloodGlucose {
                let value = UnitPreferences.mgdlToPreferred(measurement.value)
                let formatted = UnitPreferences.glucoseUnit == .mgdL
                    ? String(format: "%.0f", value)
                    : String(format: "%.1f", value)
                Text("\(formatted) \(UnitPreferences.glucoseUnit.rawValue)")
            } else {
                Text("\(String(format: "%.1f", measurement.value)) \(measurement.type.unit)")
            }
        }
        .appFont(.subheadline)
        .fontWeight(.medium)
    }
}
