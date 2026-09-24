import SwiftData
import SwiftUI

struct TodayView: View {
    @Environment(\.scenePhase) private var scenePhase
    @State private var today = Date.now

    var body: some View {
        NavigationStack {
            WorkoutDayView(date: today)
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

    private var schedule: Schedule {
        Schedule(startDate: Date(timeIntervalSince1970: startTimestamp), repeats: repeats)
    }

    var body: some View {
        Group {
            switch schedule.plan(for: date) {
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

    init(day: ProgramDay, date: Date) {
        self.day = day
        self.date = date
        let key = date.dayKey
        _logs = Query(filter: #Predicate<SetLog> { $0.dateKey == key })
        _timings = Query(filter: #Predicate<ExerciseTiming> { $0.dateKey == key })
    }

    private var doneCount: Int { logs.filter(\.done).count }
    private var totalCount: Int { day.totalRows + logs.filter { $0.setIndex >= setsCount($0.exerciseIndex) }.count }

    private func setsCount(_ exerciseIndex: Int) -> Int {
        day.exercises.indices.contains(exerciseIndex) ? day.exercises[exerciseIndex].sets.count : 0
    }

    private func isComplete(_ i: Int) -> Bool {
        let rows = day.exercises[i].rows.count
        return logs.filter { $0.exerciseIndex == i && $0.done && $0.setIndex < setsCount(i) }.count >= rows
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            exerciseStrip
            TabView(selection: $page) {
                ForEach(day.exercises.indices, id: \.self) { i in
                    ExercisePage(exercise: day.exercises[i], index: i, count: day.exercises.count,
                                 dateKey: date.dayKey,
                                 logs: logs.filter { $0.exerciseIndex == i },
                                 timing: timings.first { $0.exerciseIndex == i },
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
                Label(ExerciseClock.workoutDuration(timings, at: context.date)?.clockString ?? "",
                      systemImage: "stopwatch")
                    .font(.caption.bold().monospacedDigit())
                    .foregroundStyle(timings.contains(where: \.isRunning) ? Color.accentColor : .secondary)
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
