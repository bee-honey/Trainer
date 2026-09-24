import Foundation
import SwiftData

/// One logged row (a set or a drop) for a given calendar date.
@Model
final class SetLog {
    var dateKey: String
    var exerciseIndex: Int
    var exerciseName: String
    var setIndex: Int
    var dropIndex: Int
    var weight: Double
    var reps: Int
    var done: Bool
    var updatedAt: Date

    init(dateKey: String, exerciseIndex: Int, exerciseName: String, setIndex: Int, dropIndex: Int,
         weight: Double, reps: Int, done: Bool) {
        self.dateKey = dateKey
        self.exerciseIndex = exerciseIndex
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
