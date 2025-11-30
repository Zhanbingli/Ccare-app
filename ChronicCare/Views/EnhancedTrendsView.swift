import SwiftUI
import Charts

struct EnhancedTrendsView: View {
    @EnvironmentObject var store: DataStore

    @State private var selectedType: MeasurementType = .bloodPressure
    @State private var rangeDays: Int = 30
    @State private var selectedDataPoint: Measurement?
    @State private var showDataPointPicker = false
    @State private var showAIInsights = false
    @State private var aiInsights: String?
    @State private var isLoadingInsights = false
    @AppStorage("units.glucose") private var glucoseUnitRaw: String = GlucoseUnit.mgdL.rawValue

    private var filtered: [Measurement] {
        let start = Calendar.current.date(byAdding: .day, value: -rangeDays, to: Date())!
        return store.measurements
            .filter { $0.type == selectedType && $0.date >= start }
            .sorted(by: { $0.date < $1.date })
    }

    private var sevenDaySlice: [Measurement] {
        let start = Calendar.current.date(byAdding: .day, value: -7, to: Date())!
        return store.measurements
            .filter { $0.type == selectedType && $0.date >= start }
            .sorted(by: { $0.date < $1.date })
    }

    private struct BPDaily: Identifiable {
        let date: Date
        let systolic: Double
        let diastolic: Double?
        var id: Date { date }
    }

