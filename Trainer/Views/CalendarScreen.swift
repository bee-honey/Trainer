import SwiftData
import SwiftUI

struct CalendarScreen: View {
    @AppStorage(SettingsKey.startDate) private var startTimestamp: Double = 0
    @AppStorage(SettingsKey.repeats) private var repeats = true
    @Query(filter: #Predicate<SetLog> { $0.done }) private var doneLogs: [SetLog]
    @Query private var timings: [ExerciseTiming]

    @State private var month = Calendar.current.dateInterval(of: .month, for: .now)!.start
    @State private var selected = Calendar.current.startOfDay(for: .now)

    private let calendar = Calendar.current
    private var schedule: Schedule {
        Schedule(startDate: Date(timeIntervalSince1970: startTimestamp), repeats: repeats)
    }

    private var doneByDay: [String: Int] {
        Dictionary(grouping: doneLogs, by: \.dateKey).mapValues(\.count)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    monthHeader
                    grid
                    legend
                    selectedCard
                }
                .padding()
            }
            .navigationTitle("Calendar")
            .toolbar {
                Button("Today") {
                    withAnimation {
                        month = calendar.dateInterval(of: .month, for: .now)!.start
                        selected = calendar.startOfDay(for: .now)
                    }
                }
            }
        }
    }

    private var monthHeader: some View {
        HStack {
            Button { shiftMonth(-1) } label: { Image(systemName: "chevron.left").padding(8) }
            Spacer()
            Text(month.formatted(.dateTime.month(.wide).year())).font(.title3.bold())
            Spacer()
            Button { shiftMonth(1) } label: { Image(systemName: "chevron.right").padding(8) }
        }
    }

    private var grid: some View {
        let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 7)
        let symbols = calendar.veryShortStandaloneWeekdaySymbols
        let first = calendar.firstWeekday - 1
        let weekdays = Array(symbols[first...] + symbols[..<first])
        return LazyVGrid(columns: columns, spacing: 6) {
            ForEach(weekdays.indices, id: \.self) { i in
                Text(weekdays[i]).font(.caption.bold()).foregroundStyle(.secondary)
            }
            ForEach(Array(monthCells().enumerated()), id: \.offset) { _, date in
                if let date {
                    DayCell(date: date,
                            plan: schedule.plan(for: date),
                            doneCount: doneByDay[date.dayKey] ?? 0,
                            isSelected: calendar.isDate(date, inSameDayAs: selected),
                            isToday: calendar.isDateInToday(date))
                        .onTapGesture { selected = date }
                } else {
                    Color.clear.frame(height: 54)
                }
            }
        }
        .gesture(DragGesture(minimumDistance: 30).onEnded { value in
            if value.translation.width < -50 { shiftMonth(1) }
            if value.translation.width > 50 { shiftMonth(-1) }
        })
    }

    private var legend: some View {
        HStack(spacing: 12) {
            ForEach([WorkoutCategory.shoulders, .back, .chest, .legs, .rest], id: \.self) { c in
                HStack(spacing: 4) {
                    Circle().fill(c.color).frame(width: 8, height: 8)
                    Text(c.rawValue).font(.caption2)
                }
            }
        }
        .foregroundStyle(.secondary)
    }

    @ViewBuilder private var selectedCard: some View {
        let plan = schedule.plan(for: selected)
        VStack(alignment: .leading, spacing: 10) {
            Text(selected.formatted(.dateTime.weekday(.wide).day().month(.wide)))
                .font(.caption.bold()).foregroundStyle(.secondary)
            switch plan {
            case .workout(let day):
                let done = doneByDay[selected.dayKey] ?? 0
                let dayTimings = timings.filter { $0.dateKey == selected.dayKey }
                HStack {
                    Image(systemName: day.category.symbol).font(.title2).foregroundStyle(day.category.color)
                    VStack(alignment: .leading) {
                        Text(day.title).font(.headline)
                        Text("Week \(day.week) · Day \(day.day) · \(day.exercises.count) exercises · \(done)/\(day.totalRows) sets")
                            .font(.caption).foregroundStyle(.secondary)
                        if let total = ExerciseClock.workoutDuration(dayTimings) {
                            Label("Workout time \(total.clockString)", systemImage: "stopwatch")
                                .font(.caption.bold()).foregroundStyle(Color.accentColor)
                        }
                    }
                }
                ForEach(day.exercises.indices, id: \.self) { i in
                    HStack {
                        Text("• \(day.exercises[i].name)")
                        Spacer()
                        if let t = dayTimings.first(where: { $0.exerciseIndex == i }) {
                            Text(t.elapsed().clockString)
                                .monospacedDigit().foregroundStyle(.secondary)
                        }
                    }
                    .font(.subheadline)
                }
                NavigationLink {
                    WorkoutDayView(date: selected)
                } label: {
                    Label(done > 0 ? "Open workout" : "Start workout", systemImage: "play.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(day.category.color)
            case .rest(let n):
                Label("Rest day · Day \(n)", systemImage: WorkoutCategory.rest.symbol).font(.headline)
            case .notScheduled:
                Label("Not in your program", systemImage: "calendar.badge.exclamationmark")
                    .font(.headline).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color(.secondarySystemBackground), in: .rect(cornerRadius: 16))
    }

    private func shiftMonth(_ delta: Int) {
        withAnimation { month = calendar.date(byAdding: .month, value: delta, to: month)! }
    }

    /// Dates of the month, padded with nils so day 1 lands under its weekday.
    private func monthCells() -> [Date?] {
        guard let range = calendar.range(of: .day, in: .month, for: month) else { return [] }
        let lead = (calendar.component(.weekday, from: month) - calendar.firstWeekday + 7) % 7
        return Array(repeating: nil, count: lead)
            + range.map { calendar.date(byAdding: .day, value: $0 - 1, to: month) }
    }
}

private struct DayCell: View {
    let date: Date
    let plan: DayPlan
    let doneCount: Int
    let isSelected: Bool
    let isToday: Bool

    private var category: WorkoutCategory? {
        switch plan {
        case .workout(let d): d.category
        case .rest: .rest
        case .notScheduled: nil
        }
    }

    private var isComplete: Bool {
        if case .workout(let d) = plan { return doneCount >= d.totalRows }
        return false
    }

    var body: some View {
        VStack(spacing: 3) {
            Text("\(Calendar.current.component(.day, from: date))")
                .font(.subheadline.weight(isToday ? .bold : .regular))
                .foregroundStyle(isToday ? Color.accentColor : .primary)
            Capsule()
                .fill(category?.color ?? .clear)
                .frame(width: 20, height: 4)
                .opacity(category == .rest ? 0.4 : 1)
            Group {
                if isComplete {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                } else if doneCount > 0 {
                    Image(systemName: "circle.lefthalf.filled").foregroundStyle(.green)
                } else {
                    Color.clear
                }
            }
            .font(.caption2)
            .frame(height: 12)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 54)
        .background(isSelected ? Color.accentColor.opacity(0.15) : .clear, in: .rect(cornerRadius: 10))
        .overlay {
            if isToday { RoundedRectangle(cornerRadius: 10).strokeBorder(Color.accentColor, lineWidth: 1.5) }
        }
        .contentShape(.rect)
    }
}
