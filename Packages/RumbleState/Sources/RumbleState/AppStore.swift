import Foundation
import Observation
import RumbleServices

/// Root store: the Cook / Shop switch, both decks, the match, and the active cooking session.
@MainActor @Observable
public final class AppStore {
    public enum Mode: Hashable, Sendable { case cook, shop }

    public var mode: Mode = .cook
    public let cookDeck: DeckStore
    public let shopDeck: DeckStore
    public let plan: PlanStore

    /// The dish the user just matched in cook mode.
    public private(set) var match: Dish?
    public private(set) var cooking: CookingStore?
    public private(set) var pantryItems: [PantryItem] = []
    public var errorMessage: String?

    @ObservationIgnored private let services: AppServices

    public init(services: AppServices) {
        self.services = services
        let outbox = SwipeOutbox(deck: services.deck)
        cookDeck = DeckStore(mode: .cook, deck: services.deck, outbox: outbox)
        shopDeck = DeckStore(mode: .shop, deck: services.deck, outbox: outbox)
        plan = PlanStore(plans: services.plans, pantry: services.pantry)

        cookDeck.onAccept = { [weak self] dish in self?.match = dish }
        shopDeck.onAccept = { [weak self] dish in self?.plan.add(dish) }
    }

    public func start() async {
        cookDeck.start()
        await loadPantry()
    }

    public func loadPantry() async {
        if let items = try? await services.pantry.items() {
            pantryItems = items
        }
    }

    public func dismissMatch() { match = nil }

    /// Loads the whole recipe into the local session, then switches to cooking.
    public func startCooking(_ dish: Dish) async {
        let recipes = services.recipes
        do {
            let recipe = try await withRetry { try await recipes.recipe(id: dish.id) }
            cooking = CookingStore(recipe: recipe, pantry: services.pantry, notifier: services.notifier)
            match = nil
        } catch {
            errorMessage = error.rumbleUserMessage
        }
    }

    public func finishCooking() async {
        await cooking?.finish()
        cooking = nil
        await loadPantry()
    }

    public func cancelCooking() {
        guard let cooking else { return }
        for timer in cooking.timers { cooking.cancelTimer(id: timer.id) }
        self.cooking = nil
    }

    public func finishShopping() async {
        await plan.finishShopping()
        await loadPantry()
    }
}