    private var bpDaily: [BPDaily] {
        guard selectedType == .bloodPressure else { return [] }
        let cal = Calendar.current
        let groups = Dictionary(grouping: filtered) { m in cal.startOfDay(for: m.date) }
        func median(_ arr: [Double]) -> Double? {
            guard !arr.isEmpty else { return nil }
            let s = arr.sorted()
            let n = s.count
            if n % 2 == 1 { return s[n/2] }
            return (s[n/2 - 1] + s[n/2]) / 2
        }
        let items = groups.keys.sorted().compactMap { day -> BPDaily? in
            guard let list = groups[day] else { return nil }
            let systolics = list.map { $0.value }
            let diastolics = list.compactMap { $0.diastolic }
            guard let sMed = median(systolics) else { return nil }
            let dMed = median(diastolics)
            return BPDaily(date: day, systolic: sMed, diastolic: dMed)
        }
        return items
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
                VStack(spacing: 16) {
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
                                .transition(.asymmetric(
                                    insertion: .move(edge: .bottom).combined(with: .opacity),
                                    removal: .move(edge: .top).combined(with: .opacity)
                                ))
                        }

                        aiInsightsSection
                            .padding(.horizontal)

                        effectivenessCard
                            .padding(.horizontal)
                    }
                }
                .padding(.vertical)
            }
            .safeAreaInset(edge: .top) {
                VStack(spacing: 8) {
                    pickerSection
                }
                .padding(.vertical, 8)
                .background(.ultraThinMaterial)
                .overlay(Divider(), alignment: .bottom)
            }
            .navigationTitle("Trends")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    // MARK: - Empty State
    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "chart.xyaxis.line")
                .font(.system(size: 60))
                .foregroundStyle(.secondary)
            Text("No data in range")
                .appFont(.headline)
                .foregroundStyle(.secondary)
            Text("Add measurements to see trends")
                .appFont(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 300)
    }

    // MARK: - KPI Header
    private var kpiHeader: some View {
        VStack(spacing: 12) {
            TintedCard(tint: selectedType.tint) {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(selectedType.rawValue)
                                .appFont(.title)
                                .foregroundStyle(.white)
                            Text("\(rangeDays) Day Overview")
                                .appFont(.subheadline)
                                .foregroundStyle(.white.opacity(0.8))
                        }
                        Spacer()
                        Image(systemName: selectedType.systemImage)
                            .font(.system(size: 40))
                            .foregroundStyle(.white.opacity(0.3))
                    }

                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: 12)], spacing: 12) {
                        kpiTile(title: "Latest", value: latestText(), icon: "arrow.up.right.circle.fill")
                        kpiTile(title: "Change", value: deltaText(), icon: "arrow.triangle.2.circlepath")
                        kpiTile(title: "7d Avg", value: sevenDayAverageText(), icon: "chart.bar.fill")
                        kpiTile(title: "In Range", value: sevenDayInRangeText(), icon: "target")
                    }
                }
            }

            if let insight = insightSummary() {
                Card {
                    HStack(spacing: 12) {
                        Image(systemName: "lightbulb.fill")
                            .font(.title2)
                            .foregroundStyle(.yellow)
                        VStack(alignment: .leading, spacing: 6) {
                            Text(insight.title).appFont(.headline)
                            Text(insight.detail).appFont(.footnote).foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
    }

    private func kpiTile(title: String, value: String, icon: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.7))
                Text(title)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white.opacity(0.85))
            }
            Text(value)
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.white.opacity(0.15))
        )
    }

    // MARK: - Chart Section
    private var chartSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Data Visualization")
                    .appFont(.headline)
                Spacer()
                if selectedDataPoint != nil {
                    Button {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                            selectedDataPoint = nil
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Text("Clear")
                                .appFont(.caption)
                            Image(systemName: "xmark.circle.fill")
                                .font(.caption)
                        }
                        .foregroundStyle(.secondary)
                    }
                }
            }

            chart
                .frame(height: 280)
                .contentShape(Rectangle())
                .onTapGesture {
                    if !filtered.isEmpty {
                        showDataPointPicker = true
                    }
                }

            if !filtered.isEmpty {
                HStack(spacing: 8) {
                    Text("Tap chart to select data points")
                        .appFont(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    if selectedDataPoint != nil {
                        Text("1 selected")
                            .appFont(.caption)
                            .foregroundStyle(.blue)
                    }
                }
            }
        }
        .sheet(isPresented: $showDataPointPicker) {
            DataPointPickerView(
                measurements: filtered,
                selectedMeasurement: $selectedDataPoint,
                measurementType: selectedType
            )
            .presentationDetents([.medium, .large])
        }
    }

    // MARK: - Data Point Detail
    private func dataPointDetailCard(measurement: Measurement) -> some View {
        Card {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Selected Data Point")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.primary)
                        HStack(spacing: 8) {
                            Text(measurement.date, style: .date)
                                .font(.system(size: 13, weight: .regular))
                                .foregroundStyle(.secondary)
                            Text("•")
                                .foregroundStyle(.secondary)
                            Text(measurement.date, style: .time)
                                .font(.system(size: 13, weight: .regular))
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    Button {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                            selectedDataPoint = nil
                        }
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 22))
                            .foregroundStyle(.secondary)
                    }
                }

                Divider()

                HStack(spacing: 24) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Value")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.secondary)
                            .textCase(.uppercase)
                            .tracking(0.5)
                        if measurement.type == .bloodPressure, let dia = measurement.diastolic {
                            HStack(alignment: .firstTextBaseline, spacing: 4) {
                                Text("\(Int(measurement.value))/\(Int(dia))")
                                    .font(.system(size: 28, weight: .bold, design: .rounded))
                                    .foregroundStyle(.primary)
                                Text(measurement.type.unit)
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundStyle(.secondary)
                            }
                        } else if measurement.type == .bloodGlucose {
                            let v = UnitPreferences.mgdlToPreferred(measurement.value)
                            let unit = UnitPreferences.glucoseUnit.rawValue
                            let formatted = UnitPreferences.glucoseUnit == .mgdL ? String(format: "%.0f", v) : String(format: "%.1f", v)
                            HStack(alignment: .firstTextBaseline, spacing: 4) {
                                Text(formatted)
                                    .font(.system(size: 28, weight: .bold, design: .rounded))
                                    .foregroundStyle(.primary)
                                Text(unit)
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundStyle(.secondary)
                            }
                        } else {
                            HStack(alignment: .firstTextBaseline, spacing: 4) {
                                Text(String(format: "%.1f", measurement.value))
                                    .font(.system(size: 28, weight: .bold, design: .rounded))
                                    .foregroundStyle(.primary)
                                Text(measurement.type.unit)
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }

                    if let note = measurement.note, !note.isEmpty {
                        Divider()
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Note")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(.secondary)
                                .textCase(.uppercase)
                                .tracking(0.5)
                            Text(note)
                                .font(.system(size: 15, weight: .regular))
                                .foregroundStyle(.primary)
                                .lineLimit(3)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
        }
    }

    // MARK: - AI Insights Section
    private var aiInsightsSection: some View {
        Card {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    HStack(spacing: 8) {
                        Image(systemName: "brain.head.profile")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.purple)
                        Text("AI Insights")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.primary)
                    }
                    Spacer()
                    if !isLoadingInsights {
                        Button {
                            generateAIInsights()
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "sparkles")
                                    .font(.system(size: 11, weight: .semibold))
                                Text(aiInsights == nil ? "Generate" : "Refresh")
                                    .font(.system(size: 12, weight: .medium))
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                }

                if isLoadingInsights {
                    HStack(spacing: 12) {
                        ProgressView()
                        Text("Analyzing your health data...")
                            .font(.system(size: 14, weight: .regular))
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 24)
                } else if let insights = aiInsights {
                    Text(insights)
                        .font(.system(size: 15, weight: .regular))
                        .foregroundStyle(.primary)
                        .lineSpacing(4)
                } else {
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: "wand.and.stars")
                            .font(.system(size: 20))
                            .foregroundStyle(.purple)
                        Text("Tap Generate to get AI-powered insights about your health trends")
                            .font(.system(size: 14, weight: .regular))
                            .foregroundStyle(.secondary)
                            .lineSpacing(2)
                    }
                    .padding(.vertical, 8)
                }
            }
        }
    }

    // MARK: - Pickers
    private var pickerSection: some View {
        VStack(spacing: 8) {
            Picker("Type", selection: $selectedType) {
                ForEach(MeasurementType.allCases) { t in
                    Text(t.rawValue).tag(t)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .onChange(of: selectedType) { _ in
                withAnimation {
                    selectedDataPoint = nil
                    aiInsights = nil
                }
            }

            Picker("Range", selection: $rangeDays) {
                Text("7d").tag(7)
                Text("30d").tag(30)
                Text("90d").tag(90)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .onChange(of: rangeDays) { _ in
                withAnimation {
                    selectedDataPoint = nil
                }
            }
        }
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
        let daily = bpDaily
        let thresholds = store.bpThresholds()
        let systolicMax = daily.map { $0.systolic }.max() ?? thresholds.systolicHigh
        let upperBound = max(systolicMax, thresholds.systolicHigh) + 10
        let lowerCandidate = min(daily.compactMap { $0.diastolic }.min() ?? thresholds.diastolicHigh, thresholds.diastolicHigh)
        let lowerBound = max(40, lowerCandidate - 10)

        return Chart {
            RuleMark(y: .value("Systolic High", thresholds.systolicHigh))
                .lineStyle(.init(dash: [4, 4]))
                .foregroundStyle(.red.opacity(0.6))
                .annotation(position: .top, alignment: .trailing) {
                    Text("High")
                        .appFont(.caption)
                        .foregroundStyle(.red)
                        .padding(4)
                        .background(Capsule().fill(.red.opacity(0.1)))
                }

            RuleMark(y: .value("Diastolic High", thresholds.diastolicHigh))
                .lineStyle(.init(dash: [4, 4]))
                .foregroundStyle(.red.opacity(0.6))

            ForEach(daily.compactMap { d -> (Date, Double, Double)? in
                if let dia = d.diastolic { return (d.date, dia, d.systolic) }
                return nil
            }, id: \.0) { item in
                AreaMark(
                    x: .value("Date", item.0),
                    yStart: .value("Dia", item.1),
                    yEnd: .value("Sys", item.2)
                )
                .foregroundStyle(
                    LinearGradient(
                        colors: [selectedType.tint.opacity(0.3), selectedType.tint.opacity(0.1)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
            }

            ForEach(daily) { d in
                LineMark(
                    x: .value("Date", d.date),
                    y: .value("Systolic", d.systolic)
                )
                .interpolationMethod(.catmullRom)
                .foregroundStyle(by: .value("Series", NSLocalizedString("Systolic", comment: "")))
                .lineStyle(StrokeStyle(lineWidth: 3, lineCap: .round))
            }

            ForEach(daily.compactMap { d -> (Date, Double)? in
                guard let dia = d.diastolic else { return nil }
                return (d.date, dia)
            }, id: \.0) { item in
                LineMark(
                    x: .value("Date", item.0),
                    y: .value("Diastolic", item.1)
                )
                .interpolationMethod(.catmullRom)
                .foregroundStyle(by: .value("Series", NSLocalizedString("Diastolic", comment: "")))
                .lineStyle(StrokeStyle(lineWidth: 3, lineCap: .round))
            }

            ForEach(daily) { d in
                let cal = Calendar.current
                let isSelected = selectedDataPoint.map { cal.isDate($0.date, inSameDayAs: d.date) } ?? false
                PointMark(
                    x: .value("Date", d.date),
                    y: .value("Systolic", d.systolic)
                )
                .symbolSize(isSelected ? 120 : 60)
                .foregroundStyle(.indigo)
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
        .chartPlotStyle { plot in
            plot
                .background(
                    LinearGradient(
                        colors: [Color(.systemBackground), Color(.secondarySystemBackground)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .cornerRadius(12)
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

        return Chart {
            if let rDisplay = displayRange {
                RectangleMark(
                    xStart: .value("Start", start),
                    xEnd: .value("End", end),
                    yStart: .value("Low", rDisplay.lowerBound),
                    yEnd: .value("High", rDisplay.upperBound)
                )
                .foregroundStyle(.green.opacity(0.1))

                RuleMark(y: .value("High", rDisplay.upperBound))
                    .lineStyle(.init(dash: [4,4]))
                    .foregroundStyle(.green.opacity(0.6))
                    .annotation(position: .top, alignment: .trailing) {
                        Text("Target")
                            .appFont(.caption)
                            .foregroundStyle(.green)
                            .padding(4)
                            .background(Capsule().fill(.green.opacity(0.1)))
                    }

                RuleMark(y: .value("Low", rDisplay.lowerBound))
                    .lineStyle(.init(dash: [4,4]))
                    .foregroundStyle(.green.opacity(0.6))
            }

            ForEach(filtered) { m in
                let yVal = (selectedType == .bloodGlucose) ? UnitPreferences.mgdlToPreferred(m.value) : m.value
                AreaMark(
                    x: .value("Date", m.date),
                    y: .value("Value", yVal)
                )
                .foregroundStyle(
                    LinearGradient(
                        colors: [selectedType.tint.opacity(0.3), selectedType.tint.opacity(0.05)],
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
                .foregroundStyle(selectedType.tint)
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
                .foregroundStyle(isOutOfRange ? .red : selectedType.tint)
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
        .chartPlotStyle { plot in
            plot
                .background(
                    LinearGradient(
                        colors: [Color(.systemBackground), Color(.secondarySystemBackground)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .cornerRadius(12)
        }
        .chartYAxisLabel(unit)
    }

    // MARK: - Effectiveness Card
    @ViewBuilder
    private var effectivenessCard: some View {
        let category: MedicationCategory? = {
            switch selectedType {
            case .bloodPressure: return .antihypertensive
            case .bloodGlucose: return .antidiabetic
            default: return nil
            }
        }()

        if let category {
            let meds = store.medications.filter { $0.category == category }
            if !meds.isEmpty {
                let results: [(Medication, MedicationEffectResult)] = meds.map { ($0, store.effectiveness(for: $0)) }
                let counts = (
                    effective: results.filter { $0.1.verdict == .likelyEffective }.count,
                    unclear: results.filter { $0.1.verdict == .unclear }.count,
                    ineffective: results.filter { $0.1.verdict == .likelyIneffective }.count
                )

                Card {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(NSLocalizedString("Medication Effectiveness", comment: "")).appFont(.headline)

                        HStack(spacing: 12) {
                            effectBadge(count: counts.effective, label: "Effective", color: .green, icon: "checkmark.circle.fill")
                            effectBadge(count: counts.unclear, label: "Unclear", color: .secondary, icon: "questionmark.circle")
                            effectBadge(count: counts.ineffective, label: "Ineffective", color: .red, icon: "xmark.circle.fill")
                        }

                        Divider()

                        VStack(spacing: 10) {
                            ForEach(results.prefix(3), id: \.0.id) { pair in
                                medicationEffectRow(medication: pair.0, result: pair.1)
                            }
                        }
                    }
                }
            }
        }
    }

    private func effectBadge(count: Int, label: String, color: Color, icon: String) -> some View {
        VStack(spacing: 6) {
            ZStack {
                Circle()
                    .fill(color.opacity(0.15))
                    .frame(width: 44, height: 44)
                Image(systemName: icon)
                    .foregroundStyle(color)
            }
            Text("\(count)")
                .appFont(.headline)
            Text(label)
                .appFont(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private func medicationEffectRow(medication: Medication, result: MedicationEffectResult) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(medication.name)
                    .appFont(.subheadline)
                if !result.summary.isEmpty {
                    Text(result.summary)
                        .appFont(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                Text(effectText(result))
                    .appFont(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(effectColor(result).opacity(0.15)))
                    .foregroundStyle(effectColor(result))
                if result.confidence > 0 {
                    Text("\(result.confidence)%")
                        .appFont(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(.tertiarySystemBackground))
        )
    }

    // MARK: - Helpers
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

    private func insightSummary() -> (title: String, detail: String)? {
        guard !filtered.isEmpty else { return nil }
        switch selectedType {
        case .bloodPressure:
            let latest = filtered.last!
            let thresholds = store.bpThresholds()
            if let dia = latest.diastolic, latest.value >= thresholds.systolicHigh || dia >= thresholds.diastolicHigh {
                return (NSLocalizedString("Blood pressure is above goal", comment: ""), NSLocalizedString("Consider logging how you feel and ensure reminders are on for medications.", comment: ""))
            }
            return (NSLocalizedString("Blood pressure looks steady", comment: ""), NSLocalizedString("Keep following your schedule to stay within targets.", comment: ""))
        case .bloodGlucose:
            return (NSLocalizedString("7-day glucose trends", comment: ""), NSLocalizedString("Track meals and activities that affect your readings.", comment: ""))
        case .weight:
            let latest = filtered.last!.value
            let baseline = filtered.first!.value
            let diff = latest - baseline
            let sign = diff >= 0 ? "+" : ""
            return (NSLocalizedString("Weight trend", comment: ""), String(format: "%.1f kg (%@%.1f since start)", latest, sign, diff))
        case .heartRate:
            return (NSLocalizedString("Heart rate monitoring", comment: ""), NSLocalizedString("Note any unusual patterns or symptoms.", comment: ""))
        }
    }

    private func effectText(_ r: MedicationEffectResult) -> String {
        switch r.verdict {
        case .likelyEffective: return NSLocalizedString("Effective", comment: "")
        case .unclear: return NSLocalizedString("Unclear", comment: "")
        case .likelyIneffective: return NSLocalizedString("Ineffective", comment: "")
        case .notApplicable: return NSLocalizedString("N/A", comment: "")
        }
    }

    private func effectColor(_ r: MedicationEffectResult) -> Color {
        switch r.verdict {
        case .likelyEffective: return .green
        case .unclear: return .secondary
        case .likelyIneffective: return .red
        case .notApplicable: return .secondary
        }
    }

    private func generateAIInsights() {
        guard !filtered.isEmpty else { return }

        isLoadingInsights = true
        Task {
            do {
                let config = AIService.shared.getConfiguration()
                guard !config.apiKey.isEmpty else {
                    await MainActor.run {
                        aiInsights = "⚠️ Please configure your API key in AI Analysis settings to generate insights."
                        isLoadingInsights = false
                    }
                    return
                }

                let insights = try await generateTrendInsights()
                await MainActor.run {
                    self.aiInsights = insights
                    self.isLoadingInsights = false
                    Haptics.success()
                }
            } catch {
                await MainActor.run {
                    self.aiInsights = "Failed to generate insights: \(error.localizedDescription)"
                    self.isLoadingInsights = false
                    Haptics.error()
                }
            }
        }
    }

    private func generateTrendInsights() async throws -> String {
        // Check if AI is configured
        let config = AIService.shared.getConfiguration()

        // If no API key, return local insights
        guard !config.apiKey.isEmpty else {
            return generateLocalInsights()
        }

        // Prepare data for AI analysis
        let measurementData = filtered.suffix(20).map { m -> String in
            let dateStr = ISO8601DateFormatter().string(from: m.date)
            if selectedType == .bloodPressure, let dia = m.diastolic {
                return "\(dateStr): \(Int(m.value))/\(Int(dia)) mmHg"
            } else {
                return "\(dateStr): \(m.value) \(selectedType.unit)"
            }
        }.joined(separator: "\n")

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

        let medInfo = medications.map { "\($0.name) (\($0.dose))" }.joined(separator: ", ")

        // Create analysis prompt
        let prompt = """
        Analyze the following \(selectedType.rawValue) measurements and provide health insights:

        Recent measurements:
        \(measurementData)

        \(medications.isEmpty ? "" : "Related medications: \(medInfo)")

        Current stats:
        - Latest: \(latestText())
        - Change: \(deltaText())
        - 7-day average: \(sevenDayAverageText())
        - In target range: \(sevenDayInRangeText())

        Please provide:
        1. Trend analysis (improving/stable/concerning)
        2. Key observations
        3. Actionable recommendations
        4. When to consult healthcare provider

        Keep the response concise (3-4 paragraphs) and patient-friendly.
        """

        do {
            let insights = try await callAIForInsights(prompt: prompt)
            return insights
        } catch {
            // Fallback to local insights if AI call fails
            return generateLocalInsights()
        }
    }

    private func callAIForInsights(prompt: String) async throws -> String {
        let config = AIService.shared.getConfiguration()

        switch config.provider {
        case .openai:
            return try await callOpenAIForInsights(prompt: prompt, apiKey: config.apiKey)
        case .anthropic:
            return try await callAnthropicForInsights(prompt: prompt, apiKey: config.apiKey)
        }
    }

    private func callOpenAIForInsights(prompt: String, apiKey: String) async throws -> String {
        let url = URL(string: "https://api.openai.com/v1/chat/completions")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "model": "gpt-4o-mini",
            "messages": [
                ["role": "system", "content": "You are a helpful medical assistant providing health insights. Be concise, supportive, and always recommend consulting healthcare providers for medical decisions."],
                ["role": "user", "content": prompt]
            ],
            "temperature": 0.7,
            "max_tokens": 500
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw AIServiceError.networkError("Failed to get insights")
        }

        struct OpenAIResponse: Codable {
            struct Choice: Codable {
                struct Message: Codable {
                    let content: String
                }
                let message: Message
            }
            let choices: [Choice]
        }

        let result = try JSONDecoder().decode(OpenAIResponse.self, from: data)
        return result.choices.first?.message.content ?? generateLocalInsights()
    }

    private func callAnthropicForInsights(prompt: String, apiKey: String) async throws -> String {
        let url = URL(string: "https://api.anthropic.com/v1/messages")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")

        let body: [String: Any] = [
            "model": "claude-3-5-haiku-20241022",
            "max_tokens": 500,
            "messages": [
                [
                    "role": "user",
                    "content": "You are a helpful medical assistant providing health insights. Be concise, supportive, and always recommend consulting healthcare providers for medical decisions.\n\n\(prompt)"
                ]
            ]
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw AIServiceError.networkError("Failed to get insights")
        }

        struct AnthropicResponse: Codable {
            struct Content: Codable {
                let text: String
            }
            let content: [Content]
        }

        let result = try JSONDecoder().decode(AnthropicResponse.self, from: data)
        return result.content.first?.text ?? generateLocalInsights()
    }

    private func generateLocalInsights() -> String {
        var insights = "📊 **\(selectedType.rawValue) Analysis**\n\n"

        // Trend analysis
        if filtered.count >= 3 {
            let recent3 = Array(filtered.prefix(3))
            let values = recent3.map { $0.value }
            let isIncreasing = zip(values, values.dropFirst()).allSatisfy { $0 < $1 }
            let isDecreasing = zip(values, values.dropFirst()).allSatisfy { $0 > $1 }

            if isIncreasing {
                insights += "📈 Your \(selectedType.rawValue.lowercased()) shows an **increasing trend**. "
            } else if isDecreasing {
                insights += "📉 Your \(selectedType.rawValue.lowercased()) shows a **decreasing trend**. "
            } else {
                insights += "➡️ Your \(selectedType.rawValue.lowercased()) is **relatively stable**. "
            }
        }

        insights += "\n\n"

        // Current stats
        insights += "**Recent Stats:**\n"
        insights += "• Latest reading: \(latestText())\n"
        insights += "• Change from previous: \(deltaText())\n"
        insights += "• 7-day average: \(sevenDayAverageText())\n"
        insights += "• Within target range: \(sevenDayInRangeText())\n\n"

        // Recommendations
        insights += "**Recommendations:**\n"
        insights += "• Continue regular monitoring for accurate trends\n"
        insights += "• Record measurements at consistent times\n"
        insights += "• Note any symptoms or activities in the notes field\n"

        if let trendWarning = DataValidator.analyzeTrend(measurements: filtered, type: selectedType) {
            insights += "\n\n⚠️ **Note:** \(trendWarning)"
        }

        return insights
    }
}

// MARK: - MeasurementType Extension
private extension MeasurementType {
    var systemImage: String {
        switch self {
        case .bloodPressure: return "heart.text.square.fill"
        case .bloodGlucose: return "drop.fill"
        case .weight: return "scalemass.fill"
        case .heartRate: return "waveform.path.ecg"
        }
    }
}

// MARK: - Data Point Picker
struct DataPointPickerView: View {
    let measurements: [Measurement]
    @Binding var selectedMeasurement: Measurement?
    let measurementType: MeasurementType
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                ForEach(measurements.reversed()) { measurement in
                    Button {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                            selectedMeasurement = measurement
                        }
                        Haptics.impact(.light)
                        dismiss()
                    } label: {
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(measurement.date, style: .date)
                                    .appFont(.subheadline)
                                    .foregroundStyle(.primary)
                                Text(measurement.date, style: .time)
                                    .appFont(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()

                            VStack(alignment: .trailing, spacing: 4) {
                                if measurement.type == .bloodPressure, let dia = measurement.diastolic {
                                    Text("\(Int(measurement.value))/\(Int(dia))")
                                        .appFont(.headline)
                                        .foregroundStyle(.primary)
                                    Text(measurement.type.unit)
                                        .appFont(.caption)
                                        .foregroundStyle(.secondary)
                                } else if measurement.type == .bloodGlucose {
                                    let v = UnitPreferences.mgdlToPreferred(measurement.value)
                                    let unit = UnitPreferences.glucoseUnit.rawValue
                                    let formatted = UnitPreferences.glucoseUnit == .mgdL ? String(format: "%.0f", v) : String(format: "%.1f", v)
                                    Text(formatted)
                                        .appFont(.headline)
                                        .foregroundStyle(.primary)
                                    Text(unit)
                                        .appFont(.caption)
                                        .foregroundStyle(.secondary)
                                } else {
                                    Text(String(format: "%.1f", measurement.value))
                                        .appFont(.headline)
                                        .foregroundStyle(.primary)
                                    Text(measurement.type.unit)
                                        .appFont(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }

                            if selectedMeasurement?.id == measurement.id {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.blue)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    .listRowBackground(
                        selectedMeasurement?.id == measurement.id ?
                        Color.blue.opacity(0.1) : Color.clear
                    )
                }
            }
            .navigationTitle("Select Data Point")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                if selectedMeasurement != nil {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Clear") {
                            withAnimation {
                                selectedMeasurement = nil
                            }
                            dismiss()
                        }
                    }
                }
            }
        }
    }
}

#Preview {
    EnhancedTrendsView()
        .environmentObject(DataStore())
}
