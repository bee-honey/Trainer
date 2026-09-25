import PhotosUI
import SwiftData
import SwiftUI

/// Create or edit a library exercise. Changes to name, photos, tags and tip show up
/// in every workout that uses it; default sets only apply when it's added to a workout.
struct ExerciseEditorView: View {
    @Bindable var exercise: Exercise
    var isNew = false
    var onSave: ((Exercise) -> Void)?

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var sets: [ProgramSet] = []
    @State private var loaded = false
    @State private var pickerItems: [PhotosPickerItem] = []
    @State private var newTag = ""
    @State private var confirmDelete = false

    private static let muscles = ["Abdominals", "Biceps", "Calves", "Chest", "Forearms", "Glutes", "Hamstrings",
                                  "Lats", "Lower Back", "Middle Back", "Quadriceps", "Shoulders", "Traps", "Triceps"]
    private static let equipment = ["Barbell", "Body Only", "Cable", "Dumbbell", "E-Z Curl Bar", "Kettlebell",
                                    "Machine", "Resistance Band", "Smith Machine", "Other"]

    /// Anything the user can edit; a change marks the exercise as edited (wins iCloud conflicts).
    private var signature: String {
        [exercise.name, exercise.muscle, exercise.equipment, exercise.tagsText, exercise.tip,
         "\(exercise.defaultRest)", exercise.bundledImage ?? "", "\(exercise.photos?.count ?? 0)",
         "\(exercise.defaultSetsData?.hashValue ?? 0)"].joined(separator: "|")
    }

    var body: some View {
        form
            .navigationTitle(isNew ? "New exercise" : exercise.name)
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarBackButtonHidden(isNew)
            .interactiveDismissDisabled(isNew)
            .toolbar { toolbarContent }
            .onAppear(perform: load)
            .onChange(of: sets) { _, new in exercise.defaultSets = new }
            .onChange(of: signature) { exercise.updatedAt = .now }
            .onChange(of: pickerItems) { _, items in Task { await addPhotos(items) } }
            .confirmationDialog("Delete \(exercise.name)?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Delete", role: .destructive, action: deleteExercise)
            } message: {
                Text(deleteMessage)
            }
    }

    private var form: some View {
        Form {
            photosSection
            detailsSection
            tagsSection
            tipSection
            restSection
            SetsEditor(sets: $sets, defaultRest: exercise.defaultRest, title: "Default sets",
                       footer: "Used when you add this exercise to a workout. Workouts that already include it keep their own sets.")
            if !isNew {
                usedInSection
                Section {
                    Button("Delete exercise", role: .destructive) { confirmDelete = true }
                }
            }
        }
    }

    private var detailsSection: some View {
        Section("Details") {
            TextField("Name", text: $exercise.name)
            PresetField(label: "Muscle", text: $exercise.muscle, presets: Self.muscles)
            PresetField(label: "Equipment", text: $exercise.equipment, presets: Self.equipment)
        }
    }

    private var tipSection: some View {
        Section("Coach tip") {
            TextField("Setup, cues, tempo…", text: $exercise.tip, axis: .vertical)
                .lineLimit(3...8)
        }
    }

    private var usedInSection: some View {
        let titles = exercise.workoutTitles
        return Section("Used in") {
            if titles.isEmpty {
                Text("Not in any workout").foregroundStyle(.secondary)
            } else {
                ForEach(titles, id: \.self) { Text($0) }
            }
        }
    }

    @ToolbarContentBuilder private var toolbarContent: some ToolbarContent {
        if isNew {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") {
                    modelContext.delete(exercise)
                    dismiss()
                }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save", action: save)
                    .disabled(exercise.name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        } else {
            ToolbarItem(placement: .topBarTrailing) { EditButton() }
        }
    }

    private var deleteMessage: String {
        let count = exercise.items?.count ?? 0
        if count == 0 { return "This can't be undone." }
        return "It will be removed from \(count) workout\(count == 1 ? "" : "s"). Past logs stay in your history."
    }

    private func load() {
        guard !loaded else { return }
        loaded = true
        sets = exercise.defaultSets
    }

    private func save() {
        exercise.name = exercise.name.trimmingCharacters(in: .whitespaces)
        exercise.updatedAt = .now
        try? modelContext.save()
        onSave?(exercise)
        dismiss()
    }

    private var restLabel: String {
        exercise.defaultRest == 0 ? "None" : SetRow.format(exercise.defaultRest)
    }

    private var restSection: some View {
        Section {
            Stepper(value: $exercise.defaultRest, in: 0...600, step: 15) {
                HStack {
                    Text("Default rest")
                    Spacer()
                    Text(restLabel).monospacedDigit().foregroundStyle(.secondary)
                }
            }
            Button("Use for all default sets", action: applyDefaultRest)
                .disabled(sets.isEmpty)
        } footer: {
            Text("New sets start with this rest.")
        }
    }

    private func applyDefaultRest() {
        let rest = exercise.defaultRest
        sets = sets.map { s in
            var s = s
            if s.drops.isEmpty { s.rest = rest } else { s.drops[s.drops.count - 1].rest = rest }
            return s
        }
    }

    // MARK: Photos

    private var photosSection: some View {
        Section {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(exercise.photoRefs, id: \.self) { ref in
                        if let image = PhotoLoader.image(ref, in: modelContext) {
                            Image(uiImage: image)
                                .resizable()
                                .scaledToFill()
                                .frame(width: 120, height: 80)
                                .clipShape(.rect(cornerRadius: 10))
                                .overlay(alignment: .topTrailing) {
                                    Button { remove(ref) } label: {
                                        Image(systemName: "xmark.circle.fill")
                                            .symbolRenderingMode(.palette)
                                            .foregroundStyle(.white, .black.opacity(0.6))
                                            .font(.title3)
                                    }
                                    .buttonStyle(.borderless)
                                    .padding(4)
                                    .accessibilityLabel("Remove photo")
                                }
                        }
                    }
                    PhotosPicker(selection: $pickerItems, maxSelectionCount: 6, matching: .images) {
                        VStack(spacing: 6) {
                            Image(systemName: "photo.badge.plus").font(.title2)
                            Text("Add").font(.caption)
                        }
                        .frame(width: 80, height: 80)
                        .background(Color(.tertiarySystemFill), in: .rect(cornerRadius: 10))
                    }
                    .buttonStyle(.borderless)
                }
                .padding(.vertical, 4)
            }
        } header: {
            Text("Photos")
        } footer: {
            Text("Add screenshots or photos showing the movement. The first photo is the one shown in lists.")
        }
    }

    private func addPhotos(_ items: [PhotosPickerItem]) async {
        guard !items.isEmpty else { return }
        var next = (exercise.photos?.map(\.order).max() ?? -1) + 1
        for item in items {
            guard let raw = try? await item.loadTransferable(type: Data.self),
                  let data = PhotoLoader.prepared(raw) else { continue }
            let photo = ExercisePhoto(data: data, order: next)
            modelContext.insert(photo)
            photo.exercise = exercise
            next += 1
        }
        pickerItems = []
    }

    private func remove(_ ref: PhotoRef) {
        switch ref {
        case .bundled:
            exercise.bundledImage = nil
        case .stored(let id):
            if let photo = modelContext.model(for: id) as? ExercisePhoto { modelContext.delete(photo) }
        }
    }

    // MARK: Tags

    private var tagsSection: some View {
        Section {
            if !exercise.tags.isEmpty {
                FlowLayout(spacing: 8) {
                    ForEach(exercise.tags, id: \.self) { tag in
                        Button { exercise.tags.removeAll { $0 == tag } } label: {
                            HStack(spacing: 4) {
                                Text(tag)
                                Image(systemName: "xmark").font(.caption2.bold())
                            }
                            .font(.subheadline)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(Color.accentColor.opacity(0.15), in: .capsule)
                        }
                        .buttonStyle(.borderless)
                        .accessibilityLabel("Remove tag \(tag)")
                    }
                }
                .padding(.vertical, 4)
            }
            HStack {
                TextField("Add a tag", text: $newTag)
                    .onSubmit(addTag)
                    .submitLabel(.done)
                Button("Add", action: addTag)
                    .buttonStyle(.borderless)
                    .disabled(newTag.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        } header: {
            Text("Tags")
        } footer: {
            Text("For example: compound, warm-up, home, superset.")
        }
    }

    private func addTag() {
        let tag = newTag.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: " ")
        guard !tag.isEmpty, !exercise.tags.contains(tag) else { newTag = ""; return }
        exercise.tags.append(tag)
        newTag = ""
    }

    private func deleteExercise() {
        for item in exercise.items ?? [] {
            item.workout?.updatedAt = .now
            modelContext.delete(item)
        }
        modelContext.delete(exercise)
        try? modelContext.save()
        dismiss()
    }
}

