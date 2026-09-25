import SwiftData
import SwiftUI
import UserNotifications

@main
struct TrainerApp: App {
    @UIApplicationDelegateAdaptor private var appDelegate: AppDelegate
    @State private var restTimer = RestTimer()
    @State private var health = HealthManager()
    private let container: ModelContainer

    static let cloudContainerID = "iCloud.com.naveenkeerthy.Trainer"

    init() {
        // First launch: the program starts today (changeable in Settings).
        let defaults = UserDefaults.standard
        if defaults.object(forKey: SettingsKey.startDate) == nil {
            defaults.set(Calendar.current.startOfDay(for: .now).timeIntervalSince1970, forKey: SettingsKey.startDate)
        }
        container = Self.makeContainer()
        ProgramSeeder.prepare(container.mainContext)
    }

    /// Everything syncs to the user's private iCloud database. If CloudKit can't be set up
    /// (no iCloud capability in this build), fall back to the same store on-device only.
    private static func makeContainer() -> ModelContainer {
        let schema = Schema([SetLog.self, ExerciseTiming.self, BodyEntry.self,
                             Exercise.self, ExercisePhoto.self, Workout.self, WorkoutItem.self])
        do {
            return try ModelContainer(for: schema, configurations: [
                ModelConfiguration(schema: schema, cloudKitDatabase: .private(cloudContainerID))
            ])
        } catch {
            print("iCloud sync unavailable, using local storage: \(error)")
            return try! ModelContainer(for: schema, configurations: [
                ModelConfiguration(schema: schema, cloudKitDatabase: .none)
            ])
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(restTimer)
                .environment(health)
        }
        .modelContainer(container)
    }
}

final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        center.requestAuthorization(options: [.alert, .sound]) { _, _ in }
        return true
    }

    // Show the rest-over banner + sound even while the app is open.
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async
        -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }
}

struct RootView: View {
    @State private var tab = RootView.initialTab
    @Environment(\.modelContext) private var modelContext
    @Query private var workouts: [Workout]
    @Query private var exercises: [Exercise]

    var body: some View {
        TabView(selection: $tab) {
            TodayView()
                .tabItem { Label("Today", systemImage: "dumbbell.fill") }
                .tag(0)
            CalendarScreen()
                .tabItem { Label("Calendar", systemImage: "calendar") }
                .tag(1)
            BodyView()
                .tabItem { Label("Body", systemImage: "figure") }
                .tag(2)
            ProgramView()
                .tabItem { Label("Workouts", systemImage: "list.bullet.clipboard") }
                .tag(3)
        }
        // iCloud imports arrive in the background; clean up duplicates when they land.
        .onChange(of: workouts.count) { ProgramSeeder.dedupe(modelContext) }
        .onChange(of: exercises.count) { ProgramSeeder.dedupe(modelContext) }
    }

    /// Debug builds only: `-openTab 2` launches straight into a tab (for simulator screenshots).
    private static var initialTab: Int {
        #if DEBUG
        return UserDefaults.standard.integer(forKey: "openTab")
        #else
        return 0
        #endif
    }
}
