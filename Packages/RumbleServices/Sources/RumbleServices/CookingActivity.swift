import Foundation
#if os(iOS)
import ActivityKit
#endif

/// A running timer as the Lock Screen and Dynamic Island see it.
public struct TimerSnapshot: Codable, Hashable, Sendable, Identifiable {
    public let id: String
    public let label: String
    public let endDate: Date

    public init(id: String, label: String, endDate: Date) {
        self.id = id
        self.label = label
        self.endDate = endDate
    }
}

/// Shows the running cooking timers as a Live Activity. Ends itself when no timer is left.
@MainActor
public protocol CookingActivityController {
    func update(recipeTitle: String, timers: [TimerSnapshot])
    func end()
}

#if os(iOS)
/// Shared between the app and the widget extension, so it lives in this package.
public struct CookingActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable, Sendable {
        public var timers: [TimerSnapshot]

        public init(timers: [TimerSnapshot]) {
            self.timers = timers
        }
    }

    public var recipeTitle: String

    public init(recipeTitle: String) {
        self.recipeTitle = recipeTitle
    }
}

@MainActor
public final class ActivityKitController: CookingActivityController {
    private var activity: Activity<CookingActivityAttributes>?

    public init() {}

    public func update(recipeTitle: String, timers: [TimerSnapshot]) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        let content = ActivityContent(state: CookingActivityAttributes.ContentState(timers: timers), staleDate: nil)
        if let activity {
            Task { await activity.update(content) }
        } else {
            activity = try? Activity.request(
                attributes: CookingActivityAttributes(recipeTitle: recipeTitle),
                content: content
            )
        }
    }

    public func end() {
        guard let activity else { return }
        self.activity = nil
        Task { await activity.end(nil, dismissalPolicy: .immediate) }
    }
}
#endif
