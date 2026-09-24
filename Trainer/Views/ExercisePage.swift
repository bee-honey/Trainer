import SwiftData
import SwiftUI

/// One swipeable page: an exercise with every set as a quick-log row.
struct ExercisePage: View {
    let exercise: ProgramExercise
    let index: Int
    let count: Int
    let dateKey: String
    let logs: [SetLog]
    let timing: ExerciseTiming?
    let onNext: () -> Void

    @Environment(\.modelContext) private var modelContext
    @State private var previous: [String: SetLog] = [:]
    @State private var showTip = false
    @State private var showPhoto = false
    @State private var lastTime: TimeInterval?

    private var extraRows: [SetRowSpec] {
        logs.filter { $0.setIndex >= exercise.sets.count }
            .sorted { $0.setIndex < $1.setIndex }
            .map { SetRowSpec(setIndex: $0.setIndex, dropIndex: 0, target: "Extra set",
                              rest: 60, isDropSet: false) }
    }

    private var allRows: [SetRowSpec] { exercise.rows + extraRows }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                titleBlock
                timerBar
                if let photo = exercise.photo {
                    Button { showPhoto = true } label: {
                        Image(uiImage: photo)
                            .resizable()
                            .scaledToFit()
                            .clipShape(.rect(cornerRadius: 12))
                            .overlay(alignment: .bottomTrailing) {
                                Image(systemName: "arrow.up.left.and.arrow.down.right")
                                    .font(.caption.bold())
                                    .padding(6)
                                    .background(.ultraThinMaterial, in: .circle)
                                    .padding(8)
                            }
                    }
                    .buttonStyle(.plain)
                    .fullScreenCover(isPresented: $showPhoto) {
                        PhotoViewer(image: photo, title: exercise.name)
                    }
                }
                if let tip = exercise.tip {
                    DisclosureGroup(isExpanded: $showTip) {
                        Text(tip).font(.callout).frame(maxWidth: .infinity, alignment: .leading).padding(.top, 4)
                    } label: {
                        Label("Coach tip", systemImage: "lightbulb.fill").font(.subheadline.bold())
                    }
                    .tint(.primary)
                    .padding(12)
                    .background(Color.yellow.opacity(0.12), in: .rect(cornerRadius: 12))
                }

                VStack(spacing: 10) {
                    ForEach(allRows) { spec in
                        SetRow(spec: spec,
                               exerciseIndex: index,
                               exerciseName: exercise.name,
                               dateKey: dateKey,
                               log: logs.first { $0.rowID == spec.id },
                               previous: previous[spec.id],
                               suggestedWeight: suggestedWeight(for: spec),
                               isExtra: spec.setIndex >= exercise.sets.count,
                               onCompleted: { rowCompleted(spec) })
                    }
                }

                Button(action: addSet) {
                    Label("Add set", systemImage: "plus.circle")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)

