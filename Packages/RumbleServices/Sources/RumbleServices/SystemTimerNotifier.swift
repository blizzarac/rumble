import Foundation
import UserNotifications

/// Local notification that fires when a cooking timer ends, even with the app in the background.
@MainActor
public final class SystemTimerNotifier: TimerNotifier {
    private var didRequestAuthorization = false

    public init() {}

    public func schedule(id: String, title: String, fireDate: Date) {
        let center = UNUserNotificationCenter.current()
        let needsAuthorization = !didRequestAuthorization
        didRequestAuthorization = true

        let content = UNMutableNotificationContent()
        content.title = title
        content.sound = .default
        let interval = max(1, fireDate.timeIntervalSinceNow)
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)
        let request = UNNotificationRequest(identifier: id, content: content, trigger: trigger)

        Task {
            if needsAuthorization {
                _ = try? await center.requestAuthorization(options: [.alert, .sound])
            }
            try? await center.add(request)
        }
    }

    public func cancel(id: String) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [id])
    }
}
