import SwiftData
import SwiftUI
import UserNotifications

@main
struct TrainerApp: App {
    @UIApplicationDelegateAdaptor private var appDelegate: AppDelegate
    @State private var restTimer = RestTimer()

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
        }
        .modelContainer(for: [SetLog.self, ExerciseTiming.self])
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
    var body: some View {
        TabView {
            TodayView()
                .tabItem { Label("Today", systemImage: "dumbbell.fill") }
            CalendarScreen()
                .tabItem { Label("Calendar", systemImage: "calendar") }
            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape") }
        }
    }
}
