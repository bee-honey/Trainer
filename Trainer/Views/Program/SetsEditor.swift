import SwiftUI

/// Form section for editing a list of sets: target, rest, and drop sets.
/// Swipe to delete; tap Edit to reorder.
struct SetsEditor: View {
    @Binding var sets: [ProgramSet]
    let defaultRest: Int
    var title = "Sets"
    var footer: String?

    /// Local copy with stable IDs: identical sets (e.g. 7 × "10 reps") are common,
    /// so the sets themselves can't identify rows.
    private struct Row: Identifiable {
        let id = UUID()
        var set: ProgramSet
    }

    @State private var rows: [Row] = []
    @State private var loaded = false

    var body: some View {
        Section {
            ForEach($rows) { $row in
                SetEditorRow(number: (rows.firstIndex { $0.id == row.id } ?? 0) + 1,
                             set: $row.set, defaultRest: defaultRest)
            }
            .onDelete { rows.remove(atOffsets: $0) }
            .onMove { rows.move(fromOffsets: $0, toOffset: $1) }

            Button {
                rows.append(Row(set: rows.last?.set ?? .standard(rest: defaultRest)))
            } label: {
                Label("Add set", systemImage: "plus.circle.fill")
            }
        } header: {
            Text(title)
        } footer: {
            if let footer { Text(footer) }
        }
        .onAppear {
            guard !loaded else { return }
            loaded = true
            rows = sets.map { Row(set: $0) }
        }
        .onChange(of: rows.map(\.set)) { _, new in
            if new != sets { sets = new }
        }
        .onChange(of: sets) { _, new in
            if new != rows.map(\.set) { rows = new.map { Row(set: $0) } }
        }
    }
}

private struct SetEditorRow: View {
    let number: Int
    @Binding var set: ProgramSet
    let defaultRest: Int

    private var isDropSet: Binding<Bool> {
        Binding(get: { !set.drops.isEmpty }, set: { on in
            if on {
                // A drop set goes straight into the drop; the rest moves to after the last drop.
                set.drops = [ProgramDrop(target: "To failure", rest: set.rest ?? defaultRest)]
                set.rest = nil
                set.kind = "Drop"
            } else {
                set.rest = set.drops.last?.rest ?? defaultRest
                set.drops = []
                set.kind = "Standard"
            }
        })
    }

    private var restAfter: Binding<Int> {
        Binding(get: { (set.drops.isEmpty ? set.rest : set.drops.last?.rest) ?? 0 },
                set: { value in
                    if set.drops.isEmpty { set.rest = value } else { set.drops[set.drops.count - 1].rest = value }
                })
    }

    /// Bounds-checked so a row being removed never reads past the end.
    private func dropTarget(_ d: Int) -> Binding<String> {
        Binding(get: { d < set.drops.count ? set.drops[d].target : "" },
                set: { if d < set.drops.count { set.drops[d].target = $0 } })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Set \(number)").font(.subheadline.bold()).frame(width: 56, alignment: .leading)
                TargetField(text: $set.target)
            }
            ForEach(set.drops.indices, id: \.self) { d in
                HStack {
                    Label("Drop \(d + 1)", systemImage: "arrow.turn.down.right")
                        .font(.subheadline).labelStyle(.titleOnly).foregroundStyle(.purple)
                        .frame(width: 56, alignment: .leading)
                    TargetField(text: dropTarget(d))
                }
            }
            Stepper(value: restAfter, in: 0...600, step: 15) {
                HStack {
                    Text(set.drops.isEmpty ? "Rest" : "Rest after drops")
                    Spacer()
                    Text(restAfter.wrappedValue == 0 ? "None" : SetRow.format(restAfter.wrappedValue))
                        .monospacedDigit().foregroundStyle(.secondary)
                }
            }
            HStack {
                Toggle("Drop set", isOn: isDropSet).fixedSize()
                Spacer()
                if !set.drops.isEmpty {
                    Button {
                        let rest = set.drops.last?.rest
                        if !set.drops.isEmpty { set.drops[set.drops.count - 1].rest = nil }
                        set.drops.append(ProgramDrop(target: "To failure", rest: rest))
                    } label: { Image(systemName: "plus.circle") }
                        .accessibilityLabel("Add drop")
                    Button {
                        guard set.drops.count > 1 else { isDropSet.wrappedValue = false; return }
                        let rest = set.drops.removeLast().rest
                        set.drops[set.drops.count - 1].rest = rest
                    } label: { Image(systemName: "minus.circle") }
                        .accessibilityLabel("Remove drop")
                }
            }
            .buttonStyle(.borderless)   // several buttons in one Form row must not share one tap
        }
        .padding(.vertical, 4)
    }
}

/// Free-text target with common presets one tap away.
private struct TargetField: View {
    @Binding var text: String
    private static let presets = ["8 reps", "10 reps", "12 reps", "15 reps", "6 to 8 reps", "10 to 12 reps",
                                  "To failure", "30 sec", "45 sec", "60 sec"]

    var body: some View {
        HStack {
            TextField("e.g. 10 reps", text: $text)
            Menu {
                ForEach(Self.presets, id: \.self) { p in Button(p) { text = p } }
            } label: {
                Image(systemName: "chevron.up.chevron.down").font(.caption)
            }
            .buttonStyle(.borderless)
        }
    }
}
