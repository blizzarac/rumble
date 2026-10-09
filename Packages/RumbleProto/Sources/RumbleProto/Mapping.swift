import Foundation
import GRPCCore
import RumbleServices

// The generated types are internal to this module on purpose: nothing outside RumbleProto
// ever sees `Rumble_V1_*`. These conversions are the only place wire and domain types meet.

extension Dish {
    init(_ card: Rumble_V1_DishCard) {
        self.init(
            id: card.id,
            title: card.title,
            summary: card.summary,
            imageURL: card.imageURL.isEmpty ? nil : URL(string: card.imageURL),
            minutes: Int(card.minutes),
            missingIngredients: card.missingIngredients
        )
    }
}

extension Recipe {
    init(_ recipe: Rumble_V1_Recipe) {
        self.init(
            id: recipe.id,
            title: recipe.title,
            summary: recipe.summary,
            minutes: Int(recipe.minutes),
            imageURL: recipe.imageURL.isEmpty ? nil : URL(string: recipe.imageURL),
            ingredients: recipe.ingredients.map { Ingredient(name: $0.name, amount: $0.amount) },
            steps: recipe.steps.enumerated().map { index, step in
                // Zero on the wire means "no timer".
                RecipeStep(id: index, instruction: step.instruction, timerSeconds: step.timerSeconds > 0 ? Int(step.timerSeconds) : nil)
            }
        )
    }
}

extension Plan {
    init(_ plan: Rumble_V1_Plan) {
        self.init(id: plan.id, dishes: plan.dishes.map(Dish.init))
    }
}

extension ShoppingList {
    init(_ list: Rumble_V1_ShoppingList) {
        self.init(
            planID: list.planID,
            items: list.items.map { ShoppingItem(id: $0.id, name: $0.name, amount: $0.amount) }
        )
    }
}

extension PantryItem {
    init(_ item: Rumble_V1_PantryItem) {
        self.init(id: item.id, name: item.name, amount: item.amount)
    }
}

extension Rumble_V1_PantryChange {
    init(_ change: PantryChange) {
        self.init()
        switch change {
        case .upsert(let item):
            var wire = Rumble_V1_PantryItem()
            wire.id = item.id
            wire.name = item.name
            wire.amount = item.amount
            self.change = .upsert(wire)
        case .remove(let id):
            self.change = .removeID(id)
        }
    }
}

extension Rumble_V1_Swipe {
    init(_ swipe: Swipe) {
        self.init()
        dishID = swipe.dishID
        direction = swipe.direction == .yes ? .yes : .no
        swipedAtUnixMs = Int64(swipe.date.timeIntervalSince1970 * 1000)
    }
}

extension Rumble_V1_DeckMode {
    init(_ mode: DeckMode) {
        self = mode == .cook ? .cook : .shop
    }
}

/// Maps gRPC status codes onto the errors the rest of the app understands, so retry,
/// token refresh and the user-facing messages work the same for every transport.
func mapRPCError(_ error: Error) -> Error {
    guard let rpc = error as? RPCError else { return error }
    switch rpc.code {
    case .unavailable: return ServiceError.unavailable
    case .deadlineExceeded: return ServiceError.deadlineExceeded
    case .unauthenticated: return ServiceError.unauthenticated
    case .notFound: return ServiceError.notFound(rpc.message)
    default: return ServiceError.failed(rpc.message)
    }
}
