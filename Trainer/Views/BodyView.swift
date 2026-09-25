import Charts
import SwiftData
import SwiftUI

/// Body weight + tape measurements (manual), plus weight and steps from Apple Health.
struct BodyView: View {
    @Environment(HealthManager.self) private var health
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage(SettingsKey.unit) private var unit = "lb"
    @AppStorage(SettingsKey.healthConnected) private var healthConnected = false
    @Query(sort: \BodyEntry.date, order: .reverse) private var entries: [BodyEntry]

    @State private var editing: BodyEntry?
    @State private var addingEntry = false
    @State private var measurement = BodyMeasurement.waist

    private struct WeightPoint: Identifiable {
        let id: String
        let date: Date
        let kg: Double
    }

    /// App check-ins and Health samples on one line, last 90 days.
    private var weightPoints: [WeightPoint] {
        let cutoff = Calendar.current.date(byAdding: .day, value: -90, to: .now)!
        let app = entries.compactMap { e in
            e.weightKg.map { WeightPoint(id: "app-\(e.persistentModelID.hashValue)", date: e.date, kg: $0) }
        }
        let fromHealth = healthConnected ? health.weights.map { WeightPoint(id: $0.id.uuidString, date: $0.date, kg: $0.kg) } : []
        return (app + fromHealth).filter { $0.date >= cutoff }.sorted { $0.date < $1.date }
    }

