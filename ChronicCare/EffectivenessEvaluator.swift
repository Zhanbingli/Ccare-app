import Foundation

struct MedicationEffectResult {
    enum Verdict: String { case likelyEffective, unclear, likelyIneffective, notApplicable }
    let verdict: Verdict
    let summary: String
    let samples: Int
    let confidence: Int // 0-100
}

extension DataStore {
    // Public API for views
    func effectiveness(for med: Medication, now: Date = Date()) -> MedicationEffectResult {
        guard let cat = med.category, cat != .unspecified else {
            return MedicationEffectResult(verdict: .notApplicable, summary: NSLocalizedString("No category", comment: ""), samples: 0, confidence: 0)
        }
        switch cat {
        case .antihypertensive:
            return evaluateBP(med: med, now: now)
        case .antidiabetic:
            return evaluateGlucose(med: med, now: now)
        case .unspecified:
            return MedicationEffectResult(verdict: .notApplicable, summary: NSLocalizedString("No category", comment: ""), samples: 0, confidence: 0)
        }
    }

    // MARK: - Settings
    private func settings() -> (bpDose: Double, bpMove: Double, gluDose: Double, gluMove: Double, minSamples: Int, adh: Double) {
        let d = UserDefaults.standard
        let mode = d.string(forKey: "eff.mode") ?? "balanced"
        let minSamples = d.object(forKey: "eff.minSamples") as? Int ?? 3
        let adh = d.object(forKey: "eff.adh") as? Double ?? 0.6
        switch mode {
        case "conservative":
            return (bpDose: 7, bpMove: 7, gluDose: 15, gluMove: 15, minSamples: minSamples, adh: adh)
        case "aggressive":
            return (bpDose: 3, bpMove: 3, gluDose: 7, gluMove: 7, minSamples: minSamples, adh: adh)
        default:
            return (bpDose: 5, bpMove: 5, gluDose: 10, gluMove: 10, minSamples: minSamples, adh: adh)
        }
    }

    // MARK: - BP evaluation
    private func evaluateBP(med: Medication, now: Date) -> MedicationEffectResult {
        let cal = Calendar.current
        let daysBack = 30
        let start = cal.date(byAdding: .day, value: -daysBack, to: now)!
        let medLogs = intakeLogs.filter { $0.medicationID == med.id && $0.status == .taken && $0.date >= start }
        guard !medLogs.isEmpty else {
            return MedicationEffectResult(verdict: .unclear, summary: NSLocalizedString("Insufficient data", comment: ""), samples: 0, confidence: 0)
        }

        // Pre/post windows: pre within 2h before, post within 1..6h after
        var deltasSys: [Double] = []
        var deltasDia: [Double] = []
        for log in medLogs {
            let preStart = log.date.addingTimeInterval(-2*3600)
            let preEnd = log.date
            let postStart = log.date.addingTimeInterval(1*3600)
            let postEnd = log.date.addingTimeInterval(6*3600)
            // nearest before (last in pre window)
            let pre = measurements
                .filter { $0.type == .bloodPressure && $0.date >= preStart && $0.date <= preEnd }
                .sorted(by: { $0.date < $1.date }).last
            // first after in post window
            let post = measurements
                .filter { $0.type == .bloodPressure && $0.date >= postStart && $0.date <= postEnd }
                .sorted(by: { $0.date < $1.date }).first
            if let pre, let post {
                deltasSys.append(post.value - pre.value)
                if let pD = pre.diastolic, let aD = post.diastolic { deltasDia.append(aD - pD) }
            }
        }

        func median(_ arr: [Double]) -> Double? {
            guard !arr.isEmpty else { return nil }
            let s = arr.sorted(); let n = s.count
            if n % 2 == 1 { return s[n/2] }
            return (s[n/2-1] + s[n/2]) / 2.0
        }
        let medSys = median(deltasSys) ?? 0
        let medDia = median(deltasDia) ?? 0

        // Moving average delta: last 14d vs previous 14d (systolic)
        let last14Start = cal.date(byAdding: .day, value: -14, to: now)!
        let prev14Start = cal.date(byAdding: .day, value: -28, to: now)!
        let last14 = measurements.filter { $0.type == .bloodPressure && $0.date >= last14Start && $0.date <= now }
        let prev14 = measurements.filter { $0.type == .bloodPressure && $0.date >= prev14Start && $0.date < last14Start }
        func avgSys(_ list: [Measurement]) -> Double? { guard !list.isEmpty else { return nil }; return list.map{$0.value}.reduce(0,+)/Double(list.count) }
        let avgDelta = (avgSys(last14) ?? 0) - (avgSys(prev14) ?? 0)

        // Adherence 7d avg
        let weekly = weeklyAdherence(for: med.id)
        let adh = weekly.map { $0.1 }.reduce(0, +) / Double(max(1, weekly.count))

        let cfg = settings()

        // Verdict rules (negative deltas are improvements)
        let improvedByDose = medSys <= -cfg.bpDose || medDia <= -max(3, cfg.bpDose/2)
        let improvedMoving = avgDelta <= -cfg.bpMove
        let goodAdh = adh >= cfg.adh
        let samples = deltasSys.count
        let minSamples = cfg.minSamples
        let verdict: MedicationEffectResult.Verdict
        if samples >= minSamples && (improvedByDose || improvedMoving) && goodAdh { verdict = .likelyEffective }
        else if samples < minSamples && !improvedMoving { verdict = .unclear }
        else if (improvedByDose || improvedMoving) { verdict = .likelyEffective }
        else { verdict = .likelyIneffective }
        // Confidence
        func clip01(_ x: Double) -> Double { max(0, min(1, x)) }
        let doseScore = clip01(max(0, -medSys) / cfg.bpDose)
        let moveScore = clip01(max(0, -avgDelta) / cfg.bpMove)
        let sampleScore = clip01(Double(samples) / Double(max(1, minSamples)))
        let adhFactor = goodAdh ? 1.0 : 0.8
        let conf = Int(round(100.0 * 0.5 * (doseScore + moveScore) * sampleScore * adhFactor))
        let summary = String(format: NSLocalizedString("BP Δ: %.0f/%.0f, 14d Δ: %.0f • Confidence: %d%%", comment: ""), medSys, medDia, avgDelta, conf)
        return MedicationEffectResult(verdict: verdict, summary: summary, samples: samples, confidence: smoothConfidence(raw: 0.5 * (max(0, -medSys) / cfg.bpDose + max(0, -avgDelta) / cfg.bpMove), samples: samples, threshold: cfg.minSamples))
    }

