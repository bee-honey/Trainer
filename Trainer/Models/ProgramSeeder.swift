import Foundation
import SwiftData

/// Builds the default H.I.V.T. program from the bundled `program.json`, and keeps
/// the synced program consistent across devices.
enum ProgramSeeder {
    private struct SeedDay: Decodable {
        let day: Int
        let title: String
        let exercises: [SeedExercise]
    }

    private struct SeedExercise: Decodable {
        let name: String
        let muscle: String
        let equipment: String
        let tip: String?
        let sets: [ProgramSet]
        let image: String?
    }

    /// Everything the app needs at launch: default program, old-log migration, duplicate cleanup.
    static func prepare(_ context: ModelContext) {
        if ((try? context.fetchCount(FetchDescriptor<Workout>())) ?? 0) == 0 {
            // `distantPast` so a copy you've edited on another device always wins over this fresh one.
            seed(context, stamp: .distantPast)
        }
        dedupe(context)
        migrateLegacyLogs(context)
        try? context.save()
    }

    /// Deletes the workouts and default exercises and rebuilds the original program.
    /// Custom exercises stay in the library. Stamped `now` so the reset also wins on other devices.
    static func resetToDefaults(_ context: ModelContext) {
        for w in (try? context.fetch(FetchDescriptor<Workout>())) ?? [] { context.delete(w) }
        for e in (try? context.fetch(FetchDescriptor<Exercise>(predicate: #Predicate { !$0.isCustom }))) ?? [] {
            context.delete(e)
        }
        try? context.save()
        seed(context, stamp: .now)
        try? context.save()
    }

    private static func seed(_ context: ModelContext, stamp: Date) {
        guard let url = Bundle.main.url(forResource: "program", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let days = try? JSONDecoder().decode([SeedDay].self, from: data)
        else { return }

        // The PDF repeats 8 distinct workouts across the 35 days.
        var workouts: [(title: String, days: [Int], exercises: [SeedExercise])] = []
        for day in days {
            if let i = workouts.firstIndex(where: { $0.title == day.title }) {
                workouts[i].days.append(day.day)
            } else {
                workouts.append((day.title, [day.day], day.exercises))
            }
        }

        var library: [String: Exercise] = [:]
        for e in (try? context.fetch(FetchDescriptor<Exercise>())) ?? [] { library[e.key] = e }

        for (order, w) in workouts.enumerated() {
            let workoutKey = "default-" + slug(w.title)
            let workout = Workout(key: workoutKey, title: w.title, dayNumbers: w.days, order: order)
            workout.updatedAt = stamp
            context.insert(workout)

            for (i, s) in w.exercises.enumerated() {
                let exerciseKey = s.image ?? "ex-" + slug(s.name)
                let exercise = library[exerciseKey] ?? {
                    let e = Exercise(key: exerciseKey, name: s.name)
                    e.muscle = s.muscle
                    e.equipment = s.equipment
                    e.tip = s.tip ?? ""
                    e.bundledImage = s.image
                    e.defaultSets = s.sets
                    e.defaultRest = s.sets.first?.rest ?? 60
                    e.isCustom = false
                    e.updatedAt = stamp
                    context.insert(e)
                    library[exerciseKey] = e
                    return e
                }()
                // Deterministic keys so logs line up across devices that each seeded the program.
                let item = WorkoutItem(key: "\(workoutKey)-\(i)", order: i, sets: s.sets)
                context.insert(item)
                item.workout = workout
                item.exercise = exercise
            }
        }
    }

    /// The same record can exist twice after iCloud sync (e.g. a new phone seeds the
    /// defaults, then your edited program arrives). Keep the most recently edited copy.
    static func dedupe(_ context: ModelContext) {
        let exercises = (try? context.fetch(FetchDescriptor<Exercise>())) ?? []
        for group in Dictionary(grouping: exercises, by: \.key).values where group.count > 1 {
            let ranked = group.sorted { ($0.updatedAt, $0.photos?.count ?? 0) > ($1.updatedAt, $1.photos?.count ?? 0) }
            for loser in ranked.dropFirst() {
                for item in loser.items ?? [] { item.exercise = ranked[0] }
                context.delete(loser)
            }
        }
        let workouts = (try? context.fetch(FetchDescriptor<Workout>())) ?? []
        for group in Dictionary(grouping: workouts, by: \.key).values where group.count > 1 {
            for loser in group.sorted(by: { $0.updatedAt > $1.updatedAt }).dropFirst() {
                context.delete(loser)
            }
        }
        if context.hasChanges { try? context.save() }
    }

    /// Logs from before workouts were editable point at an exercise by position.
    /// Resolve that to the workout item's permanent key.
    private static func migrateLegacyLogs(_ context: ModelContext) {
        let logs = (try? context.fetch(FetchDescriptor<SetLog>(predicate: #Predicate { $0.itemKey == "" }))) ?? []
        let timings = (try? context.fetch(FetchDescriptor<ExerciseTiming>(predicate: #Predicate { $0.itemKey == "" }))) ?? []
        guard !logs.isEmpty || !timings.isEmpty else { return }

        let defaults = UserDefaults.standard
        let schedule = Schedule(
            startDate: Date(timeIntervalSince1970: defaults.double(forKey: SettingsKey.startDate)),
            repeats: defaults.object(forKey: SettingsKey.repeats) as? Bool ?? true,
            days: Program.days(from: (try? context.fetch(FetchDescriptor<Workout>())) ?? []))

        func exercise(dateKey: String, index: Int) -> ProgramExercise? {
            guard let date = dayFormatter.date(from: dateKey),
                  case .workout(let day) = schedule.plan(for: date),
                  day.exercises.indices.contains(index) else { return nil }
            return day.exercises[index]
        }
        for log in logs {
            guard let e = exercise(dateKey: log.dateKey, index: log.exerciseIndex) else { continue }
            log.itemKey = e.key
            log.exerciseKey = e.exerciseKey
        }
        for t in timings {
            guard let e = exercise(dateKey: t.dateKey, index: t.exerciseIndex) else { continue }
            t.itemKey = e.key
            t.exerciseKey = e.exerciseKey
        }
    }

    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar.current
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    static func slug(_ s: String) -> String {
        s.lowercased().replacingOccurrences(of: "[^a-z0-9]+", with: "-", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
    }
}
