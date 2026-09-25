import Foundation
import Observation
import UIKit
import UserNotifications

/// Countdown between sets. Fires a local notification so it still alerts while
/// you're in another app or the phone is locked.
@Observable
final class RestTimer {
    private(set) var endDate: Date?
    private(set) var total: Int = 0
    private var startedAt: Date?
    private var generation = 0
    /// Sets ticked within this many seconds of each other count as one batch
    /// (e.g. catching up on logging): the running rest isn't restarted.
    private static let batchWindow: TimeInterval = 10
    private static let notificationID = "rest-timer"

    var isRunning: Bool { endDate != nil }

    func start(seconds: Int) {
        guard seconds > 0 else { return }
        if isRunning, let startedAt, Date.now.timeIntervalSince(startedAt) < Self.batchWindow { return }
        startedAt = .now
        total = seconds
        schedule(until: .now.addingTimeInterval(TimeInterval(seconds)))
    }

    func add(seconds: Int) {
        guard let endDate else { return }
        let newEnd = max(Date.now, endDate).addingTimeInterval(TimeInterval(seconds))
        total = max(total + seconds, 1)
        schedule(until: newEnd)
    }

    func skip() {
        generation += 1
        endDate = nil
        startedAt = nil
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [Self.notificationID])
    }

    private func schedule(until end: Date) {
        generation += 1
        let gen = generation
        endDate = end

        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [Self.notificationID])
        let content = UNMutableNotificationContent()
        content.title = "Rest over"
        content.body = "Time for your next set 💪"
        content.sound = .default
        let interval = max(end.timeIntervalSinceNow, 1)
        center.add(UNNotificationRequest(identifier: Self.notificationID, content: content,
                                         trigger: UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)))

        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(interval))
            guard let self, self.generation == gen else { return }
            self.endDate = nil
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        }
    }
}