                nextButton
            }
            .padding()
            .padding(.bottom, 80) // room for the rest-timer banner
        }
        .scrollDismissesKeyboard(.interactively)
        .onAppear(perform: loadPrevious)
    }

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("EXERCISE \(index + 1) OF \(count)")
                .font(.caption.bold()).foregroundStyle(.secondary)
            Text(exercise.name).font(.title2.bold())
            HStack(spacing: 8) {
                Tag(text: exercise.muscle, systemImage: "figure.strengthtraining.functional")
                Tag(text: exercise.equipment, systemImage: "dumbbell")
                Tag(text: "\(exercise.sets.count) sets", systemImage: "number")
            }
        }
    }

    private var timerBar: some View {
        HStack(spacing: 12) {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                Text((timing?.elapsed(at: context.date) ?? 0).clockString)
                    .font(.title2.bold().monospacedDigit())
                    .foregroundStyle(timing?.isRunning == true ? Color.accentColor : .primary)
                    .contentTransition(.numericText())
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(timerStatus).font(.caption.bold())
                if let lastTime {
                    Text("Last time \(lastTime.clockString)").font(.caption2).foregroundStyle(.secondary)
                }
            }
            Spacer()
            if let timing, timing.isRunning {
                Button { ExerciseClock.pause(timing) } label: { Image(systemName: "pause.fill") }
                    .buttonStyle(.bordered)
                Button { ExerciseClock.finish(timing) } label: { Image(systemName: "stop.fill") }
                    .buttonStyle(.bordered)
            } else {
                Button {
                    ExerciseClock.start(dateKey: dateKey, index: index, name: exercise.name, in: modelContext)
                } label: {
                    Label(timing == nil ? "Start" : "Resume", systemImage: "play.fill")
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(12)
        .background(Color(.secondarySystemBackground).opacity(0.6), in: .rect(cornerRadius: 14))
        .contextMenu {
            if let timing {
                Button("Reset timer", systemImage: "arrow.counterclockwise", role: .destructive) {
                    ExerciseClock.reset(timing, in: modelContext)
                }
            }
        }
    }

    private var timerStatus: String {
        guard let timing else { return "Not started" }
        if timing.isRunning { return "In progress" }
        return timing.finished ? "Finished" : "Paused"
    }

    @ViewBuilder private var nextButton: some View {
        if index + 1 < count {
            Button(action: onNext) {
                Label("Next exercise", systemImage: "arrow.right")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        } else {
            Label("Last exercise — finish strong!", systemImage: "flag.checkered")
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .foregroundStyle(.secondary)
        }
    }

    /// Weight of the set just above this one today, else what you did last time.
    private func suggestedWeight(for spec: SetRowSpec) -> Double {
        if let p = previous[spec.id] { return p.weight }
        let earlier = logs.filter { $0.done && ($0.setIndex, $0.dropIndex) < (spec.setIndex, spec.dropIndex) }
            .max { ($0.setIndex, $0.dropIndex) < ($1.setIndex, $1.dropIndex) }
        return earlier?.weight ?? previous.values.map(\.weight).max() ?? 0
    }

    private func rowCompleted(_ spec: SetRowSpec) {
        let doneIDs = Set(logs.filter(\.done).map(\.rowID)).union([spec.id])
        let exerciseDone = exercise.rows.allSatisfy { doneIDs.contains($0.id) }
        ExerciseClock.setCompleted(dateKey: dateKey, index: index, name: exercise.name,
                                   exerciseDone: exerciseDone, in: modelContext)
        if exerciseDone, spec.setIndex < exercise.sets.count {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6, execute: onNext)
        }
    }

    private func addSet() {
        let last = logs.max { ($0.setIndex, $0.dropIndex) < ($1.setIndex, $1.dropIndex) }
        let next = max(exercise.sets.count, (logs.map(\.setIndex).max() ?? -1) + 1)
        modelContext.insert(SetLog(dateKey: dateKey, exerciseIndex: index, exerciseName: exercise.name,
                                   setIndex: next, dropIndex: 0,
                                   weight: last?.weight ?? 0, reps: last?.reps ?? 10, done: false))
    }

    /// Most recent completed log for each row of this exercise on an earlier day.
    private func loadPrevious() {
        let name = exercise.name
        let key = dateKey
        var descriptor = FetchDescriptor<SetLog>(
            predicate: #Predicate { $0.exerciseName == name && $0.dateKey != key && $0.done },
            sortBy: [SortDescriptor(\.dateKey, order: .reverse)])
        descriptor.fetchLimit = 60
        var timingDescriptor = FetchDescriptor<ExerciseTiming>(
            predicate: #Predicate { $0.exerciseName == name && $0.dateKey != key && $0.finished },
            sortBy: [SortDescriptor(\.dateKey, order: .reverse)])
        timingDescriptor.fetchLimit = 1
        lastTime = (try? modelContext.fetch(timingDescriptor))?.first?.elapsed()
        guard let results = try? modelContext.fetch(descriptor), let latest = results.first?.dateKey else { return }
        previous = Dictionary(results.filter { $0.dateKey == latest }.map { ($0.rowID, $0) },
                              uniquingKeysWith: { a, _ in a })
    }
}

/// Full-screen reference photo with pinch-to-zoom and double-tap to reset.
private struct PhotoViewer: View {
    let image: UIImage
    let title: String
    @Environment(\.dismiss) private var dismiss
    @State private var scale: CGFloat = 1
    @State private var baseScale: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var baseOffset: CGSize = .zero

    var body: some View {
        NavigationStack {
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .scaleEffect(scale)
                .offset(offset)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(.black)
                .gesture(
                    MagnifyGesture()
                        .onChanged { scale = max(1, baseScale * $0.magnification) }
                        .onEnded { _ in baseScale = scale }
                        .simultaneously(with: DragGesture()
                            .onChanged { v in
                                guard scale > 1 else { return }
                                offset = CGSize(width: baseOffset.width + v.translation.width,
                                                height: baseOffset.height + v.translation.height)
                            }
                            .onEnded { _ in baseOffset = offset })
                )
                .onTapGesture(count: 2) {
                    withAnimation { scale = 1; baseScale = 1; offset = .zero; baseOffset = .zero }
                }
                .navigationTitle(title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbarBackground(.visible, for: .navigationBar)
                .toolbar {
                    Button("Done") { dismiss() }
                }
        }
    }
}

private struct Tag: View {
    let text: String
    let systemImage: String

    var body: some View {
        Label(text, systemImage: systemImage)
            .font(.caption)
            .lineLimit(1)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color(.secondarySystemBackground), in: .capsule)
    }
}
