import Foundation
import RumbleServices

/// The dependency container passed into the SwiftUI environment. Previews and tests swap in fakes.
public struct AppServices {
    public var deck: any DeckService
    public var recipes: any RecipeService
    public var plans: any PlanService
    public var pantry: any PantryService
    public var notifier: any TimerNotifier

    public init(
        deck: any DeckService,
        recipes: any RecipeService,
        plans: any PlanService,
        pantry: any PantryService,
        notifier: any TimerNotifier
    ) {
        self.deck = deck
        self.recipes = recipes
        self.plans = plans
        self.pantry = pantry
        self.notifier = notifier
    }

    @MainActor
    public static func fake(streamDelay: Duration = .milliseconds(60)) -> AppServices {
        AppServices(
            deck: FakeDeckService(streamDelay: streamDelay),
            recipes: FakeRecipeService(),
            plans: FakePlanService(),
            pantry: InMemoryPantryService(),
            notifier: NoopTimerNotifier()
        )
    }
}
