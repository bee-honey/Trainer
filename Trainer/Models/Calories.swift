import Foundation
import SwiftData

/// Calorie estimates for strength training.
///
/// Formula (Compendium of Physical Activities):
///   active kcal = (MET − 1) × 3.5 × body weight (kg) ÷ 200 × minutes
/// Subtracting 1 MET (resting) gives *active* calories, the same thing Apple Health
/// and Apple Watch report, so the two sources are comparable. When an Apple Watch
/// recorded active energy during the exercise, that measurement is used instead.
/// Either way it's an estimate: strength-training calories vary a lot between people.
enum CalorieEstimator {
    /// Used until the user logs a weight (Body tab or Apple Health).
    static let fallbackWeightKg = 75.0

    /// Compendium values: resistance training ~5 (vigorous, multiple exercises),
    /// ~6 with drop sets / sets to failure, core work ~3.8.
    static func met(for exercise: ProgramExercise?) -> Double {
        guard let exercise else { return 5.0 }
        if exercise.muscle.localizedCaseInsensitiveContains("abdominal") { return 3.8 }
        let intense = exercise.sets.contains {
            !$0.drops.isEmpty || $0.target.localizedCaseInsensitiveContains("failure")
        }
        return intense ? 6.0 : 5.0
    }

    static func activeKcal(met: Double, weightKg: Double, seconds: TimeInterval) -> Double {
        max(met - 1, 0) * 3.5 * weightKg / 200 * seconds / 60
    }

    /// Saved value for a stopped exercise; live formula estimate while it's running.
    static func kcal(for timing: ExerciseTiming, exercise: ProgramExercise?, weightKg: Double,
                     at now: Date = .now) -> Double {
        if !timing.isRunning, let saved = timing.kcal { return saved }
        return activeKcal(met: met(for: exercise), weightKg: weightKg, seconds: timing.elapsed(at: now))
    }

    static func format(_ kcal: Double) -> String { "~\(Int(kcal.rounded())) kcal" }
}

@MainActor
enum CalorieService {
    /// Latest body weight in kg from the Body tab or Apple Health, whichever is newer.
    static func bodyWeightKg(context: ModelContext, health: HealthManager) -> Double? {
        var descriptor = FetchDescriptor<BodyEntry>(predicate: #Predicate { $0.weightKg != nil },
                                                    sortBy: [SortDescriptor(\.date, order: .reverse)])
        descriptor.fetchLimit = 1
        let app = (try? context.fetch(descriptor))?.first
        let fromHealth = health.weights.first   // newest first
        switch (app, fromHealth) {
        case let (a?, h?): return a.date >= h.date ? a.weightKg : h.kg
        case let (a?, nil): return a.weightKg
        case let (nil, h?): return h.kg
        default: return nil
        }
    }

    /// Saves the final estimate when an exercise finishes: Apple Watch active energy if
    /// the Watch recorded any during the exercise, otherwise the formula.
    static func finalize(_ timing: ExerciseTiming, exercise: ProgramExercise?, weightKg: Double,
                         health: HealthManager, useHealth: Bool) async {
        timing.kcal = CalorieEstimator.activeKcal(met: CalorieEstimator.met(for: exercise),
                                                  weightKg: weightKg, seconds: timing.elapsed())
        timing.kcalFromWatch = false
        await applyWatchData(to: timing, health: health, useHealth: useHealth)
    }

    /// Watch data can reach the phone minutes after the workout. Re-check recent
    /// exercises that are still on the formula estimate.
    static func refine(_ timings: [ExerciseTiming], health: HealthManager, useHealth: Bool) async {
        guard useHealth else { return }
        let cutoff = Date.now.addingTimeInterval(-3 * 24 * 3600)
        for t in timings where t.finished && !t.isRunning && !t.kcalFromWatch && (t.lastStoppedAt ?? .distantPast) > cutoff {
            await applyWatchData(to: t, health: health, useHealth: useHealth)
        }
    }

    private static func applyWatchData(to timing: ExerciseTiming, health: HealthManager, useHealth: Bool) async {
        guard useHealth, let start = timing.firstStartedAt, let end = timing.lastStoppedAt,
              let watch = await health.watchActiveEnergy(from: start, to: end), watch > 0
        else { return }
        timing.kcal = watch
        timing.kcalFromWatch = true
    }
}