    private func smoothConfidence(raw: Double, samples: Int, threshold: Int) -> Int {
        let base = max(0, min(1, raw))
        let sampleFactor = min(1, Double(samples) / Double(max(1, threshold)))
        let smooth = 0.6 * base + 0.4 * sampleFactor
        return Int(round(smooth * 100))
    }

    // MARK: - Glucose evaluation
    private func evaluateGlucose(med: Medication, now: Date) -> MedicationEffectResult {
        let cal = Calendar.current
        let daysBack = 30
        let start = cal.date(byAdding: .day, value: -daysBack, to: now)!
        let medLogs = intakeLogs.filter { $0.medicationID == med.id && $0.status == .taken && $0.date >= start }
        guard !medLogs.isEmpty else {
            return MedicationEffectResult(verdict: .unclear, summary: NSLocalizedString("Insufficient data", comment: ""), samples: 0, confidence: 0)
        }

        // Pre/post windows for glucose: pre within 1h, post within 1..3h
        var deltas: [Double] = []
        for log in medLogs {
            let preStart = log.date.addingTimeInterval(-1*3600)
            let preEnd = log.date
            let postStart = log.date.addingTimeInterval(1*3600)
            let postEnd = log.date.addingTimeInterval(3*3600)
            let pre = measurements
                .filter { $0.type == .bloodGlucose && $0.date >= preStart && $0.date <= preEnd }
                .sorted(by: { $0.date < $1.date }).last
            let post = measurements
                .filter { $0.type == .bloodGlucose && $0.date >= postStart && $0.date <= postEnd }
                .sorted(by: { $0.date < $1.date }).first
            if let pre, let post {
                deltas.append(post.value - pre.value)
            }
        }
        func median(_ arr: [Double]) -> Double? {
            guard !arr.isEmpty else { return nil }
            let s = arr.sorted(); let n = s.count
            if n % 2 == 1 { return s[n/2] }
            return (s[n/2-1] + s[n/2]) / 2.0
        }
        let medDelta = median(deltas) ?? 0

        // Moving average delta 14d vs prior 14d
        let last14Start = cal.date(byAdding: .day, value: -14, to: now)!
        let prev14Start = cal.date(byAdding: .day, value: -28, to: now)!
        let last14 = measurements.filter { $0.type == .bloodGlucose && $0.date >= last14Start && $0.date <= now }
        let prev14 = measurements.filter { $0.type == .bloodGlucose && $0.date >= prev14Start && $0.date < last14Start }
        func avg(_ list: [Measurement]) -> Double? { guard !list.isEmpty else { return nil }; return list.map{$0.value}.reduce(0,+)/Double(list.count) }
        let avgDelta = (avg(last14) ?? 0) - (avg(prev14) ?? 0)

        let weekly = weeklyAdherence(for: med.id)
        let adh = weekly.map { $0.1 }.reduce(0, +) / Double(max(1, weekly.count))
        let cfg = settings()
        let improvedByDose = medDelta <= -cfg.gluDose
        let improvedMoving = avgDelta <= -cfg.gluMove
        let goodAdh = adh >= cfg.adh
        let samples = deltas.count
        let minSamples = cfg.minSamples
        let verdict: MedicationEffectResult.Verdict
        if samples >= minSamples && (improvedByDose || improvedMoving) && goodAdh { verdict = .likelyEffective }
        else if samples < minSamples && !improvedMoving { verdict = .unclear }
        else if (improvedByDose || improvedMoving) { verdict = .likelyEffective }
        else { verdict = .likelyIneffective }
        func clip01(_ x: Double) -> Double { max(0, min(1, x)) }
        let doseScore = clip01(max(0, -medDelta) / cfg.gluDose)
        let moveScore = clip01(max(0, -avgDelta) / cfg.gluMove)
        let sampleScore = clip01(Double(samples) / Double(max(1, minSamples)))
        let adhFactor = goodAdh ? 1.0 : 0.8
        let conf = Int(round(100.0 * 0.5 * (doseScore + moveScore) * sampleScore * adhFactor))
        let summary = String(format: NSLocalizedString("Glucose Δ: %.0f, 14d Δ: %.0f • Confidence: %d%%", comment: ""), medDelta, avgDelta, conf)
        return MedicationEffectResult(verdict: verdict, summary: summary, samples: samples, confidence: conf)
    }
}