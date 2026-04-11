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

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    TintedCard(tint: .blue) {
                        VStack(alignment: .leading, spacing: 16) {
                            HStack(alignment: .top, spacing: 12) {
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(NSLocalizedString("Insights", comment: ""))
                                        .appFont(.largeTitle)
                                        .fontWeight(.bold)
                                    Text(NSLocalizedString("Review adherence, measurements, and reminder setup without interrupting Today.", comment: ""))
                                        .appFont(.footnote)
                                        .foregroundStyle(.secondary)
                                }

                                Spacer(minLength: 12)

                                AppBadge(
                                    text: "\(max(reminderGapCount, 0))",
                                    tint: reminderGapCount > 0 ? .orange : .green,
                                    icon: "bell.badge"
                                )
                            }

                            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                                metricPanel(
                                    value: String(format: "%.0f%%", adherence7 * 100),
                                    label: NSLocalizedString("7-day adherence", comment: ""),
                                    tint: adherence7 >= 0.8 ? .green : adherence7 >= 0.5 ? .orange : .red
                                )
                                metricPanel(
                                    value: String(format: "%.0f%%", adherence30 * 100),
                                    label: NSLocalizedString("30-day adherence", comment: ""),
                                    tint: adherence30 >= 0.8 ? .green : adherence30 >= 0.5 ? .orange : .red
                                )
                                metricPanel(
                                    value: "\(scheduledMedicationCount)",
                                    label: NSLocalizedString("Scheduled meds", comment: ""),
                                    tint: .blue
                                )
                                metricPanel(
                                    value: "\(max(reminderGapCount, 0))",
                                    label: NSLocalizedString("Reminder gaps", comment: ""),
                                    tint: reminderGapCount > 0 ? .orange : .green
                                )
                            }
                        }
                    }

                    if let latest = store.measurements.first {
                        Card {
                            VStack(alignment: .leading, spacing: 12) {
                                HStack {
                                    Text(NSLocalizedString("Latest Measurement", comment: ""))
                                        .appFont(.headline)
                                    Spacer()
                                    Button(NSLocalizedString("Log", comment: "")) {
                                        showAddMeasurement = true
                                    }
                                    .buttonStyle(.bordered)
                                    .controlSize(.small)
                                }

                                InsetPanel(tint: latest.type.tint) {
                                    latestMeasurementRow(latest)
                                }
                            }
                        }
                    } else {
                        Card {
                            EmptyStateView(
                                systemImage: "waveform.path.ecg",
                                title: NSLocalizedString("No measurements yet", comment: ""),
                                subtitle: NSLocalizedString("Log blood pressure, glucose, weight, or heart rate to unlock trend review.", comment: ""),
                                actionTitle: NSLocalizedString("Log Measurement", comment: ""),
                                action: { showAddMeasurement = true }
                            )
                        }
                    }

                    Card {
                        VStack(alignment: .leading, spacing: 12) {
                            Text(NSLocalizedString("Review Tools", comment: ""))
                                .appFont(.headline)

                            NavigationLink {
                                EnhancedTrendsView()
                                    .environmentObject(store)
                            } label: {
                                insightsLinkRow(
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
                                insightsLinkRow(
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
                                insightsLinkRow(
                                    title: NSLocalizedString("Reminder Diagnostics", comment: ""),
                                    subtitle: NSLocalizedString("Check permission, schedule times, and reminder reliability.", comment: ""),
                                    systemImage: "bell.badge.fill",
                                    tint: reminderGapCount > 0 ? .orange : .green
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
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

    private func refreshNotificationStatus() {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            DispatchQueue.main.async {
                notificationStatus = settings.authorizationStatus
            }
        }
    }

    private func metricPanel(value: String, label: String, tint: Color) -> some View {
        InsetPanel(tint: tint) {
            VStack(alignment: .leading, spacing: 6) {
                Text(value)
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                    .foregroundStyle(tint)
                    .monospacedDigit()
                Text(label)
                    .appFont(.footnote)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, minHeight: 74, alignment: .topLeading)
        }
    }

    private func insightsLinkRow(title: String, subtitle: String, systemImage: String, tint: Color) -> some View {
        InsetPanel(tint: tint) {
            HStack(spacing: 12) {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(tint.opacity(0.14))
                    .frame(width: 40, height: 40)
                    .overlay(
                        Image(systemName: systemImage)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(tint)
                    )
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .appFont(.subheadline)
                        .foregroundStyle(.primary)
                    Text(subtitle)
                        .appFont(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private func latestMeasurementRow(_ m: Measurement) -> some View {
        HStack(spacing: 10) {
            Circle()
                .fill(m.type.tint)
                .frame(width: 8, height: 8)
            Text(m.type.rawValue)
                .appFont(.subheadline)
            Spacer()
            Group {
                if m.type == .bloodPressure, let dia = m.diastolic {
                    Text("\(Int(m.value))/\(Int(dia)) \(m.type.unit)")
                } else if m.type == .bloodGlucose {
                    let v = UnitPreferences.mgdlToPreferred(m.value)
                    let formatted = UnitPreferences.glucoseUnit == .mgdL ? String(format: "%.0f", v) : String(format: "%.1f", v)
                    Text("\(formatted) \(UnitPreferences.glucoseUnit.rawValue)")
                } else {
                    Text("\(String(format: "%.1f", m.value)) \(m.type.unit)")
                }
            }
            .appFont(.subheadline)
            .fontWeight(.medium)
        }
    }
}