    var body: some View {
        NavigationStack {
            List {
                healthSection
                weightSection
                measurementSection
                historySection
            }
            .navigationTitle("Body")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { addingEntry = true } label: { Label("Log", systemImage: "plus") }
                }
                ToolbarItem(placement: .topBarTrailing) { SettingsButton() }
            }
            .sheet(isPresented: $addingEntry) { BodyEntrySheet(entry: nil) }
            .sheet(item: $editing) { BodyEntrySheet(entry: $0) }
            .refreshable { await health.refresh() }
            .task { if healthConnected { await health.refresh() } }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active, healthConnected { Task { await health.refresh() } }
            }
        }
    }

    // MARK: Apple Health

    @ViewBuilder private var healthSection: some View {
        if !health.isAvailable {
            EmptyView()
        } else if !healthConnected {
            Section {
                VStack(alignment: .leading, spacing: 10) {
                    Label("Apple Health", systemImage: "heart.fill")
                        .font(.headline).foregroundStyle(.pink)
                    Text("Show your weight and daily steps from Apple Health here. Trainer only reads this data. It never changes it.")
                        .font(.subheadline).foregroundStyle(.secondary)
                    Button {
                        Task {
                            await health.connect()
                            healthConnected = true
                        }
                    } label: {
                        Text("Connect Apple Health").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.pink)
                }
                .padding(.vertical, 4)
            }
        } else {
            Section("Steps") {
                StepsCard(days: health.stepDays, today: health.todaySteps)
                if let error = health.errorMessage {
                    Text(error).font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: Weight

    private var weightSection: some View {
        Section("Weight") {
            let points = weightPoints
            if let latest = points.last {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(format(Units.weight(latest.kg, unit)))
                            .font(.system(size: 34, weight: .bold, design: .rounded))
                        Text(unit).font(.headline).foregroundStyle(.secondary)
                        Spacer()
                        Text(latest.date.formatted(.dateTime.month(.abbreviated).day()))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    if let change = change(points.map { ($0.date, $0.kg) }, days: 30) {
                        Text("\(signed(Units.weight(change, unit))) \(unit) in the last 30 days")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                    if points.count >= 2 {
                        TrendChart(points: points.map { ($0.date, Units.weight($0.kg, unit)) }, unit: unit)
                            .frame(height: 180)
                    }
                }
                .padding(.vertical, 4)
            } else {
                emptyRow("No weight yet", detail: healthConnected
                         ? "Tap + to log your weight, or add it in Apple Health."
                         : "Tap + to log your weight, or connect Apple Health.")
            }
        }
    }

    // MARK: Measurements

    private var measurementSection: some View {
        Section("Measurements") {
            Picker("Measurement", selection: $measurement) {
                ForEach(BodyMeasurement.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .listRowSeparator(.hidden)

            let series = entries.compactMap { e in e[keyPath: measurement.keyPath].map { (e.date, $0) } }
                .sorted { $0.0 < $1.0 }
            let lengthUnit = Units.lengthUnit(unit)
            if let latest = series.last {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(format(Units.length(latest.1, unit)))
                            .font(.system(size: 34, weight: .bold, design: .rounded))
                        Text(lengthUnit).font(.headline).foregroundStyle(.secondary)
                    }
                    if let first = series.first, series.count >= 2 {
                        Text("\(signed(Units.length(latest.1 - first.1, unit))) \(lengthUnit) since \(first.0.formatted(.dateTime.month(.abbreviated).day()))")
                            .font(.subheadline).foregroundStyle(.secondary)
                        TrendChart(points: series.map { ($0.0, Units.length($0.1, unit)) }, unit: lengthUnit)
                            .frame(height: 160)
                    }
                }
                .padding(.vertical, 4)
            } else {
                emptyRow("No \(measurement.rawValue.lowercased()) measurements yet",
                         detail: "Tap + and add your tape measurements.")
            }
        }
    }

    // MARK: History

    @ViewBuilder private var historySection: some View {
        if !entries.isEmpty {
            Section {
                ForEach(entries) { entry in
                    Button { editing = entry } label: { historyRow(entry) }
                        .buttonStyle(.plain)
                }
                .onDelete { offsets in offsets.map { entries[$0] }.forEach(modelContext.delete) }
            } header: {
                Text("Your check-ins")
            } footer: {
                if healthConnected, !health.weights.isEmpty {
                    Text("The weight chart also includes \(health.weights.count) weigh-ins from Apple Health.")
                }
            }
        }
    }

    private func historyRow(_ entry: BodyEntry) -> some View {
        let lengthUnit = Units.lengthUnit(unit)
        let parts = BodyMeasurement.allCases.compactMap { m in
            entry[keyPath: m.keyPath].map { "\(m.rawValue) \(format(Units.length($0, unit)))" }
        }
        return HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day().year()))
                    .font(.subheadline.bold())
                if !parts.isEmpty {
                    Text(parts.joined(separator: " · ") + " \(lengthUnit)")
                        .font(.caption).foregroundStyle(.secondary).lineLimit(2)
                }
            }
            Spacer()
            if let kg = entry.weightKg {
                Text("\(format(Units.weight(kg, unit))) \(unit)").font(.subheadline.monospacedDigit())
            }
        }
        .contentShape(.rect)
    }

    // MARK: Helpers

    private func emptyRow(_ title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.subheadline.bold())
            Text(detail).font(.caption).foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }

    /// Latest value minus the value closest to `days` ago (needs data that old).
    private func change(_ series: [(Date, Double)], days: Int) -> Double? {
        guard let last = series.last,
              let cutoff = Calendar.current.date(byAdding: .day, value: -days, to: last.0),
              let base = series.last(where: { $0.0 <= cutoff }) ?? (series.count >= 2 ? series.first : nil)
        else { return nil }
        return last.1 - base.1
    }

    private func format(_ v: Double) -> String { v.formatted(.number.precision(.fractionLength(0...1))) }
    private func signed(_ v: Double) -> String { (v > 0 ? "+" : v < 0 ? "−" : "±") + format(abs(v)) }
}

/// Single-series line over time. Drag across it to read a value.
private struct TrendChart: View {
    let points: [(Date, Double)]
    let unit: String
    @State private var selected: Date?

    private var selectedPoint: (Date, Double)? {
        guard let selected else { return nil }
        return points.min { abs($0.0.timeIntervalSince(selected)) < abs($1.0.timeIntervalSince(selected)) }
    }

