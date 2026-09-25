import Foundation
import SwiftData

/// How long one exercise took on a given date. Time accumulates across
/// pause/resume so a mid-exercise break can be excluded.
@Model
final class ExerciseTiming {
    var dateKey: String = ""
    var itemKey: String = ""
    var exerciseKey: String = ""
    var exerciseIndex: Int = 0        // legacy; used only to migrate old timings
    var exerciseName: String = ""
    var accumulated: Double = 0
    var runningSince: Date?
    var firstStartedAt: Date?
    var lastStoppedAt: Date?
    var finished = false
    var kcal: Double?                 // final estimate, saved when the exercise finishes
    var kcalFromWatch = false         // true when it came from Apple Watch active energy

    init(dateKey: String, itemKey: String, exerciseKey: String, exerciseName: String) {
        self.dateKey = dateKey
        self.itemKey = itemKey
        self.exerciseKey = exerciseKey
        self.exerciseName = exerciseName
    }

    var isRunning: Bool { runningSince != nil }

    func elapsed(at now: Date = .now) -> TimeInterval {
        accumulated + (runningSince.map { now.timeIntervalSince($0) } ?? 0)
    }

    fileprivate func start(at now: Date) {
        guard runningSince == nil else { return }
        runningSince = now
        firstStartedAt = firstStartedAt ?? now
        finished = false
    }

    fileprivate func pause(at now: Date) {
        guard let since = runningSince else { return }
        accumulated += now.timeIntervalSince(since)
        runningSince = nil
        lastStoppedAt = now
    }
}

/// Rules: only one exercise runs at a time; checking a set starts its exercise's
/// timer if you forgot; checking the last planned set stops it.
enum ExerciseClock {
    static func start(dateKey: String, exercise: ProgramExercise, in context: ModelContext) {
        let now = Date.now
        for other in timings(dateKey: dateKey, in: context) where other.itemKey != exercise.key {
            other.pause(at: now)
        }
        timing(dateKey: dateKey, exercise: exercise, in: context).start(at: now)
    }

    static func pause(_ timing: ExerciseTiming) {
        timing.pause(at: .now)
    }

    static func finish(_ timing: ExerciseTiming) {
        timing.pause(at: .now)
        timing.finished = true
    }

    static func reset(_ timing: ExerciseTiming, in context: ModelContext) {
        context.delete(timing)
    }

    static func setCompleted(dateKey: String, exercise: ProgramExercise, exerciseDone: Bool, in context: ModelContext) {
        let existing = timings(dateKey: dateKey, in: context).first { $0.itemKey == exercise.key }
        if exerciseDone {
            if let existing, existing.firstStartedAt != nil { finish(existing) }
        } else if existing?.isRunning != true {
            start(dateKey: dateKey, exercise: exercise, in: context)
        }
    }

    /// Wall-clock span of the whole workout: first start → now (or last stop).
    static func workoutDuration(_ timings: [ExerciseTiming], at now: Date = .now) -> TimeInterval? {
        guard let start = timings.compactMap(\.firstStartedAt).min() else { return nil }
        let end = timings.contains(where: \.isRunning) ? now : (timings.compactMap(\.lastStoppedAt).max() ?? now)
        return end.timeIntervalSince(start)
    }

    private static func timings(dateKey: String, in context: ModelContext) -> [ExerciseTiming] {
        (try? context.fetch(FetchDescriptor<ExerciseTiming>(predicate: #Predicate { $0.dateKey == dateKey }))) ?? []
    }

    private static func timing(dateKey: String, exercise: ProgramExercise, in context: ModelContext) -> ExerciseTiming {
        if let existing = timings(dateKey: dateKey, in: context).first(where: { $0.itemKey == exercise.key }) {
            return existing
        }
        let t = ExerciseTiming(dateKey: dateKey, itemKey: exercise.key, exerciseKey: exercise.exerciseKey,
                               exerciseName: exercise.name)
        context.insert(t)
        return t
    }
}

extension TimeInterval {
    /// 75 -> "1:15", 3725 -> "1:02:05"
    var clockString: String {
        let s = Int(self.rounded(.down))
        return s >= 3600
            ? String(format: "%d:%02d:%02d", s / 3600, s / 60 % 60, s % 60)
            : String(format: "%d:%02d", s / 60, s % 60)
    }
}
