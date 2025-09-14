import SwiftUI
import Charts

struct TrendsView: View {
    @EnvironmentObject var store: DataStore

    @State private var selectedType: MeasurementType = .bloodPressure
    @State private var rangeDays: Int = 30
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

    // Daily aggregated BP (median per day) to reduce clutter
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

    // X-axis marks to avoid overlapping labels: 7d=每2天, 30d=每7天, 90d=每30天
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
                VStack(spacing: 12) {
                    kpiHeader
                        .frame(maxWidth: .infinity)
                        .padding(.horizontal)
                    if filtered.isEmpty {
                        Text("No data in range")
                            .foregroundStyle(.secondary)
                            .padding()
                            .frame(maxWidth: .infinity, minHeight: 260)
                    } else {
                        chart
                            .padding(.horizontal)
                            .frame(height: 260)
                        effectivenessCard
                            .padding(.horizontal)
                    }
                }
                // content is pushed by safeAreaInset below
            }
            .safeAreaInset(edge: .top) {
                VStack(spacing: 8) {
                    pickerSection
                }
                .padding(.vertical, 8)
                .background(.thinMaterial)
                .overlay(Divider(), alignment: .bottom)
            }
            .navigationTitle("Trends")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    // MARK: - KPI Header
    private var kpiHeader: some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                (Text("Overview (") + Text(selectedType.rawValue).bold() + Text(")"))
                    .font(.title3)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: 12)], spacing: 12) {
                    kpiTile(title: "Latest", value: latestText())
                    kpiTile(title: "Change", value: deltaText())
                    kpiTile(title: "7d Avg", value: sevenDayAverageText())
                    kpiTile(title: "7d In‑Range", value: sevenDayInRangeText())
                }
            }
        }
    }

    private func kpiTile(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title3).fontWeight(.semibold)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .allowsTightening(true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func latestText() -> String {
        guard let last = filtered.last else { return "—" }
        let df = DateFormatter(); df.dateStyle = .short; df.timeStyle = .short
        switch selectedType {
        case .bloodPressure:
            if let d = last.diastolic { return "\(Int(last.value))/\(Int(d)) \(selectedType.unit)" }
            return "\(Int(last.value)) \(selectedType.unit)"
        default:
            return formattedValue(last.value)
        }
    }

    private func deltaText() -> String {
        guard filtered.count >= 2 else { return "—" }
        let last = filtered[filtered.count - 1]
        let prev = filtered[filtered.count - 2]
        switch selectedType {
        case .bloodPressure:
            let sDiff = Int(last.value - prev.value)
            if let d1 = last.diastolic, let d2 = prev.diastolic {
                let dDiff = Int(d1 - d2)
                return "Δ \(sDiff >= 0 ? "+" : "")\(sDiff)/\(dDiff >= 0 ? "+" : "")\(dDiff)"
            } else {
                return "Δ \(sDiff >= 0 ? "+" : "")\(sDiff)"
            }
        default:
            if selectedType == .bloodGlucose {
                let diffMg = last.value - prev.value
                let diff = UnitPreferences.mgdlToPreferred(diffMg)
                let sign = diff >= 0 ? "+" : ""
                let fmt = UnitPreferences.glucoseUnit == .mgdL ? "%.0f" : "%.1f"
                return "Δ \(sign)\(String(format: fmt, diff))"
            } else {
                let diff = last.value - prev.value
                let sign = diff >= 0 ? "+" : ""
                // one decimal for non‑BP
                return "Δ \(sign)\(String(format: "%.1f", diff))"
            }
        }
    }

    private func sevenDayAverageText() -> String {
        guard !sevenDaySlice.isEmpty else { return "—" }
        switch selectedType {
        case .bloodPressure:
            let sysAvg = sevenDaySlice.map { $0.value }.reduce(0, +) / Double(sevenDaySlice.count)
            let dias = sevenDaySlice.compactMap { $0.diastolic }
            if dias.isEmpty {
                return "\(Int(sysAvg)) \(selectedType.unit)"
            } else {
                let diaAvg = dias.reduce(0, +) / Double(dias.count)
                return "\(Int(sysAvg))/\(Int(diaAvg)) \(selectedType.unit)"
            }
        default:
            if selectedType == .bloodGlucose {
                let avgMg = sevenDaySlice.map { $0.value }.reduce(0, +) / Double(sevenDaySlice.count)
                let avg = UnitPreferences.mgdlToPreferred(avgMg)
                let unit = UnitPreferences.glucoseUnit.rawValue
                let fmt = UnitPreferences.glucoseUnit == .mgdL ? "%.0f %@" : "%.1f %@"
                return String(format: fmt, avg, unit)
            } else {
                let avg = sevenDaySlice.map { $0.value }.reduce(0, +) / Double(sevenDaySlice.count)
                return formattedValue(avg)
            }
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

    private func formattedValue(_ v: Double) -> String {
        switch selectedType {
        case .weight:
            return String(format: "%.1f %@", v, selectedType.unit)
        case .bloodGlucose:
            let val = UnitPreferences.mgdlToPreferred(v)
            let unit = UnitPreferences.glucoseUnit.rawValue
            let fmt = UnitPreferences.glucoseUnit == .mgdL ? "%.0f %@" : "%.1f %@"
            return String(format: fmt, val, unit)
        default:
            return String(format: "%.0f %@", v, selectedType.unit)
        }
    }

    private var pickerSection: some View {
        VStack(spacing: 8) {
            Picker("Type", selection: $selectedType) {
                ForEach(MeasurementType.allCases) { t in
                    Text(t.rawValue).tag(t)
                }
            }
            .pickerStyle(.segmented)
            .controlSize(.large)
            .padding(.horizontal)

            Picker("Range", selection: $rangeDays) {
                Text("7d").tag(7)
                Text("30d").tag(30)
                Text("90d").tag(90)
            }
            .pickerStyle(.segmented)
            .controlSize(.large)
            .padding(.horizontal)
        }
    }

    @ViewBuilder
    private var chart: some View {
        switch selectedType {
        case .bloodPressure:
            let start = Calendar.current.date(byAdding: .day, value: -rangeDays, to: Date())!
            let end = Date()
            let daily = bpDaily
            Chart {
                // Threshold lines (guides)
                let bp = store.bpThresholds()
                RuleMark(y: .value("Systolic High", bp.systolicHigh))
                    .lineStyle(.init(dash: [4, 4]))
                    .foregroundStyle(.red.opacity(0.6))
                RuleMark(y: .value("Diastolic High", bp.diastolicHigh))
                    .lineStyle(.init(dash: [4, 4]))
                    .foregroundStyle(.red.opacity(0.6))

                // Band between daily median diastolic and systolic (when both exist)
                ForEach(daily.compactMap { d -> (Date, Double, Double)? in
                    if let dia = d.diastolic { return (d.date, dia, d.systolic) }
                    return nil
                }, id: \.0) { item in
                    AreaMark(
                        x: .value("Date", item.0),
                        yStart: .value("Dia", item.1),
                        yEnd: .value("Sys", item.2)
                    )
                    .foregroundStyle(.indigo.opacity(0.15))
                }

                // Daily median lines
                ForEach(daily) { d in
                    LineMark(
                        x: .value("Date", d.date),
                        y: .value("Systolic", d.systolic)
                    )
                    .interpolationMethod(.monotone)
                    .foregroundStyle(by: .value("Series", NSLocalizedString("Systolic", comment: "")))
                }
                ForEach(daily.compactMap { d -> (Date, Double)? in
                    guard let dia = d.diastolic else { return nil }
                    return (d.date, dia)
                }, id: \.0) { item in
                    LineMark(
                        x: .value("Date", item.0),
                        y: .value("Diastolic", item.1)
                    )
                    .interpolationMethod(.monotone)
                    .foregroundStyle(by: .value("Series", NSLocalizedString("Diastolic", comment: "")))
                }
            }
            .chartYAxisLabel("mmHg")
            .chartLegend(position: .overlay, alignment: .topTrailing)
            .chartXScale(domain: start...end)
            .chartXAxis {
                AxisMarks(values: xAxisValues) { value in
                    AxisGridLine()
                    AxisTick()
                    AxisValueLabel {
                        if let date = value.as(Date.self) {
                            Text(date, format: .dateTime.month(.twoDigits).day(.twoDigits))
                                .font(.caption2)
                        }
                    }
                }
            }
            .chartYAxis { AxisMarks(position: .leading) }
            .chartPlotStyle { plot in
                plot
                    .background(Color(.secondarySystemBackground))
                    .mask(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
        case .bloodGlucose:
            lineChart(unit: UnitPreferences.glucoseUnit.rawValue)
        case .weight:
            lineChart(unit: "kg")
        case .heartRate:
            lineChart(unit: "bpm")
        }
    }

    // MARK: - Medication Effectiveness Summary
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
        if meds.isEmpty {
            Card {
                VStack(alignment: .leading, spacing: 8) {
                    Text(NSLocalizedString("Medication Effectiveness", comment: "")).font(.headline)
                    Text(NSLocalizedString("No categorized medications", comment: "")).font(.footnote).foregroundStyle(.secondary)
                }
            }
        } else {
        let results: [(Medication, MedicationEffectResult)] = meds.map { ($0, store.effectiveness(for: $0)) }
        let counts = (
            effective: results.filter { $0.1.verdict == .likelyEffective }.count,
            unclear: results.filter { $0.1.verdict == .unclear }.count,
            ineffective: results.filter { $0.1.verdict == .likelyIneffective }.count
        )
        Card {
            VStack(alignment: .leading, spacing: 10) {
                Text(NSLocalizedString("Medication Effectiveness", comment: "")).font(.headline)
                HStack(alignment: .top, spacing: 12) {
                    summaryTile(icon: "checkmark.circle.fill", tint: .green, title: "\(counts.effective) " + NSLocalizedString("Likely effective", comment: ""))
                    summaryTile(icon: "questionmark.circle", tint: .secondary, title: "\(counts.unclear) " + NSLocalizedString("Unclear", comment: ""))
                    summaryTile(icon: "xmark.octagon.fill", tint: .red, title: "\(counts.ineffective) " + NSLocalizedString("Likely ineffective", comment: ""))
                }
                
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(results.prefix(3), id: \.0.id) { pair in
                        let med = pair.0; let res = pair.1
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text(med.name).font(.subheadline)
                            Spacer()
                            Text(effectText(res)).font(.caption).foregroundStyle(effectColor(res))
                            if res.confidence > 0 {
                                Text(String(format: NSLocalizedString("Confidence: %d%%", comment: ""), res.confidence))
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        if !res.summary.isEmpty {
                            Text(res.summary).font(.caption2).foregroundStyle(.secondary)
                        }
                        Divider()
                    }
                }
            }
        }
        }
        } else {
            EmptyView()
        }
    }

    private func effectText(_ r: MedicationEffectResult) -> String {
        switch r.verdict {
        case .likelyEffective: return NSLocalizedString("Likely effective", comment: "")
        case .unclear: return NSLocalizedString("Unclear", comment: "")
        case .likelyIneffective: return NSLocalizedString("Likely ineffective", comment: "")
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

    // Compact KPI tile: icon above label, evenly spaced
    private func summaryTile(icon: String, tint: Color, title: String) -> some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(tint)
            Text(title)
                .font(.caption)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.9)
        }
        .frame(maxWidth: .infinity)
    }

    private func lineChart(unit: String) -> some View {
        let start = Calendar.current.date(byAdding: .day, value: -rangeDays, to: Date())!
        let end = Date()
        let normal = store.customGoalRange(for: selectedType) ?? selectedType.normalRange
        // Precompute display range outside Chart result builder to avoid '() as ChartContent' errors
        var displayRange: ClosedRange<Double>? = nil
        if let r = normal {
            if selectedType == .bloodGlucose {
                displayRange = UnitPreferences.mgdlToPreferred(r.lowerBound)...UnitPreferences.mgdlToPreferred(r.upperBound)
            } else {
                displayRange = r
            }
        }
        return Chart {
            // Normal band (when available and meaningful)
            if let rDisplay = displayRange { // weight has nil
                RectangleMark(
                    xStart: .value("Start", start),
                    xEnd: .value("End", end),
                    yStart: .value("Low", rDisplay.lowerBound),
                    yEnd: .value("High", rDisplay.upperBound)
                )
                .foregroundStyle(.green.opacity(0.12))
                RuleMark(y: .value("High", rDisplay.upperBound))
                    .lineStyle(.init(dash: [4,4]))
                    .foregroundStyle(.green.opacity(0.6))
                RuleMark(y: .value("Low", rDisplay.lowerBound))
                    .lineStyle(.init(dash: [4,4]))
                    .foregroundStyle(.green.opacity(0.6))
            }

            // Base line (convert for glucose)
            ForEach(filtered) { m in
                let yVal = (selectedType == .bloodGlucose) ? UnitPreferences.mgdlToPreferred(m.value) : m.value
                LineMark(
                    x: .value("Date", m.date),
                    y: .value("Value", yVal)
                )
                .interpolationMethod(.monotone)
                .foregroundStyle(selectedType.tint.opacity(0.95))
            }
            // Highlight abnormal points in red (use custom goals when available)
            ForEach(filtered.filter { m in
                switch selectedType {
                case .bloodPressure:
                    let th = store.bpThresholds()
                    if let d = m.diastolic { return !(m.value < th.systolicHigh && d < th.diastolicHigh) }
                    return !(m.value < th.systolicHigh)
                default:
                    let range = store.customGoalRange(for: selectedType) ?? selectedType.normalRange
                    if let r = range { return !r.contains(m.value) }
                    return false
                }
            }) { m in
                let yVal = (selectedType == .bloodGlucose) ? UnitPreferences.mgdlToPreferred(m.value) : m.value
                PointMark(
                    x: .value("Date", m.date),
                    y: .value("Value", yVal)
                )
                .symbol(.circle)
                .symbolSize(40)
                .foregroundStyle(Color.red)
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
                            .font(.caption2)
                    }
                }
            }
        }
        .chartYAxis { AxisMarks(position: .leading) }
        .chartPlotStyle { plot in
            plot
                .background(Color(.secondarySystemBackground))
                .mask(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .chartYAxisLabel(unit)
    }
}

#Preview {
    TrendsView().environmentObject(DataStore())
}
