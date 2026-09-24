import Foundation
import SwiftUI

// MARK: - Program data (bundled from the H.I.V.T. PDF)

struct ProgramDrop: Codable, Hashable {
    let target: String
    let rest: Int?
}

struct ProgramSet: Codable, Hashable {
    let kind: String      // "Standard" or "Drop"
    let target: String    // e.g. "10 to 12 reps", "To failure"
    let rest: Int?        // seconds of rest after this set (nil = go straight into the drop)
    let drops: [ProgramDrop]
}

struct ProgramExercise: Codable, Hashable {
    let name: String
    let muscle: String
    let equipment: String
    let tip: String?
    let sets: [ProgramSet]
    let image: String?    // bundled start/end reference photo, cropped from the PDF

    var photo: UIImage? {
        image.flatMap { Bundle.main.path(forResource: $0, ofType: "jpg") }.flatMap(UIImage.init(contentsOfFile:))
    }

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

struct ProgramDay: Codable, Hashable {
    let day: Int
    let week: Int
    let title: String
    let exercises: [ProgramExercise]

    var totalRows: Int { exercises.reduce(0) { $0 + $1.rows.count } }
    var category: WorkoutCategory { WorkoutCategory(title: title) }
}

enum WorkoutCategory: String {
    case shoulders = "Shoulders", back = "Back", chest = "Chest", legs = "Legs", rest = "Rest"

    init(title: String) {
        let t = title.lowercased()
        if t.contains("shoulder") { self = .shoulders }
        else if t.contains("back") { self = .back }
        else if t.contains("chest") { self = .chest }
        else if t.contains("leg") { self = .legs }
        else { self = .rest }
    }

    var color: Color {
        switch self {
        case .shoulders: .orange
        case .back: .blue
        case .chest: .pink
        case .legs: .green
        case .rest: .gray
        }
    }

    var symbol: String {
        switch self {
        case .shoulders: "figure.arms.open"
        case .back: "figure.rower"
        case .chest: "figure.strengthtraining.traditional"
        case .legs: "figure.step.training"
        case .rest: "bed.double.fill"
        }
    }
}

enum Program {
    static let cycleLength = 35

    static let days: [Int: ProgramDay] = {
        guard let url = Bundle.main.url(forResource: "program", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let list = try? JSONDecoder().decode([ProgramDay].self, from: data)
        else { return [:] }
        return Dictionary(uniqueKeysWithValues: list.map { ($0.day, $0) })
    }()
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
        if let day = Program.days[n] { return .workout(day) }
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

enum SettingsKey {
    static let startDate = "programStartDate"
    static let repeats = "programRepeats"
    static let unit = "weightUnit"
}

extension Date {
    var dayKey: String {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: self)
        return String(format: "%04d-%02d-%02d", c.year!, c.month!, c.day!)
    }
}
