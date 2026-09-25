import SwiftData
import SwiftUI

/// Workouts tab: edit the program's workouts and the exercise library.
struct ProgramView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Workout.order) private var workouts: [Workout]
    @Query(sort: \Exercise.name) private var exercises: [Exercise]
    @State private var search = ""
    @State private var newExercise: Exercise?
    @State private var confirmReset = false

    private var filtered: [Exercise] {
        search.isEmpty ? exercises : exercises.filter {
            $0.name.localizedCaseInsensitiveContains(search) || $0.muscle.localizedCaseInsensitiveContains(search)
                || $0.tags.contains { $0.localizedCaseInsensitiveContains(search) }
        }
    }

    var body: some View {
        NavigationStack {
            List {
                if search.isEmpty {
                    Section {
                        ForEach(workouts) { workout in
                            NavigationLink(value: workout) { WorkoutRow(workout: workout) }
                        }
                    } header: {
                        Text("Workouts")
                    } footer: {
                        Text("Each workout repeats on its scheduled days, so a change applies to every week.")
                    }
                }
                Section("Exercise library · \(filtered.count)") {
                    ForEach(filtered) { exercise in
                        NavigationLink(value: exercise) { ExerciseRow(exercise: exercise) }
                    }
                }
            }
            .searchable(text: $search, prompt: "Search exercises")
            .navigationTitle("Workouts")
            .navigationDestination(for: Workout.self) { WorkoutEditorView(workout: $0) }
            .navigationDestination(for: Exercise.self) { ExerciseEditorView(exercise: $0) }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Menu {
                        Button("New exercise", systemImage: "plus", action: createExercise)
                        Divider()
                        Button("Reset to default program", systemImage: "arrow.counterclockwise", role: .destructive) {
                            confirmReset = true
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) { SettingsButton() }
            }
            .sheet(item: $newExercise) { exercise in
                NavigationStack { ExerciseEditorView(exercise: exercise, isNew: true) }
            }
            .confirmationDialog("Reset to the default program?", isPresented: $confirmReset, titleVisibility: .visible) {
                Button("Reset program", role: .destructive) { ProgramSeeder.resetToDefaults(modelContext) }
            } message: {
                Text("This brings back the original 8 workouts and their exercises, and undoes your edits to them. Your custom exercises, workout history and body check-ins are kept.")
            }
        }
    }

    private func createExercise() {
        let e = Exercise()
        e.defaultSets = Array(repeating: .standard(rest: e.defaultRest), count: 3)
        modelContext.insert(e)
        newExercise = e
    }
}

private struct WorkoutRow: View {
    let workout: Workout

    var body: some View {
        let category = WorkoutCategory(title: workout.title)
        let count = workout.items?.count ?? 0
        HStack(spacing: 12) {
            Image(systemName: category.symbol)
                .font(.title3)
                .foregroundStyle(category.color)
                .frame(width: 32)
            VStack(alignment: .leading, spacing: 2) {
                Text(workout.title)
                Text("\(count) exercise\(count == 1 ? "" : "s") · Day\(workout.dayNumbers.count == 1 ? "" : "s") \(workout.dayNumbers.sorted().map(String.init).joined(separator: ", "))")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}