    var body: some View {
        Chart {
            ForEach(points.indices, id: \.self) { i in
                LineMark(x: .value("Date", points[i].0), y: .value("Value", points[i].1))
                    .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                    .foregroundStyle(Color.accentColor)
                if points.count <= 40 {
                    PointMark(x: .value("Date", points[i].0), y: .value("Value", points[i].1))
                        .symbolSize(30)
                        .foregroundStyle(Color.accentColor)
                }
            }
            if let p = selectedPoint {
                RuleMark(x: .value("Date", p.0))
                    .foregroundStyle(Color.secondary.opacity(0.4))
                    .lineStyle(StrokeStyle(lineWidth: 1))
                    .annotation(position: .top, overflowResolution: .init(x: .fit(to: .chart), y: .disabled)) {
                        ChartTooltip(title: p.1.formatted(.number.precision(.fractionLength(0...1))) + " " + unit,
                                     subtitle: p.0.formatted(.dateTime.month(.abbreviated).day()))
                    }
                PointMark(x: .value("Date", p.0), y: .value("Value", p.1))
                    .symbolSize(80)
                    .foregroundStyle(Color.accentColor)
            }
        }
        .chartYScale(domain: .automatic(includesZero: false))
        .chartXScale(range: .plotDimension(startPadding: 8, endPadding: 24))
        .chartXSelection(value: $selected)
        .chartYAxis {
            AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) {
                AxisGridLine().foregroundStyle(Color.secondary.opacity(0.15))
                AxisValueLabel()
            }
        }
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 4)) {
                AxisValueLabel(format: .dateTime.month(.abbreviated).day())
            }
        }
    }
}

/// Today's steps + last 7 days as bars. Drag across it to read a day.
private struct StepsCard: View {
    let days: [HealthManager.StepDay]
    let today: Int
    @State private var selected: Date?

    private var selectedDay: HealthManager.StepDay? {
        guard let selected else { return nil }
        return days.first { Calendar.current.isDate($0.date, inSameDayAs: selected) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(today.formatted()).font(.system(size: 34, weight: .bold, design: .rounded))
                Text("steps today").font(.headline).foregroundStyle(.secondary)
            }
            if days.contains(where: { $0.steps > 0 }) {
                let average = days.map(\.steps).reduce(0, +) / max(days.count, 1)
                Text("\(average.formatted()) a day on average this week")
                    .font(.subheadline).foregroundStyle(.secondary)
                Chart {
                    ForEach(days) { day in
                        BarMark(x: .value("Day", day.date, unit: .day), y: .value("Steps", day.steps), width: .ratio(0.6))
                            .clipShape(UnevenRoundedRectangle(topLeadingRadius: 4, topTrailingRadius: 4))
                            .foregroundStyle(Color.accentColor.opacity(selectedDay == nil || selectedDay?.date == day.date ? 1 : 0.35))
                    }
                    if let d = selectedDay {
                        RuleMark(x: .value("Day", d.date, unit: .day))
                            .foregroundStyle(.clear)
                            .annotation(position: .top, overflowResolution: .init(x: .fit(to: .chart), y: .disabled)) {
                                ChartTooltip(title: "\(d.steps.formatted()) steps",
                                             subtitle: d.date.formatted(.dateTime.weekday(.wide)))
                            }
                    }
                }
                .chartXSelection(value: $selected)
                .chartXAxis {
                    AxisMarks(values: .stride(by: .day)) {
                        AxisValueLabel(format: .dateTime.weekday(.narrow), centered: true)
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) {
                        AxisGridLine().foregroundStyle(Color.secondary.opacity(0.15))
                        AxisValueLabel()
                    }
                }
                .frame(height: 150)
            } else {
                Text("No steps found. If you didn't allow access, go to the Settings app → Health → Data Access & Devices → Trainer.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

private struct ChartTooltip: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(spacing: 1) {
            Text(title).font(.caption.bold().monospacedDigit()).foregroundStyle(.primary)
            Text(subtitle).font(.caption2).foregroundStyle(.secondary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(.regularMaterial, in: .rect(cornerRadius: 8))
    }
}
