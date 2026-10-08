import Foundation

public struct FakeDeckService: DeckService {
    private let streamDelay: Duration

    public init(streamDelay: Duration = .milliseconds(60)) {
        self.streamDelay = streamDelay
    }

    public func streamDeck(mode: DeckMode) -> AsyncThrowingStream<Dish, Error> {
        let dishes = mode == .cook ? SampleData.dishes.filter(\.canCookNow) : SampleData.dishes
        let delay = streamDelay
        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    for dish in dishes {
                        try await Task.sleep(for: delay)
                        continuation.yield(dish)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    public func recordSwipe(_ swipe: Swipe) async throws {}
}

public struct FakeRecipeService: RecipeService {
    public init() {}

    public func recipe(id: String) async throws -> Recipe {
        guard let recipe = SampleData.recipes.first(where: { $0.id == id }) else {
            throw ServiceError.notFound(id)
        }
        return recipe
    }
}

public actor FakePlanService: PlanService {
    private var plans: [String: Plan] = [:]
    private let pantryIDs: Set<String>

    public init(pantryIDs: Set<String> = Set(SampleData.pantry.map(\.id))) {
        self.pantryIDs = pantryIDs
    }

    public func buildPlan(dishIDs: [String]) async throws -> Plan {
        let dishes = dishIDs.compactMap { id in SampleData.dishes.first { $0.id == id } }
        let plan = Plan(id: UUID().uuidString, dishes: dishes)
        plans[plan.id] = plan
        return plan
    }

    /// Everything the plan's recipes need that the pantry lacks, once per ingredient.
    public func shoppingList(planID: String) async throws -> ShoppingList {
        guard let plan = plans[planID] else { throw ServiceError.notFound(planID) }
        var items: [ShoppingItem] = []
        var seen = pantryIDs
        for dish in plan.dishes {
            guard let recipe = SampleData.recipes.first(where: { $0.id == dish.id }) else { continue }
            for ingredient in recipe.ingredients where seen.insert(ingredient.id).inserted {
                items.append(ShoppingItem(id: ingredient.id, name: ingredient.name, amount: ingredient.amount))
            }
        }
        return ShoppingList(planID: planID, items: items)
    }
}

public actor InMemoryPantryService: PantryService {
    private var storage: [String: PantryItem]

    public init(items: [PantryItem] = SampleData.pantry) {
        storage = Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0) })
    }

    public func items() async throws -> [PantryItem] {
        storage.values.sorted { $0.name < $1.name }
    }

    public func apply(_ changes: [PantryChange]) async throws {
        for change in changes {
            switch change {
            case .upsert(let item): storage[item.id] = item
            case .remove(let id): storage[id] = nil
            }
        }
    }
}

@MainActor
public struct NoopTimerNotifier: TimerNotifier {
    public init() {}
    public func schedule(id: String, title: String, fireDate: Date) {}
    public func cancel(id: String) {}
}
