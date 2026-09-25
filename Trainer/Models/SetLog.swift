import Foundation
import SwiftData

/// One logged row (a set or a drop) for a given calendar date.
/// Defaults on every attribute are required for iCloud (CloudKit) sync.
@Model
final class SetLog {
    var dateKey: String = ""
    var itemKey: String = ""          // WorkoutItem.key: survives reordering/removing exercises
    var exerciseKey: String = ""      // Exercise.key: links history across workouts and renames
    var exerciseIndex: Int = 0        // legacy (pre-editing) position; used only to migrate old logs
    var exerciseName: String = ""
    var setIndex: Int = 0
    var dropIndex: Int = 0
    var weight: Double = 0
    var reps: Int = 0
    var done: Bool = false
    var updatedAt: Date = Date.now

    init(dateKey: String, itemKey: String, exerciseKey: String, exerciseName: String, setIndex: Int, dropIndex: Int,
         weight: Double, reps: Int, done: Bool) {
        self.dateKey = dateKey
        self.itemKey = itemKey
        self.exerciseKey = exerciseKey
        self.exerciseName = exerciseName
        self.setIndex = setIndex
        self.dropIndex = dropIndex
        self.weight = weight
        self.reps = reps
        self.done = done
        self.updatedAt = .now
    }

    var rowID: String { "\(setIndex)-\(dropIndex)" }
}
