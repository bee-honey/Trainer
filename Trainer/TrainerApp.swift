import SwiftData
import SwiftUI
import UserNotifications

@main
struct TrainerApp: App {
    @UIApplicationDelegateAdaptor private var appDelegate: AppDelegate
    @State private var restTimer = RestTimer()
    @State private var health = HealthManager()

    init() {
        // First launch: the program starts today (changeable in Settings).
        let defaults = UserDefaults.standard
        if defaults.object(forKey: SettingsKey.startDate) == nil {
            defaults.set(Calendar.current.startOfDay(for: .now).timeIntervalSince1970, forKey: SettingsKey.startDate)
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(restTimer)
                .environment(health)
        }
        .modelContainer(for: [SetLog.self, ExerciseTiming.self, BodyEntry.self])
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
            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape") }
                .tag(3)
        }
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
