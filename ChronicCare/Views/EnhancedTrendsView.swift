import SwiftUI
import Charts

struct EnhancedTrendsView: View {
    @EnvironmentObject var store: DataStore

    @State private var selectedType: MeasurementType = .bloodPressure
    @State private var rangeDays: Int = 30
    @State private var selectedDataPoint: Measurement?
    @State private var editingMeasurement: Measurement?
    @State private var deleteTarget: Measurement?
    @State private var aiInsights: String?
    @State private var isLoadingInsights = false
    @State private var showAIDataDisclosure = false
    @AppStorage("units.glucose") private var glucoseUnitRaw: String = GlucoseUnit.mgdL.rawValue

    private var filtered: [Measurement] {
        let now = Date()
        let start = Calendar.current.date(byAdding: .day, value: -rangeDays, to: Date())!
        return store.measurements
            .filter { $0.type == selectedType && $0.date >= start && $0.date <= now }
            .sorted(by: { $0.date < $1.date })
    }

    private var sevenDaySlice: [Measurement] {
        let now = Date()
        let start = Calendar.current.date(byAdding: .day, value: -7, to: Date())!
        return store.measurements
            .filter { $0.type == selectedType && $0.date >= start && $0.date <= now }
            .sorted(by: { $0.date < $1.date })
    }

    private var deleteConfirmationBinding: Binding<Bool> {
        Binding(
            get: { deleteTarget != nil },
            set: { if !$0 { deleteTarget = nil } }
        )
    }

    private struct BPPoint: Identifiable {
        let id: UUID
        let date: Date
        let systolic: Double
        let diastolic: Double?
    }

    /// Returns every individual blood pressure measurement as a chart point,
    /// preserving all readings even when multiple are recorded on the same day.
    private var bpPoints: [BPPoint] {
        guard selectedType == .bloodPressure else { return [] }
        return filtered.map { m in
            BPPoint(id: m.id, date: m.date, systolic: m.value, diastolic: m.diastolic)
        }
    }

