import Foundation
import HealthKit
import Observation

/// Read-only Apple Health access for body weight and step count.
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

    /// Shows the Health permission sheet (only the first time), then loads data.
    /// HealthKit never reveals whether read access was granted, so a denial just
    /// looks like "no data".
    func connect() async {
        guard isAvailable else { return }
        do {
            try await store.requestAuthorization(toShare: [], read: [bodyMass, stepCount])
            await refresh()
        } catch {
            errorMessage = error.localizedDescription
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
