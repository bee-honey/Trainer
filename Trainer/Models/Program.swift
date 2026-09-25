import Foundation
import SwiftUI

import SwiftData

// MARK: - Set schemes (stored as JSON on exercises / workout items)

struct ProgramDrop: Codable, Hashable {
    var target: String
    var rest: Int?
}

struct ProgramSet: Codable, Hashable {
    var kind: String      // "Standard" or "Drop"
    var target: String    // e.g. "10 to 12 reps", "To failure"
    var rest: Int?        // seconds of rest after this set (nil = go straight into the drop)
    var drops: [ProgramDrop]

    static func standard(_ target: String = "10 reps", rest: Int) -> ProgramSet {
        ProgramSet(kind: "Standard", target: target, rest: rest, drops: [])
    }
}

// MARK: - Read-only snapshot the workout screens render (built from the SwiftData program)

enum PhotoRef: Hashable {
    case bundled(String)                 // default photo shipped in the app
    case stored(PersistentIdentifier)    // user-added photo (ExercisePhoto)
}

struct ProgramExercise: Hashable, Identifiable {
    let key: String           // WorkoutItem key: stable across edits, used by logs
    let exerciseKey: String   // Exercise key: shared by every workout that uses it
    let name: String
    let muscle: String
    let equipment: String
    let tags: [String]
    let tip: String?
    let sets: [ProgramSet]
    let photos: [PhotoRef]

    var id: String { key }

    /// Every loggable row: each set, followed by its drops.
    var rows: [SetRowSpec] {
        sets.enumerated().flatMap { i, set in
            [SetRowSpec(setIndex: i, dropIndex: 0, target: set.target, rest: set.rest, isDropSet: set.kind == "Drop")]
                + set.drops.enumerated().map { d, drop in
                    SetRowSpec(setIndex: i, dropIndex: d + 1, target: drop.target, rest: drop.rest, isDropSet: true)
                }
        }
    }
}

struct SetRowSpec: Hashable, Identifiable {
    let setIndex: Int
    let dropIndex: Int    // 0 = the set itself, 1... = drops
    let target: String
    let rest: Int?
    let isDropSet: Bool

    var id: String { "\(setIndex)-\(dropIndex)" }
    var label: String { dropIndex == 0 ? "Set \(setIndex + 1)" : "Drop \(dropIndex)" }

    /// First number in the target ("10 to 12 reps" -> 10), used to prefill reps.
    var suggestedReps: Int {
        let digits = target.prefix { !$0.isNumber }.count
        return Int(target.dropFirst(digits).prefix { $0.isNumber }) ?? 8
    }

    var isTimed: Bool { target.localizedCaseInsensitiveContains("sec") }
}

struct ProgramDay: Hashable {
    let day: Int
    let week: Int
    let title: String
    let exercises: [ProgramExercise]

    var totalRows: Int { exercises.reduce(0) { $0 + $1.rows.count } }
    var category: WorkoutCategory { WorkoutCategory(title: title) }
}

enum WorkoutCategory: String {
    case shoulders = "Shoulders", back = "Back", chest = "Chest", legs = "Legs", other = "Workout", rest = "Rest"

    init(title: String) {
        let t = title.lowercased()
        if t.contains("shoulder") { self = .shoulders }
        else if t.contains("back") { self = .back }
        else if t.contains("chest") { self = .chest }
        else if t.contains("leg") { self = .legs }
        else { self = .other }   // custom workout titles; rest days are set explicitly
    }

    var color: Color {
        switch self {
        case .shoulders: .orange
        case .back: .blue
        case .chest: .pink
        case .legs: .green
        case .other: .purple
        case .rest: .gray
        }
    }

    var symbol: String {
        switch self {
        case .shoulders: "figure.arms.open"
        case .back: "figure.rower"
        case .chest: "figure.strengthtraining.traditional"
        case .legs: "figure.step.training"
        case .other: "dumbbell.fill"
        case .rest: "bed.double.fill"
        }
    }
}

enum Program {
    static let cycleLength = 35

    /// Program day number → workout, from the user's (editable, iCloud-synced) workouts.
    static func days(from workouts: [Workout]) -> [Int: ProgramDay] {
        var out: [Int: ProgramDay] = [:]
        for workout in workouts {
            let exercises = workout.sortedItems.compactMap(ProgramExercise.init(item:))
            for d in workout.dayNumbers {
                out[d] = ProgramDay(day: d, week: (d - 1) / 7 + 1, title: workout.title, exercises: exercises)
            }
        }
        return out
    }
}

// MARK: - Mapping calendar dates to program days

enum DayPlan {
    case workout(ProgramDay)
    case rest(dayNumber: Int)
    case notScheduled
}

struct Schedule {
    var startDate: Date
    var repeats: Bool
    var days: [Int: ProgramDay] = [:]

    private var calendar: Calendar { .current }

    func programDayNumber(for date: Date) -> Int? {
        let diff = calendar.dateComponents([.day], from: calendar.startOfDay(for: startDate),
                                           to: calendar.startOfDay(for: date)).day ?? 0
        guard diff >= 0 else { return nil }
        if repeats { return diff % Program.cycleLength + 1 }
        return diff < Program.cycleLength ? diff + 1 : nil
    }

    func plan(for date: Date) -> DayPlan {
        guard let n = programDayNumber(for: date) else { return .notScheduled }
        if let day = days[n] { return .workout(day) }
        return .rest(dayNumber: n)
    }

    /// The next workout strictly after `date`, within one cycle.
    func nextWorkout(after date: Date) -> (Date, ProgramDay)? {
        for offset in 1...Program.cycleLength {
            guard let d = calendar.date(byAdding: .day, value: offset, to: date) else { continue }
            if case .workout(let day) = plan(for: d) { return (d, day) }
        }
        return nil
    }
}

// MARK: - Settings keys

enum AppInfo {
    /// Set in one place: the target's Display Name (INFOPLIST_KEY_CFBundleDisplayName).
    static let name = Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String ?? "Trainer"
}

enum SettingsKey {
    static let startDate = "programStartDate"
    static let repeats = "programRepeats"
    static let unit = "weightUnit"
    static let healthConnected = "healthConnected"
}

extension Date {
    var dayKey: String {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: self)
        return String(format: "%04d-%02d-%02d", c.year!, c.month!, c.day!)
    }
}
