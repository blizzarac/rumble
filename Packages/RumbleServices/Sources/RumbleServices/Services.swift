import Foundation

/// Views and stores only ever see these protocols. The real implementations
/// wrap the generated gRPC clients; previews and tests use the fakes.

public protocol DeckService: Sendable {
    /// Cards arrive as the backend picks them, so the next card is ready before the current one is swiped away.
    func streamDeck(mode: DeckMode) -> AsyncThrowingStream<Dish, Error>
    /// Fire-and-forget with a short deadline (2 s).
    func recordSwipe(_ swipe: Swipe) async throws
}

public protocol RecipeService: Sendable {
    func recipe(id: String) async throws -> Recipe
}

public protocol PlanService: Sendable {
    func buildPlan(dishIDs: [String]) async throws -> Plan
    func shoppingList(planID: String) async throws -> ShoppingList
}

public protocol PantryService: Sendable {
    func items() async throws -> [PantryItem]
    func apply(_ changes: [PantryChange]) async throws
}

/// Schedules the local notification that fires when a cooking timer ends.
@MainActor
public protocol TimerNotifier {
    func schedule(id: String, title: String, fireDate: Date)
    func cancel(id: String)
}

public enum ServiceError: Error, Sendable, Equatable {
    case unavailable
    case deadlineExceeded
    case unauthenticated
    case notFound(String)
    case failed(String)

    /// `unavailable` and `deadlineExceeded` retry with backoff; everything else surfaces to the UI.
    public var isRetryable: Bool {
        switch self {
        case .unavailable, .deadlineExceeded: true
        case .unauthenticated, .notFound, .failed: false
        }
    }

    public var userMessage: String {
        switch self {
        case .unavailable, .deadlineExceeded: "Can't reach Rumble right now. Check your connection."
        case .unauthenticated: "Please sign in again."
        case .notFound: "We couldn't find that."
        case .failed: "Something went wrong."
        }
    }
}

public extension Error {
    var rumbleUserMessage: String {
        (self as? ServiceError)?.userMessage ?? "Something went wrong."
    }
}
