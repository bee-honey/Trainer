import SwiftData
import SwiftUI

struct TodayView: View {
    @Environment(\.scenePhase) private var scenePhase
    @State private var today = Date.now

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: 0) {
                        Text(today.formatted(.dateTime.weekday(.wide).month(.abbreviated).day()).uppercased())
                            .font(.caption.bold())
                            .foregroundStyle(.secondary)
                        Text(AppInfo.name).font(.largeTitle.bold())
                    }
                    Spacer()
                    SettingsButton()
                }
                .padding(.horizontal)
                .padding(.top, 4)
                WorkoutDayView(date: today)
            }
            .toolbar(.hidden, for: .navigationBar)
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active, !Calendar.current.isDate(today, inSameDayAs: .now) { today = .now }
        }
    }
}

/// Whatever the program says for a given date: a workout, a rest day, or nothing.
struct WorkoutDayView: View {
    let date: Date
    @AppStorage(SettingsKey.startDate) private var startTimestamp: Double = 0
    @AppStorage(SettingsKey.repeats) private var repeats = true
    @Query(sort: \Workout.order) private var workouts: [Workout]

    private var schedule: Schedule {
        Schedule(startDate: Date(timeIntervalSince1970: startTimestamp), repeats: repeats,
                 days: Program.days(from: workouts))
    }

    var body: some View {
        Group {
            switch schedule.plan(for: date) {
            case .workout(let day) where day.exercises.isEmpty:
                ContentUnavailableView("No exercises", systemImage: "dumbbell",
                                       description: Text("\(day.title) has no exercises. Add some in the Workouts tab."))
            case .workout(let day):
                WorkoutPager(day: day, date: date)
            case .rest(let n):
                RestDayView(date: date, dayNumber: n, next: schedule.nextWorkout(after: date))
            case .notScheduled:
                ContentUnavailableView("Not in your program",
                                       systemImage: "calendar.badge.exclamationmark",
                                       description: Text("This date is outside your program. Change the start date in Settings."))
            }
        }
        .navigationTitle(date.formatted(.dateTime.weekday(.wide).day().month(.abbreviated)))
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct RestDayView: View {
    let date: Date
    let dayNumber: Int
    let next: (Date, ProgramDay)?

    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            Image(systemName: WorkoutCategory.rest.symbol)
                .font(.system(size: 64))
                .foregroundStyle(.secondary)
            VStack(spacing: 6) {
                Text("Rest Day").font(.largeTitle.bold())
                Text("Day \(dayNumber) · Week \((dayNumber - 1) / 7 + 1)").foregroundStyle(.secondary)
            }
            Text("Recover, eat well, sleep. Growth happens today.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            if let (nextDate, day) = next {
                VStack(alignment: .leading, spacing: 4) {
                    Text("NEXT UP").font(.caption.bold()).foregroundStyle(.secondary)
                    Text(day.title).font(.headline)
                    Text(nextDate.formatted(.dateTime.weekday(.wide).day().month()))
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
                .background(day.category.color.opacity(0.15), in: .rect(cornerRadius: 16))
            }
            Spacer()
        }
        .padding()
    }
}

/// Swipe left/right between the day's exercises.
struct WorkoutPager: View {
    let day: ProgramDay
    let date: Date
    @State private var page = 0
    @Query private var logs: [SetLog]
    @Query private var timings: [ExerciseTiming]
    @Environment(RestTimer.self) private var restTimer
    @Environment(HealthManager.self) private var health
    @Environment(\.modelContext) private var modelContext
    @AppStorage(SettingsKey.healthConnected) private var healthConnected = false
    @State private var weightKg: Double?
    @State private var banner: CalorieBanner.Content?

