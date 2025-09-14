import Foundation
import HealthKit

final class HealthKitManager: ObservableObject {
    static let shared = HealthKitManager()
    private init() {}

    private let healthStore = HKHealthStore()

    // MARK: - Types
    private var systolicType: HKQuantityType { HKObjectType.quantityType(forIdentifier: .bloodPressureSystolic)! }
    private var diastolicType: HKQuantityType { HKObjectType.quantityType(forIdentifier: .bloodPressureDiastolic)! }
    private var bpCorrelationType: HKCorrelationType { HKObjectType.correlationType(forIdentifier: .bloodPressure)! }
    private var glucoseType: HKQuantityType { HKObjectType.quantityType(forIdentifier: .bloodGlucose)! }
    private var heartRateType: HKQuantityType { HKObjectType.quantityType(forIdentifier: .heartRate)! }
    private var weightType: HKQuantityType { HKObjectType.quantityType(forIdentifier: .bodyMass)! }

    // MARK: - Authorization
    func requestAuthorization(completion: @escaping (Bool, Error?) -> Void) {
        guard HKHealthStore.isHealthDataAvailable() else { completion(false, nil); return }

        let read: Set<HKObjectType> = [
            systolicType, diastolicType, bpCorrelationType,
            glucoseType, heartRateType, weightType
        ]
        let write: Set<HKSampleType> = [
            systolicType, diastolicType, bpCorrelationType,
            glucoseType, heartRateType, weightType
        ]
        healthStore.requestAuthorization(toShare: write, read: read, completion: completion)
    }

    // MARK: - Fetch
    func fetchMeasurements(since startDate: Date, completion: @escaping ([Measurement]) -> Void) {
        var results: [Measurement] = []
        let group = DispatchGroup()

        // Blood Pressure via correlation
        group.enter()
        let bpPredicate = HKQuery.predicateForSamples(withStart: startDate, end: Date(), options: .strictStartDate)
        let bpQuery = HKSampleQuery(sampleType: bpCorrelationType, predicate: bpPredicate, limit: HKObjectQueryNoLimit, sortDescriptors: nil) { [weak self] _, samples, _ in
            guard let self = self else { group.leave(); return }
            if let correlations = samples as? [HKCorrelation] {
                for c in correlations {
                    let s = c.objects(for: systolicType).compactMap { $0 as? HKQuantitySample }.first
                    let d = c.objects(for: diastolicType).compactMap { $0 as? HKQuantitySample }.first
                    if let s, let d {
                        let sys = s.quantity.doubleValue(for: HKUnit.millimeterOfMercury())
                        let dia = d.quantity.doubleValue(for: HKUnit.millimeterOfMercury())
                        results.append(Measurement(type: .bloodPressure, value: sys, diastolic: dia, date: s.startDate, note: nil))
                    }
                }
            }
            group.leave()
        }
        healthStore.execute(bpQuery)

        // Single quantity types
        func fetchQuantity(_ type: HKQuantityType, unit: HKUnit, mType: MeasurementType) {
            group.enter()
            let predicate = HKQuery.predicateForSamples(withStart: startDate, end: Date(), options: .strictStartDate)
            let query = HKSampleQuery(sampleType: type, predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: nil) { _, samples, _ in
                if let list = samples as? [HKQuantitySample] {
                    for s in list {
                        let v = s.quantity.doubleValue(for: unit)
                        results.append(Measurement(type: mType, value: v, diastolic: nil, date: s.startDate, note: nil))
                    }
                }
                group.leave()
            }
            healthStore.execute(query)
        }

        fetchQuantity(glucoseType, unit: HKUnit(from: "mg/dL"), mType: .bloodGlucose)
        fetchQuantity(heartRateType, unit: HKUnit.count().unitDivided(by: HKUnit.minute()), mType: .heartRate)
        fetchQuantity(weightType, unit: HKUnit.gramUnit(with: .kilo), mType: .weight)

        group.notify(queue: .main) {
            // sort by date desc
            completion(results.sorted(by: { $0.date > $1.date }))
        }
    }

    // MARK: - Write
    func saveMeasurement(_ m: Measurement, completion: @escaping (Bool, Error?) -> Void) {
        guard HKHealthStore.isHealthDataAvailable() else { completion(false, nil); return }

        switch m.type {
        case .bloodPressure:
            let sys = HKQuantity(unit: .millimeterOfMercury(), doubleValue: m.value)
            let diaV = m.diastolic ?? 0
            let dia = HKQuantity(unit: .millimeterOfMercury(), doubleValue: diaV)
            let sysSample = HKQuantitySample(type: systolicType, quantity: sys, start: m.date, end: m.date)
            let diaSample = HKQuantitySample(type: diastolicType, quantity: dia, start: m.date, end: m.date)
            let corr = HKCorrelation(type: bpCorrelationType, start: m.date, end: m.date, objects: Set([sysSample, diaSample]))
            healthStore.save([sysSample, diaSample, corr]) { success, error in
                DispatchQueue.main.async { completion(success, error) }
            }
        case .bloodGlucose:
            let q = HKQuantity(unit: HKUnit(from: "mg/dL"), doubleValue: m.value)
            let sample = HKQuantitySample(type: glucoseType, quantity: q, start: m.date, end: m.date)
            healthStore.save(sample) { success, error in
                DispatchQueue.main.async { completion(success, error) }
            }
        case .heartRate:
            let unit = HKUnit.count().unitDivided(by: HKUnit.minute())
            let q = HKQuantity(unit: unit, doubleValue: m.value)
            let sample = HKQuantitySample(type: heartRateType, quantity: q, start: m.date, end: m.date)
            healthStore.save(sample) { success, error in
                DispatchQueue.main.async { completion(success, error) }
            }
        case .weight:
            let q = HKQuantity(unit: HKUnit.gramUnit(with: .kilo), doubleValue: m.value)
            let sample = HKQuantitySample(type: weightType, quantity: q, start: m.date, end: m.date)
            healthStore.save(sample) { success, error in
                DispatchQueue.main.async { completion(success, error) }
            }
        }
    }

    // MARK: - Authorization Status Helpers
    func isSharingAuthorized() -> Bool {
        guard HKHealthStore.isHealthDataAvailable() else { return false }
        let types: [HKObjectType] = [
            systolicType, diastolicType, bpCorrelationType,
            glucoseType, heartRateType, weightType
        ]
        return types.contains { healthStore.authorizationStatus(for: $0) == .sharingAuthorized }
    }
}
