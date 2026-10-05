import SwiftData
import SwiftUI

/// Gear button for the top-right of each tab; opens Settings as a sheet.
struct SettingsButton: View {
    @State private var showing = false

    var body: some View {
        Button { showing = true } label: {
            Image(systemName: "gearshape").font(.title3)
        }
        .accessibilityLabel("Settings")
        .sheet(isPresented: $showing) { SettingsView() }
    }
}

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage(SettingsKey.startDate) private var startTimestamp: Double = 0
    @AppStorage(SettingsKey.repeats) private var repeats = true
    @AppStorage(SettingsKey.unit) private var unit = "lb"
    @Query(sort: \Workout.order) private var workouts: [Workout]

    private var startDate: Binding<Date> {
        Binding(get: { Date(timeIntervalSince1970: startTimestamp) },
                set: { startTimestamp = Calendar.current.startOfDay(for: $0).timeIntervalSince1970 })
    }

    private var todayDayNumber: Int? {
        Schedule(startDate: startDate.wrappedValue, repeats: repeats).programDayNumber(for: .now)
    }

    private var iCloudSignedIn: Bool { FileManager.default.ubiquityIdentityToken != nil }

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
                        let days = Program.days(from: workouts)
                        ForEach(1...Program.cycleLength, id: \.self) { n in
                            Text(label(for: n, days: days)).tag(n)
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

                Section {
                    Label(iCloudSignedIn ? "Syncing with iCloud" : "Not signed in to iCloud",
                          systemImage: iCloudSignedIn ? "checkmark.icloud" : "icloud.slash")
                        .foregroundStyle(iCloudSignedIn ? Color.primary : .secondary)
                } header: {
                    Text("iCloud")
                } footer: {
                    Text(iCloudSignedIn
                         ? "Your workouts, exercises, logs and body check-ins are saved to your iCloud account and restored on any iPhone signed in to it."
                         : "Sign in to iCloud in the Settings app to back up your workouts and history. Until then, data stays on this iPhone.")
                }

                Section("About") {
                    NavigationLink("Acknowledgements") { AcknowledgementsView() }
                    LabeledContent("Version", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "")
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
    }

    private func label(for n: Int, days: [Int: ProgramDay]) -> String {
        let week = (n - 1) / 7 + 1
        let name = days[n].map { WorkoutCategory(title: $0.title).rawValue } ?? "Rest"
        return "Day \(n) · W\(week) · \(name)"
    }
}

/// Credits required by the Creative Commons licence of the exercise drawings.
struct AcknowledgementsView: View {
    var body: some View {
        List {
            Section {
                Text("Exercise drawings are by Everkinetic (created by Greg Priday), with one by wger.de, obtained through the open-source wger project. They're used under the Creative Commons Attribution-ShareAlike 3.0 licence. The start and end positions have been placed side by side.")
                Link("Everkinetic", destination: URL(string: "https://everkinetic.com")!)
                Link("wger — open-source fitness", destination: URL(string: "https://wger.de")!)
                Link("CC BY-SA 3.0 licence", destination: URL(string: "https://creativecommons.org/licenses/by-sa/3.0/")!)
            } header: {
                Text("Exercise illustrations")
            } footer: {
                Text("Some exercises show a drawing of a closely related movement. Photos you add yourself stay private to your devices and iCloud.")
            }
            Section("Calorie estimates") {
                Text("Estimates use MET values from the Compendium of Physical Activities (Ainsworth et al.). With an Apple Watch, the app uses the active energy the Watch recorded.")
            }
        }
        .navigationTitle("Acknowledgements")
        .navigationBarTitleDisplayMode(.inline)
    }
}