    private var xAxisValues: [Date] {
        let cal = Calendar.current
        let end = cal.startOfDay(for: Date())
        let start = cal.date(byAdding: .day, value: -rangeDays, to: end)!
        let step = rangeDays <= 7 ? 2 : (rangeDays <= 30 ? 7 : 30)
        var arr: [Date] = []
        var d = start
        while d <= end {
            arr.append(d)
            d = cal.date(byAdding: .day, value: step, to: d)!
        }
        if arr.last != end { arr.append(end) }
        return arr
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: EditorialSpacing.lg) {
                    kpiHeader
                        .padding(.horizontal)

                    if filtered.isEmpty {
                        emptyStateView
                    } else {
                        chartSection
                            .padding(.horizontal)

                        if let selected = selectedDataPoint {
                            dataPointDetailCard(measurement: selected)
                                .padding(.horizontal)
                                .transition(.opacity)
                        }

                        aiInsightsSection
                            .padding(.horizontal)
                    }
                }
                .padding(.vertical, 12)
            }
            .background(AppColor.background)
            .safeAreaInset(edge: .top) {
                pickerSection
                    .padding(.vertical, 8)
                    .background(AppColor.background)
                    .overlay(AppDivider(), alignment: .bottom)
            }
            .navigationTitle(NSLocalizedString("Trends", comment: ""))
            .navigationBarTitleDisplayMode(.inline)
            .sheet(item: $editingMeasurement) { measurement in
                AddMeasurementView(editing: measurement) { updated in
                    store.updateMeasurement(updated)
                    selectedDataPoint = updated
                    Haptics.success()
                }
            }
            .alert(NSLocalizedString("Delete Measurement", comment: ""), isPresented: deleteConfirmationBinding) {
                Button(NSLocalizedString("Delete", comment: ""), role: .destructive) {
                    deleteSelectedMeasurement()
                }
                Button(NSLocalizedString("Cancel", comment: ""), role: .cancel) {
                    deleteTarget = nil
                }
            } message: {
                Text(NSLocalizedString("This measurement will be removed from trends and future visit summaries.", comment: ""))
            }
        }
    }

    // MARK: - Empty State
    private var emptyStateView: some View {
        EmptyStateView(
            systemImage: "chart.xyaxis.line",
            title: NSLocalizedString("No data in range", comment: ""),
            subtitle: NSLocalizedString("Add measurements to see trends", comment: "")
        )
        .frame(minHeight: 260)
    }

    // MARK: - KPI Header
    private var kpiHeader: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
            kpiCell(label: NSLocalizedString("Latest", comment: ""), value: latestText(), unit: selectedType.unit)
            kpiCell(label: NSLocalizedString("Change", comment: ""), value: deltaText(), unit: "")
            kpiCell(label: NSLocalizedString("7d Avg", comment: ""), value: sevenDayAverageText(), unit: "")
            kpiCell(label: NSLocalizedString("7d In\u{2011}Range", comment: ""), value: sevenDayInRangeText(), unit: "")
        }
    }

    private func kpiCell(label: String, value: String, unit: String) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .appFontNumeric(.title)
                .foregroundStyle(AppColor.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            Text(label)
                .appFont(.caption)
                .foregroundStyle(AppColor.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, AppSpacing.small)
        .background(
            RoundedRectangle(cornerRadius: AppRadius.medium, style: .continuous)
                .fill(AppColor.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: AppRadius.medium, style: .continuous)
                .stroke(AppColor.divider, lineWidth: 1)
        )
    }

    // MARK: - Chart Section
    private var chartSection: some View {
        chart
            .frame(height: 260)
    }

    // MARK: - Data Point Detail
    private func dataPointDetailCard(measurement: Measurement) -> some View {
        VStack(alignment: .leading, spacing: EditorialSpacing.md) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: EditorialSpacing.xs) {
                    Text(measurementValueText(measurement))
                        .appFont(.subheadline)
                        .fontWeight(.bold)
                        .foregroundStyle(AppColor.textPrimary)

                    HStack(spacing: EditorialSpacing.sm) {
                        Text(measurement.date, style: .date)
                        Text(measurement.date, style: .time)
                    }
                    .appFont(.caption)
                    .foregroundStyle(AppColor.textSecondary)

                    if let note = measurement.note, !note.isEmpty {
                        Text(note)
                            .appFont(.caption)
                            .foregroundStyle(AppColor.textSecondary)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                Spacer(minLength: 0)

                Button {
                    withAnimation(.easeInOut(duration: 0.2)) { selectedDataPoint = nil }
                } label: {
                    Image(systemName: "xmark.circle")
                        .font(.system(size: 20, weight: .regular))
                        .foregroundStyle(AppColor.textTertiary)
                }
                .accessibilityLabel(NSLocalizedString("Close", comment: ""))
            }

            HStack(spacing: EditorialSpacing.sm) {
                Button {
                    editingMeasurement = measurement
                } label: {
                    Label(NSLocalizedString("Edit", comment: ""), systemImage: "square.and.pencil")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .tint(AppColor.primary)
                .controlSize(.small)

                Button(role: .destructive) {
                    deleteTarget = measurement
                } label: {
                    Label(NSLocalizedString("Delete", comment: ""), systemImage: "trash")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .tint(AppColor.warning)
                .controlSize(.small)
            }
        }
        .padding(.horizontal, AppSpacing.medium)
        .padding(.vertical, AppSpacing.medium)
        .background(
            RoundedRectangle(cornerRadius: AppRadius.small, style: .continuous)
                .fill(AppColor.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: AppRadius.small, style: .continuous)
                .stroke(AppColor.divider, lineWidth: 1)
        )
    }

    // MARK: - AI Insights Section
    private var hasAIKey: Bool {
        AIService.shared.isConfigured
    }

    @ViewBuilder
    private var aiInsightsSection: some View {
        if !filtered.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    HStack(spacing: 6) {
                        Image(systemName: "text.magnifyingglass")
                            .font(.system(size: 14, weight: .regular))
                            .foregroundStyle(AppColor.primary)
                        Text(NSLocalizedString("AI Analysis", comment: ""))
                            .appFont(.subheadline)
                            .foregroundStyle(AppColor.textPrimary)
                    }
                    Spacer()
                    if !isLoadingInsights {
                        Button {
                            beginInsightFlow()
                        } label: {
                            Text(aiInsights == nil ? NSLocalizedString("Generate", comment: "") : NSLocalizedString("Refresh", comment: ""))
                                .appFont(.caption)
                        }
                        .buttonStyle(.bordered)
                        .tint(AppColor.primary)
                        .controlSize(.small)
                    }
                }

                Text(aiSectionSubtitle)
                    .appFont(.caption)
                    .foregroundStyle(AppColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                if isLoadingInsights {
                    HStack(spacing: 10) {
                        ProgressView()
                            .controlSize(.small)
                        Text(NSLocalizedString("Analyzing...", comment: "AI insight loading"))
                            .appFont(.caption)
                            .foregroundStyle(AppColor.textSecondary)
                    }
                    .padding(.vertical, 12)
                } else if let insights = aiInsights {
                    Text(insights)
                        .appFont(.caption)
                        .foregroundStyle(AppColor.textPrimary)
                        .lineSpacing(5)
                }
            }
            .padding(AppSpacing.medium)
            .background(
            RoundedRectangle(cornerRadius: AppRadius.medium, style: .continuous)
                    .fill(AppColor.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: AppRadius.medium, style: .continuous)
                    .stroke(AppColor.divider, lineWidth: 1)
            )
            .alert(NSLocalizedString("Send Data for AI Analysis?", comment: "AI consent alert title"), isPresented: $showAIDataDisclosure) {
                Button(NSLocalizedString("Analyze with AI", comment: "AI consent action")) {
                    AIService.shared.hasUserConsent = true
                    generateAIInsights()
                }
                Button(NSLocalizedString("Use On-Device Summary", comment: "AI local fallback action")) {
                    generateLocalOnlyInsights()
                }
                Button(NSLocalizedString("Cancel", comment: ""), role: .cancel) { }
            } message: {
                Text(aiDataDisclosureMessage)
            }
        }
    }

    private var aiSectionSubtitle: String {
        if !hasAIKey {
            return NSLocalizedString("Generate an on-device summary now. Add an API key in Settings to use provider analysis.", comment: "AI section no key subtitle")
        }
        if !AIService.shared.hasUserConsent {
            return NSLocalizedString("Provider analysis is off until you approve sending a limited trend summary.", comment: "AI section consent subtitle")
        }
        return NSLocalizedString("Uses a limited trend summary: recent readings, related medication names and doses, and aggregate stats.", comment: "AI section enabled subtitle")
    }

    private var aiDataDisclosureMessage: String {
        NSLocalizedString("This sends up to 20 recent readings for the selected measurement type, related medication names and doses, and aggregate stats to your selected AI provider. Notes, contacts, emergency info, and raw backups are not sent.", comment: "AI consent disclosure")
    }

    // MARK: - Pickers
    private var pickerSection: some View {
        HStack(spacing: 12) {
            Picker("Type", selection: $selectedType) {
                ForEach(MeasurementType.allCases) { t in
                    Text(t.rawValue).tag(t)
                }
            }
            .pickerStyle(.segmented)
            .onChange(of: selectedType) { _ in
                withAnimation {
                    selectedDataPoint = nil
                    aiInsights = nil
                }
            }

            Picker("Range", selection: $rangeDays) {
                Text(NSLocalizedString("7d", comment: "")).tag(7)
                Text(NSLocalizedString("30d", comment: "")).tag(30)
                Text(NSLocalizedString("90d", comment: "")).tag(90)
            }
            .pickerStyle(.segmented)
            .frame(width: 140)
            .onChange(of: rangeDays) { _ in
                withAnimation {
                    selectedDataPoint = nil
                }
            }
        }
        .padding(.horizontal)
    }

    // MARK: - Chart
    @ViewBuilder
    private var chart: some View {
        switch selectedType {
        case .bloodPressure:
            bloodPressureChart
        case .bloodGlucose:
            interactiveLineChart(unit: UnitPreferences.glucoseUnit.rawValue)
        case .weight:
            interactiveLineChart(unit: "kg")
        case .heartRate:
            interactiveLineChart(unit: "bpm")
        }
    }

    private var bloodPressureChart: some View {
        let start = Calendar.current.date(byAdding: .day, value: -rangeDays, to: Date())!
        let end = Date()
        let points = bpPoints
        let thresholds = store.bpThresholds()
        let systolicMax = points.map { $0.systolic }.max() ?? thresholds.systolicHigh
        let upperBound = max(systolicMax, thresholds.systolicHigh) + 10
        let lowerCandidate = min(points.compactMap { $0.diastolic }.min() ?? thresholds.diastolicHigh, thresholds.diastolicHigh)
        let lowerBound = max(40, lowerCandidate - 10)

        return Chart {
            RuleMark(y: .value("Systolic High", thresholds.systolicHigh))
                .lineStyle(.init(dash: [4, 4]))
                .foregroundStyle(AppColor.warning.opacity(0.6))
                .annotation(position: .top, alignment: .trailing) {
                    Text(NSLocalizedString("High", comment: "chart annotation"))
                        .appFont(.caption)
                        .foregroundStyle(AppColor.warning)
                        .padding(4)
                        .background(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(AppColor.surface)
                        )
                }

            RuleMark(y: .value("Diastolic High", thresholds.diastolicHigh))
                .lineStyle(.init(dash: [4, 4]))
                .foregroundStyle(AppColor.warning.opacity(0.6))

            ForEach(points.filter { $0.diastolic != nil }) { p in
                AreaMark(
                    x: .value("Date", p.date),
                    yStart: .value("Dia", p.diastolic!),
                    yEnd: .value("Sys", p.systolic)
                )
                .foregroundStyle(
                    LinearGradient(
                        colors: [AppColor.primary.opacity(0.12), AppColor.primary.opacity(0.03)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
            }

            ForEach(points) { p in
                LineMark(
                    x: .value("Date", p.date),
                    y: .value("Systolic", p.systolic)
                )
                .interpolationMethod(.catmullRom)
                .foregroundStyle(by: .value("Series", NSLocalizedString("Systolic", comment: "")))
                .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round))
            }

            ForEach(points.filter { $0.diastolic != nil }) { p in
                LineMark(
                    x: .value("Date", p.date),
                    y: .value("Diastolic", p.diastolic!)
                )
                .interpolationMethod(.catmullRom)
                .foregroundStyle(by: .value("Series", NSLocalizedString("Diastolic", comment: "")))
                .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round))
            }

            ForEach(points) { p in
                let isSelected = selectedDataPoint.map { $0.id == p.id } ?? false
                PointMark(
                    x: .value("Date", p.date),
                    y: .value("Systolic", p.systolic)
                )
                .symbolSize(isSelected ? 120 : 50)
                .foregroundStyle(AppColor.primary)
            }

            if let selected = selectedDataPoint {
                RuleMark(x: .value("Selected", selected.date))
                    .lineStyle(.init(dash: [2, 2]))
                    .foregroundStyle(.secondary.opacity(0.5))
            }
        }
        .chartLegend(position: .bottom, alignment: .leading)
        .chartXScale(domain: start...end)
        .chartYScale(domain: lowerBound...upperBound)
        .chartXAxis {
            AxisMarks(values: xAxisValues) { value in
                AxisGridLine()
                AxisTick()
                AxisValueLabel {
                    if let date = value.as(Date.self) {
                        Text(date, format: .dateTime.month(.twoDigits).day(.twoDigits))
                            .appFont(.caption)
                    }
                }
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading) { value in
                AxisGridLine()
                AxisTick()
                AxisValueLabel {
                    if let doubleValue = value.as(Double.self) {
                        Text("\(Int(doubleValue))")
                            .appFont(.caption)
                    }
                }
            }
        }
        .chartOverlay { proxy in
            GeometryReader { geo in
                Rectangle().fill(.clear).contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onEnded { drag in
                                guard let date: Date = proxy.value(atX: drag.location.x) else { return }
                                let nearest = filtered.min(by: { abs($0.date.timeIntervalSince(date)) < abs($1.date.timeIntervalSince(date)) })
                                withAnimation(.easeInOut(duration: 0.2)) { selectedDataPoint = nearest }
                            }
                    )
            }
        }
    }

    private func interactiveLineChart(unit: String) -> some View {
        let start = Calendar.current.date(byAdding: .day, value: -rangeDays, to: Date())!
        let end = Date()
        let normal = store.customGoalRange(for: selectedType) ?? selectedType.normalRange
        var displayRange: ClosedRange<Double>? = nil
        if let r = normal {
            if selectedType == .bloodGlucose {
                displayRange = UnitPreferences.mgdlToPreferred(r.lowerBound)...UnitPreferences.mgdlToPreferred(r.upperBound)
            } else {
                displayRange = r
            }
        }
        let displayValues = filtered.map { (selectedType == .bloodGlucose) ? UnitPreferences.mgdlToPreferred($0.value) : $0.value }
        let yFloor = displayValues.min().map { $0 * 0.95 } ?? 0

        return Chart {
            if let rDisplay = displayRange {
                RectangleMark(
                    xStart: .value("Start", start),
                    xEnd: .value("End", end),
                    yStart: .value("Low", rDisplay.lowerBound),
                    yEnd: .value("High", rDisplay.upperBound)
                )
                .foregroundStyle(AppColor.primary.opacity(0.06))

                RuleMark(y: .value("High", rDisplay.upperBound))
                    .lineStyle(.init(dash: [4,4]))
                    .foregroundStyle(AppColor.primary.opacity(0.55))
                    .annotation(position: .top, alignment: .trailing) {
                        Text(NSLocalizedString("Target", comment: "chart annotation"))
                            .appFont(.caption)
                            .foregroundStyle(AppColor.primary)
                            .padding(4)
                            .background(
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .fill(AppColor.surface)
                            )
                    }

                RuleMark(y: .value("Low", rDisplay.lowerBound))
                    .lineStyle(.init(dash: [4,4]))
                    .foregroundStyle(AppColor.primary.opacity(0.55))
            }

            ForEach(filtered) { m in
                let yVal = (selectedType == .bloodGlucose) ? UnitPreferences.mgdlToPreferred(m.value) : m.value
                AreaMark(
                    x: .value("Date", m.date),
                    yStart: .value("Base", yFloor),
                    yEnd: .value("Value", yVal)
                )
                .foregroundStyle(
                    LinearGradient(
                        colors: [AppColor.primary.opacity(0.10), AppColor.primary.opacity(0.02)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .interpolationMethod(.catmullRom)
            }

            ForEach(filtered) { m in
                let yVal = (selectedType == .bloodGlucose) ? UnitPreferences.mgdlToPreferred(m.value) : m.value
                LineMark(
                    x: .value("Date", m.date),
                    y: .value("Value", yVal)
                )
                .interpolationMethod(.catmullRom)
                .foregroundStyle(AppColor.primary)
                .lineStyle(StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
            }

            ForEach(filtered) { m in
                let yVal = (selectedType == .bloodGlucose) ? UnitPreferences.mgdlToPreferred(m.value) : m.value
                let isOutOfRange: Bool = {
                    let range = store.customGoalRange(for: selectedType) ?? selectedType.normalRange
                    if let r = range { return !r.contains(m.value) }
                    return false
                }()

                PointMark(
                    x: .value("Date", m.date),
                    y: .value("Value", yVal)
                )
                .symbolSize(selectedDataPoint?.id == m.id ? 120 : (isOutOfRange ? 80 : 60))
                .foregroundStyle(isOutOfRange ? AppColor.warning : AppColor.primary)
            }

            if let selected = selectedDataPoint {
                RuleMark(x: .value("Selected", selected.date))
                    .lineStyle(.init(dash: [2, 2]))
                    .foregroundStyle(.secondary.opacity(0.5))
            }
        }
        .chartXScale(domain: start...end)
        .chartXAxis {
            AxisMarks(values: xAxisValues) { value in
                AxisGridLine()
                AxisTick()
                AxisValueLabel {
                    if let date = value.as(Date.self) {
                        Text(date, format: .dateTime.month(.twoDigits).day(.twoDigits))
                            .appFont(.caption)
                    }
                }
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading)
        }
        .chartYAxisLabel(unit)
        .chartOverlay { proxy in
            GeometryReader { geo in
                Rectangle().fill(.clear).contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onEnded { drag in
                                guard let date: Date = proxy.value(atX: drag.location.x) else { return }
                                let nearest = filtered.min(by: { abs($0.date.timeIntervalSince(date)) < abs($1.date.timeIntervalSince(date)) })
                                withAnimation(.easeInOut(duration: 0.2)) { selectedDataPoint = nearest }
                            }
                    )
            }
        }
    }

    // MARK: - Helpers
    private func measurementValueText(_ measurement: Measurement) -> String {
        if measurement.type == .bloodPressure, let dia = measurement.diastolic {
            return "\(Int(measurement.value))/\(Int(dia)) \(measurement.type.unit)"
        }
        if measurement.type == .bloodGlucose {
            let value = UnitPreferences.mgdlToPreferred(measurement.value)
            let formatted = UnitPreferences.glucoseUnit == .mgdL ? String(format: "%.0f", value) : String(format: "%.1f", value)
            return "\(formatted) \(UnitPreferences.glucoseUnit.rawValue)"
        }
        return "\(String(format: "%.1f", measurement.value)) \(measurement.type.unit)"
    }

    private func deleteSelectedMeasurement() {
        guard let deleteTarget else { return }
        store.removeMeasurement(deleteTarget)
        if selectedDataPoint?.id == deleteTarget.id {
            selectedDataPoint = nil
        }
        self.deleteTarget = nil
        Haptics.notification(.warning)
    }

    private func latestText() -> String {
        guard let last = filtered.last else { return "—" }
        switch selectedType {
        case .bloodPressure:
            if let d = last.diastolic { return "\(Int(last.value))/\(Int(d))" }
            return "\(Int(last.value))"
        case .bloodGlucose:
            let v = UnitPreferences.mgdlToPreferred(last.value)
            let fmt = UnitPreferences.glucoseUnit == .mgdL ? "%.0f" : "%.1f"
            return String(format: fmt, v)
        default:
            return String(format: "%.1f", last.value)
        }
    }

    private func deltaText() -> String {
        guard filtered.count >= 2 else { return "—" }
        let last = filtered[filtered.count - 1]
        let prev = filtered[filtered.count - 2]
        switch selectedType {
        case .bloodPressure:
            let sDiff = Int(last.value - prev.value)
            return "\(sDiff >= 0 ? "+" : "")\(sDiff)"
        case .bloodGlucose:
            let diffMg = last.value - prev.value
            let diff = UnitPreferences.mgdlToPreferred(diffMg)
            let sign = diff >= 0 ? "+" : ""
            let fmt = UnitPreferences.glucoseUnit == .mgdL ? "%.0f" : "%.1f"
            return "\(sign)\(String(format: fmt, diff))"
        default:
            let diff = last.value - prev.value
            let sign = diff >= 0 ? "+" : ""
            return "\(sign)\(String(format: "%.1f", diff))"
        }
    }

    private func sevenDayAverageText() -> String {
        guard !sevenDaySlice.isEmpty else { return "—" }
        switch selectedType {
        case .bloodPressure:
            let sysAvg = sevenDaySlice.map { $0.value }.reduce(0, +) / Double(sevenDaySlice.count)
            return "\(Int(sysAvg))"
        case .bloodGlucose:
            let avgMg = sevenDaySlice.map { $0.value }.reduce(0, +) / Double(sevenDaySlice.count)
            let avg = UnitPreferences.mgdlToPreferred(avgMg)
            let fmt = UnitPreferences.glucoseUnit == .mgdL ? "%.0f" : "%.1f"
            return String(format: fmt, avg)
        default:
            let avg = sevenDaySlice.map { $0.value }.reduce(0, +) / Double(sevenDaySlice.count)
            return String(format: "%.1f", avg)
        }
    }

    private func sevenDayInRangeText() -> String {
        guard !sevenDaySlice.isEmpty else { return "—" }
        let ok: Int = sevenDaySlice.reduce(0) { acc, m in
            switch selectedType {
            case .bloodPressure:
                let th = store.bpThresholds()
                let inRange: Bool
                if let d = m.diastolic {
                    inRange = m.value < th.systolicHigh && d < th.diastolicHigh
                } else {
                    inRange = m.value < th.systolicHigh
                }
                return acc + (inRange ? 1 : 0)
            default:
                let range = store.customGoalRange(for: selectedType) ?? selectedType.normalRange
                if let r = range { return acc + (r.contains(m.value) ? 1 : 0) }
                return acc
            }
        }
        let pct = Double(ok) / Double(sevenDaySlice.count)
        return "\(Int(pct * 100))%"
    }

    private func beginInsightFlow() {
        guard !filtered.isEmpty else { return }
        if !hasAIKey {
            generateLocalOnlyInsights()
            return
        }
        if !AIService.shared.hasUserConsent {
            showAIDataDisclosure = true
            return
        }
        generateAIInsights()
    }

    private func generateAIInsights() {
        guard !filtered.isEmpty else { return }

        isLoadingInsights = true
        Task {
            do {
                let insights = try await generateTrendInsights()
                await MainActor.run {
                    self.aiInsights = insights
                    self.isLoadingInsights = false
                    Haptics.success()
                }
            } catch {
                await MainActor.run {
                    self.aiInsights = String(
                        format: NSLocalizedString("AI analysis could not be completed. Showing an on-device summary instead.\n\n%@", comment: "AI failure local fallback"),
                        generateLocalInsights()
                    )
                    self.isLoadingInsights = false
                    Haptics.notification(.warning)
                }
            }
        }
    }

    private func generateLocalOnlyInsights() {
        aiInsights = generateLocalInsights()
        Haptics.success()
    }

    private func generateTrendInsights() async throws -> String {
        let measurementData = filtered.suffix(20).map { m -> String in
            let dateStr = ISO8601DateFormatter().string(from: m.date)
            if selectedType == .bloodPressure, let dia = m.diastolic {
                return "\(dateStr): \(Int(m.value))/\(Int(dia)) mmHg"
            } else {
                return "\(dateStr): \(m.value) \(selectedType.unit)"
            }
        }

        // Get related medications
        let relatedCategory: MedicationCategory? = {
            switch selectedType {
            case .bloodPressure: return .antihypertensive
            case .bloodGlucose: return .antidiabetic
            default: return nil
            }
        }()

        let medications = relatedCategory != nil ?
            store.medications.filter { $0.category == relatedCategory } : []

        let request = AITrendInsightRequest(
            measurementType: selectedType.displayName,
            recentMeasurements: measurementData,
            relatedMedications: medications.map {
                DrugInteractionRequest.MedicationInfo(
                    name: $0.name,
                    dose: $0.dose,
                    category: $0.category?.displayName
                )
            },
            latest: latestText(),
            change: deltaText(),
            sevenDayAverage: sevenDayAverageText(),
            sevenDayInRange: sevenDayInRangeText()
        )

        return try await AIService.shared.analyzeTrendInsights(request)
    }

    private func generateLocalInsights() -> String {
        var insights = String(format: NSLocalizedString("%@ Summary", comment: "Local trend insight title"), selectedType.displayName)
        insights += "\n\n"

        // Trend analysis
        if filtered.count >= 3 {
            let recent3 = Array(filtered.suffix(3))
            let values = recent3.map { $0.value }
            let isIncreasing = zip(values, values.dropFirst()).allSatisfy { $0 < $1 }
            let isDecreasing = zip(values, values.dropFirst()).allSatisfy { $0 > $1 }

            if isIncreasing {
                insights += String(format: NSLocalizedString("Recent %@ readings are trending upward.", comment: "Local trend upward"), selectedType.displayName.lowercased())
            } else if isDecreasing {
                insights += String(format: NSLocalizedString("Recent %@ readings are trending downward.", comment: "Local trend downward"), selectedType.displayName.lowercased())
            } else {
                insights += String(format: NSLocalizedString("Recent %@ readings look relatively stable.", comment: "Local trend stable"), selectedType.displayName.lowercased())
            }
        } else {
            insights += NSLocalizedString("More readings are needed before a reliable trend can be estimated.", comment: "Local sparse trend")
        }

        insights += "\n\n"

        // Current stats
        insights += NSLocalizedString("Recent Stats:", comment: "Local trend stats header") + "\n"
        insights += String(format: NSLocalizedString("- Latest reading: %@", comment: "Local latest stat"), latestText()) + "\n"
        insights += String(format: NSLocalizedString("- Change from previous: %@", comment: "Local change stat"), deltaText()) + "\n"
        insights += String(format: NSLocalizedString("- 7-day average: %@", comment: "Local average stat"), sevenDayAverageText()) + "\n"
        insights += String(format: NSLocalizedString("- Within target range: %@", comment: "Local range stat"), sevenDayInRangeText()) + "\n\n"

        // Recommendations
        insights += NSLocalizedString("Suggested Review:", comment: "Local recommendations header") + "\n"
        insights += NSLocalizedString("- Keep recording at consistent times so trends are easier to compare.", comment: "Local recommendation consistent") + "\n"
        insights += NSLocalizedString("- Add context notes when symptoms, meals, activity, or missed medication may affect a reading.", comment: "Local recommendation notes") + "\n"
        insights += NSLocalizedString("- Discuss medication or dose changes with your clinician.", comment: "Local recommendation clinician")

        if let trendWarning = DataValidator.analyzeTrend(measurements: filtered, type: selectedType) {
            insights += "\n\n"
            insights += String(format: NSLocalizedString("Note: %@", comment: "Local trend warning"), trendWarning)
        }

        return insights
    }
}

#Preview {
    EnhancedTrendsView()
        .environmentObject(DataStore())
}
