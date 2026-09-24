import SwiftUI

struct SettingsView: View {
    @AppStorage(SettingsKey.startDate) private var startTimestamp: Double = 0
    @AppStorage(SettingsKey.repeats) private var repeats = true
    @AppStorage(SettingsKey.unit) private var unit = "lb"

    private var startDate: Binding<Date> {
        Binding(get: { Date(timeIntervalSince1970: startTimestamp) },
                set: { startTimestamp = Calendar.current.startOfDay(for: $0).timeIntervalSince1970 })
    }

    private var todayDayNumber: Int? {
        Schedule(startDate: startDate.wrappedValue, repeats: repeats).programDayNumber(for: .now)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    DatePicker("Day 1 starts on", selection: startDate, displayedComponents: .date)
                    Toggle("Repeat after 5 weeks", isOn: $repeats)
                    Picker("Today is program day", selection: Binding(
                        get: { todayDayNumber ?? 0 },
                        set: { n in
                            guard n > 0 else { return }
                            startDate.wrappedValue = Calendar.current.date(byAdding: .day, value: -(n - 1), to: .now)!
                        })) {
                        if todayDayNumber == nil { Text("—").tag(0) }
                        ForEach(1...Program.cycleLength, id: \.self) { n in
                            Text(label(for: n)).tag(n)
                        }
                    }
                } header: {
                    Text("Program schedule")
                } footer: {
                    Text("High Intensity Volume Training: 5 weeks, 6 training days + 1 rest day per week.")
                }

                Section {
                    Picker("Unit", selection: $unit) {
                        Text("lb").tag("lb")
                        Text("kg").tag("kg")
                    }
                    .pickerStyle(.segmented)
                } header: {
                    Text("Units")
                } footer: {
                    Text("lb uses inches for body measurements. kg uses centimetres.")
                }
            }
            .navigationTitle("Settings")
        }
    }

    private func label(for n: Int) -> String {
        let week = (n - 1) / 7 + 1
        let name = Program.days[n].map { WorkoutCategory(title: $0.title).rawValue } ?? "Rest"
        return "Day \(n) · W\(week) · \(name)"
    }
}