    init(day: ProgramDay, date: Date) {
        self.day = day
        self.date = date
        let key = date.dayKey
        _logs = Query(filter: #Predicate<SetLog> { $0.dateKey == key })
        _timings = Query(filter: #Predicate<ExerciseTiming> { $0.dateKey == key })
    }

    /// Planned rows plus extra sets, counting only exercises still in the workout.
    private var totalCount: Int {
        day.totalRows + logs.filter { log in
            day.exercises.first { $0.key == log.itemKey }.map { log.setIndex >= $0.sets.count } ?? false
        }.count
    }

    private var doneCount: Int {
        let keys = Set(day.exercises.map(\.key))
        return logs.filter { $0.done && keys.contains($0.itemKey) }.count
    }

    private var bodyWeight: Double { weightKg ?? CalorieEstimator.fallbackWeightKg }

    private func exercise(for timing: ExerciseTiming) -> ProgramExercise? {
        day.exercises.first { $0.key == timing.itemKey }
    }

    private func dayKcal(at now: Date = .now) -> Double {
        timings.reduce(0) { $0 + CalorieEstimator.kcal(for: $1, exercise: exercise(for: $1), weightKg: bodyWeight, at: now) }
    }

    private var finishedKeys: Set<String> { Set(timings.filter(\.finished).map(\.itemKey)) }

    private func isComplete(_ i: Int) -> Bool {
        let exercise = day.exercises[i]
        let done = Set(logs.filter { $0.itemKey == exercise.key && $0.done }.map(\.rowID))
        return exercise.rows.allSatisfy { done.contains($0.id) }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            exerciseStrip
            TabView(selection: $page) {
                ForEach(day.exercises.indices, id: \.self) { i in
                    let exercise = day.exercises[i]
                    ExercisePage(exercise: exercise, index: i, count: day.exercises.count,
                                 dateKey: date.dayKey,
                                 logs: logs.filter { $0.itemKey == exercise.key },
                                 timing: timings.first { $0.itemKey == exercise.key },
                                 weightKg: bodyWeight,
                                 onNext: { advance(from: i) })
                        .tag(i)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .overlay(alignment: .bottom) {
                if restTimer.isRunning {
                    RestTimerBanner().padding(.horizontal).padding(.bottom, 8)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(.spring, value: restTimer.isRunning)
            .overlay(alignment: .top) {
                if let banner {
                    CalorieBanner(content: banner) { self.banner = nil }
                        .padding(.horizontal)
                        .padding(.top, 4)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .animation(.spring, value: banner)
        }
        .task {
            if healthConnected, health.weights.isEmpty { await health.refresh() }
            weightKg = CalorieService.bodyWeightKg(context: modelContext, health: health)
            await CalorieService.refine(timings, health: health, useHealth: healthConnected)
        }
        .onChange(of: finishedKeys) { old, new in
            for key in new.subtracting(old) {
                guard let timing = timings.first(where: { $0.itemKey == key }) else { continue }
                Task { await exerciseFinished(timing) }
            }
        }
        .onAppear { UIApplication.shared.isIdleTimerDisabled = true }
        .onDisappear { UIApplication.shared.isIdleTimerDisabled = false }
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") {
                    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                }
            }
        }
    }

    /// Save the exercise's calories, then celebrate it (or the whole workout).
    private func exerciseFinished(_ timing: ExerciseTiming) async {
        let exercise = exercise(for: timing)
        await CalorieService.finalize(timing, exercise: exercise, weightKg: bodyWeight,
                                      health: health, useHealth: healthConnected)
        let kcal = timing.kcal ?? 0
        let note = weightKg == nil ? "Log your weight in Body for a better estimate" : nil
        if day.exercises.indices.allSatisfy(isComplete) {
            let duration = ExerciseClock.workoutDuration(timings) ?? timing.elapsed()
            banner = .init(title: "Workout complete 💪",
                           detail: "\(duration.clockString) · \(CalorieEstimator.format(dayKcal()))",
                           note: note, fromWatch: timing.kcalFromWatch)
        } else {
            banner = .init(title: "\(exercise?.name ?? timing.exerciseName) done",
                           detail: "\(timing.elapsed().clockString) · \(CalorieEstimator.format(kcal))",
                           note: note, fromWatch: timing.kcalFromWatch)
        }
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        let shown = banner
        try? await Task.sleep(for: .seconds(5))
        if banner == shown { banner = nil }
    }

    private func advance(from i: Int) {
        guard i + 1 < day.exercises.count else { return }
        withAnimation { page = i + 1 }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("Week \(day.week) · Day \(day.day)", systemImage: day.category.symbol)
                    .font(.caption.bold())
                    .foregroundStyle(day.category.color)
                Spacer()
                workoutClock
                Text("\(doneCount)/\(totalCount) sets")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Text(day.title).font(.title3.bold()).lineLimit(2)
            ProgressView(value: Double(doneCount), total: Double(max(totalCount, 1)))
                .tint(day.category.color)
        }
        .padding(.horizontal)
        .padding(.top, 8)
    }

    @ViewBuilder private var workoutClock: some View {
        if ExerciseClock.workoutDuration(timings) != nil {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                HStack(spacing: 6) {
                    Label(ExerciseClock.workoutDuration(timings, at: context.date)?.clockString ?? "",
                          systemImage: "stopwatch")
                        .foregroundStyle(timings.contains(where: \.isRunning) ? Color.accentColor : .secondary)
                    Text("·").foregroundStyle(.secondary)
                    Label("\(Int(dayKcal(at: context.date).rounded()))", systemImage: "flame.fill")
                        .foregroundStyle(.secondary)
                        .accessibilityLabel(CalorieEstimator.format(dayKcal(at: context.date)))
                }
                .font(.caption.bold().monospacedDigit())
                .labelStyle(.tightIcon)
            }
            Text("·").font(.caption).foregroundStyle(.secondary)
        }
    }

    private var exerciseStrip: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(day.exercises.indices, id: \.self) { i in
                        Button {
                            withAnimation { page = i }
                        } label: {
                            ZStack {
                                Circle()
                                    .fill(isComplete(i) ? day.category.color : Color(.secondarySystemBackground))
                                Circle()
                                    .strokeBorder(page == i ? day.category.color : .clear, lineWidth: 2)
                                if isComplete(i) {
                                    Image(systemName: "checkmark").font(.caption.bold()).foregroundStyle(.white)
                                } else {
                                    Text("\(i + 1)").font(.subheadline.bold())
                                        .foregroundStyle(page == i ? day.category.color : .primary)
                                }
                            }
                            .frame(width: 36, height: 36)
                        }
                        .buttonStyle(.plain)
                        .id(i)
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 10)
            }
            .onChange(of: page) { _, p in withAnimation { proxy.scrollTo(p, anchor: .center) } }
        }
    }
}

