import Foundation
import Observation
import RumbleServices

/// A running kitchen timer. Stored as an end time, not a countdown, so it stays correct
/// if the app is closed or the phone locks.
public struct CookTimer: Identifiable, Hashable, Sendable {
    public let id: String
    public let label: String
    public let endDate: Date

    public init(id: String, label: String, endDate: Date) {
        self.id = id
        self.label = label
        self.endDate = endDate
    }

    public func remaining(at date: Date) -> TimeInterval { max(0, endDate.timeIntervalSince(date)) }
    public func isFinished(at date: Date) -> Bool { remaining(at: date) == 0 }
}

/// Step-by-step cooking. Reads only from the recipe it was given, so it works with no connection.
@MainActor @Observable
public final class CookingStore {
    public let recipe: Recipe

    /// Bound to the paged step view.
    public var stepIndex = 0
    public private(set) var timers: [CookTimer] = []
    public private(set) var isFinished = false

    @ObservationIgnored private let pantry: any PantryService
    @ObservationIgnored private let notifier: any TimerNotifier
    @ObservationIgnored private let activities: (any CookingActivityController)?
    @ObservationIgnored private let now: @Sendable () -> Date

    public init(
        recipe: Recipe,
        pantry: any PantryService,
        notifier: any TimerNotifier,
        activities: (any CookingActivityController)? = nil,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.recipe = recipe
        self.pantry = pantry
        self.notifier = notifier
        self.activities = activities
        self.now = now
    }

    public var currentStep: RecipeStep { recipe.steps[stepIndex] }
    public var isFirstStep: Bool { stepIndex == 0 }
    public var isLastStep: Bool { stepIndex == recipe.steps.count - 1 }

    public func next() { if !isLastStep { stepIndex += 1 } }
    public func back() { if !isFirstStep { stepIndex -= 1 } }

    public func timer(for step: RecipeStep) -> CookTimer? {
        timers.first { $0.id == timerID(for: step) }
    }

    /// Starts (or restarts) the timer of a step. Several timers can run at once.
    public func startTimer(for step: RecipeStep) {
        guard let seconds = step.timerSeconds else { return }
        let id = timerID(for: step)
        let timer = CookTimer(
            id: id,
            label: "Step \(step.id + 1)",
            endDate: now().addingTimeInterval(TimeInterval(seconds))
        )
        timers.removeAll { $0.id == id }
        timers.append(timer)
        notifier.schedule(id: id, title: "\(recipe.title): timer done", fireDate: timer.endDate)
        syncActivity()
    }

    public func cancelTimer(id: String) {
        timers.removeAll { $0.id == id }
        notifier.cancel(id: id)
        syncActivity()
    }

    /// Cooking empties the pantry: the used ingredients are removed.
    /// TODO: record the dish as cooked for the taste profile once the history service exists.
    public func finish() async {
        for timer in timers { notifier.cancel(id: timer.id) }
        timers = []
        syncActivity()
        try? await pantry.apply(recipe.ingredients.map { .remove(id: $0.id) })
        isFinished = true
    }

    /// Mirrors the running timers to the Lock Screen / Dynamic Island; ends the activity when none are left.
    private func syncActivity() {
        guard let activities else { return }
        if timers.isEmpty {
            activities.end()
        } else {
            activities.update(
                recipeTitle: recipe.title,
                timers: timers.map { TimerSnapshot(id: $0.id, label: $0.label, endDate: $0.endDate) }
            )
        }
    }

    private func timerID(for step: RecipeStep) -> String { "\(recipe.id)-step-\(step.id)" }
}
