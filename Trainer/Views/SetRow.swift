import SwiftData
import SwiftUI

/// A set: target + rest on top, weight/reps steppers and a big check button below.
struct SetRow: View {
    let spec: SetRowSpec
    let exerciseIndex: Int
    let exerciseName: String
    let dateKey: String
    let log: SetLog?
    let previous: SetLog?
    let suggestedWeight: Double
    let isExtra: Bool
    let onCompleted: () -> Void

    @Environment(\.modelContext) private var modelContext
    @Environment(RestTimer.self) private var restTimer
    @AppStorage(SettingsKey.unit) private var unit = "kg"

    @State private var weight: Double = 0
    @State private var reps: Int = 0
    @State private var loaded = false

    private var done: Bool { log?.done ?? false }
    private var weightStep: Double { unit == "kg" ? 2.5 : 5 }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text(spec.label).font(.subheadline.bold())
                if spec.dropIndex > 0 {
                    Image(systemName: "arrow.turn.down.right").font(.caption).foregroundStyle(.secondary)
                }
                Text(spec.target).font(.subheadline).foregroundStyle(.secondary)
                if let rest = spec.rest, rest > 0 {
                    Label(Self.format(rest), systemImage: "timer")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                if let previous {
                    Text("Last \(previous.weight.formatted()) × \(previous.reps)")
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }

            HStack(spacing: 10) {
                ValueStepper(value: $weight, step: weightStep, unit: unit, isDecimal: true)
                ValueStepper(value: Binding(get: { Double(reps) }, set: { reps = max(0, Int($0)) }),
                        step: 1, unit: spec.isTimed ? "sec" : "reps", isDecimal: false)
                Button(action: toggleDone) {
                    Image(systemName: done ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 34))
                        .foregroundStyle(done ? Color.green : Color.secondary)
                        .contentTransition(.symbolEffect(.replace))
                }
                .buttonStyle(.plain)
                .sensoryFeedback(.success, trigger: done) { _, new in new }
            }
        }
        .padding(12)
        .background(done ? Color.green.opacity(0.12) : Color(.secondarySystemBackground).opacity(0.6),
                    in: .rect(cornerRadius: 14))
        .overlay(alignment: .leading) {
            if spec.isDropSet {
                RoundedRectangle(cornerRadius: 2).fill(.purple).frame(width: 4).padding(.vertical, 10)
            }
        }
        .contextMenu {
            if isExtra, let log {
                Button("Delete set", systemImage: "trash", role: .destructive) { modelContext.delete(log) }
            }
        }
        .onAppear(perform: load)
        .onChange(of: suggestedWeight) { _, w in if log == nil { weight = w } }
        .onChange(of: weight) { save() }
        .onChange(of: reps) { save() }
    }

    private func load() {
        guard !loaded else { return }
        loaded = true
        weight = log?.weight ?? suggestedWeight
        reps = log?.reps ?? previous?.reps ?? spec.suggestedReps
    }

    private func save() {
        guard let log else { return }
        log.weight = weight
        log.reps = reps
        log.updatedAt = .now
    }

    private func toggleDone() {
        if let log {
            log.done.toggle()
            log.weight = weight
            log.reps = reps
            log.updatedAt = .now
        } else {
            modelContext.insert(SetLog(dateKey: dateKey, exerciseIndex: exerciseIndex, exerciseName: exerciseName,
                                       setIndex: spec.setIndex, dropIndex: spec.dropIndex,
                                       weight: weight, reps: reps, done: true))
        }
        guard log?.done ?? true else {
            restTimer.skip()
            return
        }
        if let rest = spec.rest { restTimer.start(seconds: rest) }
        onCompleted()
    }

    static func format(_ seconds: Int) -> String {
        seconds >= 60 ? String(format: "%d:%02d", seconds / 60, seconds % 60) : "\(seconds)s"
    }
}

/// Compact − value + control; the value is also directly editable.
private struct ValueStepper: View {
    @Binding var value: Double
    let step: Double
    let unit: String
    let isDecimal: Bool

    var body: some View {
        HStack(spacing: 0) {
            button("minus") { value = max(0, value - step) }
            VStack(spacing: 0) {
                TextField("0", value: $value, format: .number.precision(.fractionLength(0...1)))
                    .keyboardType(isDecimal ? .decimalPad : .numberPad)
                    .multilineTextAlignment(.center)
                    .font(.headline.monospacedDigit())
                Text(unit).font(.caption2).foregroundStyle(.secondary)
            }
            .frame(minWidth: 44)
            button("plus") { value += step }
        }
        .padding(4)
        .background(Color(.tertiarySystemBackground), in: .rect(cornerRadius: 10))
        .frame(maxWidth: .infinity)
    }

    private func button(_ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.subheadline.bold())
                .frame(width: 34, height: 38)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .foregroundStyle(.tint)
    }
}
