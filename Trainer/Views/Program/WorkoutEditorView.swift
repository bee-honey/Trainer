import SwiftData
import SwiftUI

/// Rename a workout, and add, remove, reorder or re-set its exercises.
/// Applies to every program day that uses this workout.
struct WorkoutEditorView: View {
    @Bindable var workout: Workout
    @Environment(\.modelContext) private var modelContext
    @State private var picking = false

    var body: some View {
        List {
            Section("Name") {
                TextField("Workout name", text: $workout.title)
            }
            Section {
                ForEach(workout.sortedItems) { item in
                    NavigationLink {
                        WorkoutItemEditor(item: item)
                    } label: {
                        WorkoutItemRow(item: item)
                    }
                }
                .onDelete(perform: delete)
                .onMove(perform: move)

                Button { picking = true } label: {
                    Label("Add exercise", systemImage: "plus.circle.fill")
                }
            } header: {
                Text("Exercises")
            } footer: {
                Text(scheduleText)
            }
        }
        .navigationTitle(workout.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { EditButton() }
        .sheet(isPresented: $picking) { ExercisePicker(onPick: add) }
        .onChange(of: workout.title) { touch() }
    }

    private var scheduleText: String {
        let days = workout.dayNumbers.sorted()
        guard !days.isEmpty else { return "Not scheduled on any program day." }
        return "Scheduled on program day\(days.count == 1 ? "" : "s") \(days.map(String.init).joined(separator: ", ")). Changes apply to all of them. Past logs stay in your history."
    }

    private func touch() { workout.updatedAt = .now }

    private func delete(_ offsets: IndexSet) {
        let items = workout.sortedItems
        for i in offsets { modelContext.delete(items[i]) }
        renumber(items.enumerated().filter { !offsets.contains($0.offset) }.map(\.element))
    }

    private func move(_ from: IndexSet, _ to: Int) {
        var items = workout.sortedItems
        items.move(fromOffsets: from, toOffset: to)
        renumber(items)
    }

    private func renumber(_ items: [WorkoutItem]) {
        for (i, item) in items.enumerated() { item.order = i }
        touch()
        try? modelContext.save()
    }

    private func add(_ exercise: Exercise) {
        let sets = exercise.defaultSets.isEmpty
            ? Array(repeating: ProgramSet.standard(rest: exercise.defaultRest), count: 3)
            : exercise.defaultSets
        let item = WorkoutItem(order: (workout.sortedItems.last?.order ?? -1) + 1, sets: sets)
        modelContext.insert(item)
        item.workout = workout
        item.exercise = exercise
        touch()
        try? modelContext.save()
    }
}

/// The sets for one exercise in one workout.
struct WorkoutItemEditor: View {
    let item: WorkoutItem
    @State private var sets: [ProgramSet] = []
    @State private var loaded = false

    var body: some View {
        Form {
            if let exercise = item.exercise {
                Section {
                    ExerciseRow(exercise: exercise)
                    NavigationLink("Edit exercise details") { ExerciseEditorView(exercise: exercise) }
                } footer: {
                    Text("Name, photos, tags and tip are shared by every workout that uses this exercise.")
                }
            }
            SetsEditor(sets: $sets, defaultRest: item.exercise?.defaultRest ?? 60, title: "Sets in this workout",
                       footer: "Rest is the break after a set. For a drop set, you go straight into the drops and rest after the last one.")
            if let defaults = item.exercise?.defaultSets, !defaults.isEmpty, defaults != sets {
                Section {
                    Button("Use the exercise's default sets") { sets = defaults }
                }
            }
        }
        .navigationTitle(item.exercise?.name ?? "Exercise")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { EditButton() }
        .onAppear {
            guard !loaded else { return }
            loaded = true
            sets = item.sets
        }
        .onChange(of: sets) { _, new in
            guard new != item.sets else { return }
            item.sets = new
            item.workout?.updatedAt = .now
        }
    }
}

/// Choose an exercise from the library, or create a new one.
struct ExercisePicker: View {
    let onPick: (Exercise) -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Exercise.name) private var exercises: [Exercise]
    @State private var search = ""
    @State private var newExercise: Exercise?

    private var filtered: [Exercise] {
        search.isEmpty ? exercises : exercises.filter {
            $0.name.localizedCaseInsensitiveContains(search) || $0.muscle.localizedCaseInsensitiveContains(search)
                || $0.tags.contains { $0.localizedCaseInsensitiveContains(search) }
        }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button {
                        let e = Exercise(name: search)
                        e.defaultSets = Array(repeating: .standard(rest: e.defaultRest), count: 3)
                        modelContext.insert(e)
                        newExercise = e
                    } label: {
                        Label("Create new exercise", systemImage: "plus.circle.fill")
                    }
                }
                Section("Library") {
                    ForEach(filtered) { exercise in
                        Button {
                            onPick(exercise)
                            dismiss()
                        } label: {
                            ExerciseRow(exercise: exercise)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .searchable(text: $search, prompt: "Search by name, muscle or tag")
            .navigationTitle("Add exercise")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
            .navigationDestination(item: $newExercise) { exercise in
                ExerciseEditorView(exercise: exercise, isNew: true) { saved in
                    onPick(saved)
                    dismiss()
                }
            }
        }
    }
}

// MARK: - Rows

struct ExerciseRow: View {
    let exercise: Exercise

    var body: some View {
        HStack(spacing: 12) {
            Thumbnail(image: exercise.thumbnail)
            VStack(alignment: .leading, spacing: 2) {
                Text(exercise.name.isEmpty ? "Untitled exercise" : exercise.name).font(.body)
                Text([exercise.muscle, exercise.equipment].filter { !$0.isEmpty }.joined(separator: " · "))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            if exercise.isCustom {
                Text("Custom").font(.caption2.bold())
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(Color.accentColor.opacity(0.15), in: .capsule)
            }
        }
        .contentShape(.rect)
    }
}

private struct WorkoutItemRow: View {
    let item: WorkoutItem

    private var summary: String {
        let sets = item.sets
        let drops = sets.filter { !$0.drops.isEmpty }.count
        let rests = Set(sets.compactMap { $0.drops.last?.rest ?? $0.rest }.filter { $0 > 0 })
        var parts = ["\(sets.count) set\(sets.count == 1 ? "" : "s")"]
        if drops > 0 { parts.append("\(drops) drop") }
        if rests.count == 1, let r = rests.first { parts.append("\(SetRow.format(r)) rest") }
        return parts.joined(separator: " · ")
    }

    var body: some View {
        HStack(spacing: 12) {
            Thumbnail(image: item.exercise?.thumbnail)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.exercise?.name ?? "Missing exercise")
                Text(summary).font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

struct Thumbnail: View {
    let image: UIImage?

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                Image(systemName: "dumbbell").foregroundStyle(.secondary)
            }
        }
        .frame(width: 56, height: 40)
        .background(Color(.tertiarySystemFill))
        .clipShape(.rect(cornerRadius: 8))
    }
}
