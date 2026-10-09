import Foundation
import Observation
import RumbleServices

/// Shop mode: pick a few dinners by swiping, get one shopping list, tick it off.
@MainActor @Observable
public final class PlanStore {
    public let targetCount: Int

    public private(set) var selected: [Dish] = []
    public private(set) var shoppingList: ShoppingList?
    public private(set) var isBuilding = false
    public private(set) var errorMessage: String?

    @ObservationIgnored private let plans: any PlanService
    @ObservationIgnored private let pantry: any PantryService
    @ObservationIgnored private let persistence: (any ShoppingListPersistence)?

    public init(
        plans: any PlanService,
        pantry: any PantryService,
        persistence: (any ShoppingListPersistence)? = nil,
        targetCount: Int = 3
    ) {
        self.plans = plans
        self.pantry = pantry
        self.persistence = persistence
        self.targetCount = targetCount
    }

    public var checkedCount: Int { shoppingList?.items.filter(\.isChecked).count ?? 0 }

    /// Brings back the list saved by a previous launch, so it is still there in the shop.
    public func restore() async {
        guard shoppingList == nil, let saved = try? await persistence?.loadShoppingList() else { return }
        shoppingList = saved
    }

    /// Adds a dinner; builds the plan once the target count is reached.
    public func add(_ dish: Dish) {
        guard selected.count < targetCount, !selected.contains(dish) else { return }
        selected.append(dish)
        if selected.count == targetCount {
            Task { await buildPlan() }
        }
    }

    public func buildPlan() async {
        guard !isBuilding else { return }
        isBuilding = true
        errorMessage = nil
        defer { isBuilding = false }
        let plans = plans
        let ids = selected.map(\.id)
        do {
            shoppingList = try await withRetry {
                let plan = try await plans.buildPlan(dishIDs: ids)
                return try await plans.shoppingList(planID: plan.id)
            }
            persist()
        } catch {
            errorMessage = error.rumbleUserMessage
        }
    }

    public func toggle(itemID: String) {
        guard let index = shoppingList?.items.firstIndex(where: { $0.id == itemID }) else { return }
        shoppingList?.items[index].isChecked.toggle()
        persist()
    }

    private func persist() {
        guard let persistence else { return }
        let list = shoppingList
        Task { try? await persistence.saveShoppingList(list) }
    }

    /// Shopping fills the pantry: everything ticked off goes into it, then the plan resets.
    public func finishShopping() async {
        let bought = (shoppingList?.items ?? []).filter(\.isChecked)
        let changes = bought.map { PantryChange.upsert(PantryItem(name: $0.name, amount: $0.amount)) }
        do {
            try await pantry.apply(changes)
            selected = []
            shoppingList = nil
            persist()
        } catch {
            errorMessage = error.rumbleUserMessage
        }
    }
}
