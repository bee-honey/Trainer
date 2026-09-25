import Foundation
import HealthKit
import Observation

/// Read-only Apple Health access for body weight, step count, and active energy (Apple Watch).
@Observable
final class HealthManager {
    struct WeightSample: Identifiable {
        let id: UUID
        let date: Date
        let kg: Double
    }

    struct StepDay: Identifiable {
        var id: Date { date }
        let date: Date
        let steps: Int
    }

    let isAvailable = HKHealthStore.isHealthDataAvailable()
    private(set) var weights: [WeightSample] = []
    private(set) var stepDays: [StepDay] = []
    private(set) var errorMessage: String?

    var todaySteps: Int {
        stepDays.first { Calendar.current.isDateInToday($0.date) }?.steps ?? 0
    }

    private let store = HKHealthStore()
    private let bodyMass = HKQuantityType(.bodyMass)
    private let stepCount = HKQuantityType(.stepCount)
    private let activeEnergy = HKQuantityType(.activeEnergyBurned)
    private var readTypes: Set<HKObjectType> { [bodyMass, stepCount, activeEnergy] }

    /// Shows the Health permission sheet (only the first time), then loads data.
    /// HealthKit never reveals whether read access was granted, so a denial just
    /// looks like "no data".
    func connect() async {
        guard isAvailable else { return }
        do {
            try await store.requestAuthorization(toShare: [], read: readTypes)
            await refresh()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Asks again only for types added since the user last connected (e.g. active energy).
    func requestNewPermissionsIfNeeded() async {
        guard isAvailable,
              (try? await store.statusForAuthorizationRequest(toShare: [], read: readTypes)) == .shouldRequest
        else { return }
        try? await store.requestAuthorization(toShare: [], read: readTypes)
    }

    /// Active kcal recorded by an Apple Watch between two times, or nil if no Watch data.
    /// iPhone-only samples are ignored: a phone in a pocket barely registers lifting.
    /// Samples that straddle the window count in proportion to their overlap.
    func watchActiveEnergy(from start: Date, to end: Date) async -> Double? {
        guard isAvailable, end > start else { return nil }
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.quantitySample(type: activeEnergy,
                                         predicate: HKQuery.predicateForSamples(withStart: start, end: end))],
            sortDescriptors: [])
        guard let samples = try? await descriptor.result(for: store) else { return nil }
        let watch = samples.filter {
            $0.device?.model == "Watch" || $0.sourceRevision.productType?.hasPrefix("Watch") == true
        }
        guard !watch.isEmpty else { return nil }
        return watch.reduce(0) { total, s in
            let span = s.endDate.timeIntervalSince(s.startDate)
            let overlap = min(end, s.endDate).timeIntervalSince(max(start, s.startDate))
            let fraction = span > 0 ? max(0, min(1, overlap / span)) : 1
            return total + s.quantity.doubleValue(for: .kilocalorie()) * fraction
        }
    }

    func refresh() async {
        guard isAvailable else { return }
        do {
            async let w = fetchWeights()
            async let s = fetchSteps()
            (weights, stepDays) = try await (w, s)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func fetchWeights() async throws -> [WeightSample] {
        let start = Calendar.current.date(byAdding: .year, value: -1, to: .now)
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.quantitySample(type: bodyMass,
                                         predicate: HKQuery.predicateForSamples(withStart: start, end: nil))],
            sortDescriptors: [SortDescriptor(\.endDate, order: .reverse)],
            limit: 500)
        return try await descriptor.result(for: store).map {
            WeightSample(id: $0.uuid, date: $0.endDate, kg: $0.quantity.doubleValue(for: .gramUnit(with: .kilo)))
        }
    }

    private func fetchSteps() async throws -> [StepDay] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        let start = calendar.date(byAdding: .day, value: -6, to: today)!
        let descriptor = HKStatisticsCollectionQueryDescriptor(
            predicate: .quantitySample(type: stepCount,
                                       predicate: HKQuery.predicateForSamples(withStart: start, end: nil)),
            options: .cumulativeSum,
            anchorDate: today,
            intervalComponents: DateComponents(day: 1))
        let collection = try await descriptor.result(for: store)
        var days: [StepDay] = []
        collection.enumerateStatistics(from: start, to: .now) { stats, _ in
            days.append(StepDay(date: stats.startDate,
                                steps: Int(stats.sumQuantity()?.doubleValue(for: .count()) ?? 0)))
        }
        return days
    }
}