/// Text field with a menu of common values.
private struct PresetField: View {
    let label: String
    @Binding var text: String
    let presets: [String]

    var body: some View {
        HStack {
            Text(label)
            TextField(label, text: $text).multilineTextAlignment(.trailing)
            Menu {
                ForEach(presets, id: \.self) { p in Button(p) { text = p } }
            } label: {
                Image(systemName: "chevron.up.chevron.down").font(.caption)
            }
            .buttonStyle(.borderless)
        }
    }
}

/// Wraps children onto new lines, like words in a paragraph.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(width: proposal.width ?? .infinity, subviews: subviews)
        return CGSize(width: proposal.width ?? rows.map(\.width).max() ?? 0,
                      height: rows.map(\.height).reduce(0, +) + spacing * CGFloat(max(rows.count - 1, 0)))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in arrange(width: bounds.width, subviews: subviews) {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += row.height + spacing
        }
    }

    private func arrange(width: CGFloat, subviews: Subviews) -> [(indices: [Int], width: CGFloat, height: CGFloat)] {
        var rows: [(indices: [Int], width: CGFloat, height: CGFloat)] = []
        var current: (indices: [Int], width: CGFloat, height: CGFloat) = ([], 0, 0)
        for (i, view) in subviews.enumerated() {
            let size = view.sizeThatFits(.unspecified)
            let needed = current.indices.isEmpty ? size.width : current.width + spacing + size.width
            if needed > width, !current.indices.isEmpty {
                rows.append(current)
                current = ([i], size.width, size.height)
            } else {
                current = (current.indices + [i], needed, max(current.height, size.height))
            }
        }
        if !current.indices.isEmpty { rows.append(current) }
        return rows
    }
}
