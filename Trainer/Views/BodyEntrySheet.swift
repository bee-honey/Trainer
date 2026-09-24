import SwiftData
import SwiftUI

/// Log or edit a body check-in. Every field is optional. Log just your weight if that's all you measured.
struct BodyEntrySheet: View {
    let entry: BodyEntry?

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @AppStorage(SettingsKey.unit) private var unit = "lb"

    @State private var date = Date.now
    @State private var weight = ""
    @State private var lengths: [BodyMeasurement: String] = [:]

    var body: some View {
        NavigationStack {
            Form {
                DatePicker("Date", selection: $date, in: ...Date.now, displayedComponents: .date)
                Section("Body weight") {
                    field("Weight", text: $weight, unit: unit)
                }
                Section {
                    ForEach(BodyMeasurement.allCases) { m in
                        field(m.rawValue, text: Binding(get: { lengths[m] ?? "" }, set: { lengths[m] = $0 }),
                              unit: Units.lengthUnit(unit))
                    }
                } header: {
                    Text("Measurements")
                } footer: {
                    Text("Measure at the same spot each time, for example waist at the navel. Arms: flexed, at the widest point.")
                }
            }
            .navigationTitle(entry == nil ? "Log body" : "Edit check-in")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save).disabled(!hasAnyValue)
                }
            }
            .onAppear(perform: load)
        }
        .presentationDetents([.large])
    }

    private func field(_ label: String, text: Binding<String>, unit: String) -> some View {
        HStack {
            Text(label)
            Spacer()
            TextField("—", text: text)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .frame(maxWidth: 100)
            Text(unit).foregroundStyle(.secondary).frame(width: 28, alignment: .leading)
        }
    }

    private var hasAnyValue: Bool {
        parse(weight) != nil || lengths.values.contains { parse($0) != nil }
    }

    private func parse(_ s: String) -> Double? {
        let v = Double(s.replacingOccurrences(of: ",", with: ".").trimmingCharacters(in: .whitespaces))
        return v.flatMap { $0 > 0 ? $0 : nil }
    }

    private func show(_ v: Double) -> String { v.formatted(.number.precision(.fractionLength(0...1)).grouping(.never)) }

    private func load() {
        guard let entry else { return }
        date = entry.date
        weight = entry.weightKg.map { show(Units.weight($0, unit)) } ?? ""
        for m in BodyMeasurement.allCases {
            lengths[m] = entry[keyPath: m.keyPath].map { show(Units.length($0, unit)) } ?? ""
        }
    }

    private func save() {
        let target = entry ?? BodyEntry(date: date)
        target.date = date
        target.weightKg = parse(weight).map { Units.kg(from: $0, unit) }
        for m in BodyMeasurement.allCases {
            target[keyPath: m.keyPath] = parse(lengths[m] ?? "").map { Units.cm(from: $0, unit) }
        }
        if entry == nil { modelContext.insert(target) }
        dismiss()
    }
}