/// Top banner shown when an exercise or the whole workout is finished.
struct CalorieBanner: View {
    struct Content: Equatable {
        let title: String
        let detail: String
        let note: String?
        let fromWatch: Bool
    }

    let content: Content
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "flame.fill")
                .font(.title2)
                .foregroundStyle(.white)
                .frame(width: 40, height: 40)
                .background(Color.accentColor.gradient, in: .circle)
            VStack(alignment: .leading, spacing: 2) {
                Text(content.title).font(.subheadline.bold()).lineLimit(1)
                HStack(spacing: 4) {
                    Text(content.detail).monospacedDigit()
                    if content.fromWatch {
                        Image(systemName: "applewatch").accessibilityLabel("from Apple Watch")
                    }
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
                if let note = content.note {
                    Text(note).font(.caption2).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(.regularMaterial, in: .rect(cornerRadius: 18))
        .shadow(color: .black.opacity(0.15), radius: 10, y: 4)
        .onTapGesture(perform: onDismiss)
        .accessibilityAddTraits(.isButton)
        .accessibilityHint("Dismiss")
    }
}

/// Icon + title with less space between them, for compact caption stats.
struct TightIconLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 3) {
            configuration.icon
            configuration.title
        }
    }
}

extension LabelStyle where Self == TightIconLabelStyle {
    static var tightIcon: TightIconLabelStyle { .init() }
}
