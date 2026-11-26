import Foundation
import UserNotifications

/// "Drink some water" — one quiet notification an hour, switched on in
/// Settings. Scheduled with the system, so it keeps arriving even while
/// ARC is busy; turning it off removes the pending request.
@MainActor
final class WaterReminder {

    private static let requestID = "arc.water.reminder"

    private var observer: Task<Void, Never>?
    private var lastEnabled: Bool?

    init() {

        apply()

        observer = Task { [weak self] in
            for await _ in NotificationCenter.default.notifications(
                named: UserDefaults.didChangeNotification
            ) {
                self?.apply()
            }
        }
    }

    deinit {
        observer?.cancel()
    }

    private func apply() {

        let enabled = UserDefaults.standard.bool(forKey: AppSettings.Key.waterReminderEnabled)

        // `UserDefaults` posts for every write in the app.
        guard enabled != lastEnabled else { return }

        lastEnabled = enabled

        let center = UNUserNotificationCenter.current()

        guard enabled else {
            center.removePendingNotificationRequests(withIdentifiers: [Self.requestID])
            return
        }

        center.requestAuthorization(options: [.alert, .sound]) { granted, _ in

            guard granted else { return }

            let content = UNMutableNotificationContent()
            content.title = "Time for some water"
            content.body = "A glass now keeps the afternoon slump away."
            content.sound = .default

            let request = UNNotificationRequest(
                identifier: Self.requestID,
                content: content,
                trigger: UNTimeIntervalNotificationTrigger(timeInterval: 3600, repeats: true)
            )

            center.add(request)
        }
    }
}
