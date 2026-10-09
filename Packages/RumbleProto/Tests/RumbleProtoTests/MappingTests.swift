import Foundation
import GRPCCore
import Testing
import RumbleServices
@testable import RumbleProto

@Suite struct MappingTests {
    @Test func dishCardBecomesDish() {
        var card = Rumble_V1_DishCard()
        card.id = "d1"
        card.title = "Soup"
        card.summary = "Warm"
        card.imageURL = "https://cdn.example.com/soup.jpg"
        card.minutes = 25
        card.missingIngredients = ["Leek"]
        let dish = Dish(card)
        #expect(dish.id == "d1")
        #expect(dish.minutes == 25)
        #expect(dish.imageURL?.host == "cdn.example.com")
        #expect(dish.missingIngredients == ["Leek"])
        #expect(!dish.canCookNow)
    }

    @Test func emptyImageURLIsNil() {
        #expect(Dish(Rumble_V1_DishCard()).imageURL == nil)
    }

    @Test func zeroTimerMeansNoTimer() {
        var recipe = Rumble_V1_Recipe()
        var boil = Rumble_V1_RecipeStep()
        boil.instruction = "Boil"
        boil.timerSeconds = 600
        var serve = Rumble_V1_RecipeStep()
        serve.instruction = "Serve"
        recipe.steps = [boil, serve]
        let mapped = Recipe(recipe)
        #expect(mapped.steps.map(\.timerSeconds) == [600, nil])
        #expect(mapped.steps.map(\.id) == [0, 1])
    }

    @Test func swipeKeepsDirectionAndTime() {
        let swipe = Swipe(dishID: "d1", direction: .yes, date: Date(timeIntervalSince1970: 12))
        let wire = Rumble_V1_Swipe(swipe)
        #expect(wire.dishID == "d1")
        #expect(wire.direction == .yes)
        #expect(wire.swipedAtUnixMs == 12_000)
    }

    @Test func pantryChangesRoundTrip() {
        let upsert = Rumble_V1_PantryChange(.upsert(PantryItem(name: "Flour", amount: "1 kg")))
        if case .upsert(let item)? = upsert.change {
            #expect(PantryItem(item) == PantryItem(name: "Flour", amount: "1 kg"))
        } else {
            Issue.record("expected an upsert")
        }
        let remove = Rumble_V1_PantryChange(.remove(id: "eggs"))
        if case .removeID(let id)? = remove.change {
            #expect(id == "eggs")
        } else {
            Issue.record("expected a remove")
        }
    }

    @Test func statusCodesMapToServiceErrors() {
        #expect(mapRPCError(RPCError(code: .unavailable, message: "")) as? ServiceError == .unavailable)
        #expect(mapRPCError(RPCError(code: .deadlineExceeded, message: "")) as? ServiceError == .deadlineExceeded)
        #expect(mapRPCError(RPCError(code: .unauthenticated, message: "")) as? ServiceError == .unauthenticated)
        #expect(mapRPCError(RPCError(code: .notFound, message: "x")) as? ServiceError == .notFound("x"))
        #expect(mapRPCError(RPCError(code: .internalError, message: "boom")) as? ServiceError == .failed("boom"))
    }

    @Test func backendSpecParsing() {
        let config = BackendConfig(parsing: "api.example.com:443")
        #expect(config?.host == "api.example.com")
        #expect(config?.port == 443)
        #expect(config?.useTLS == true)
        #expect(BackendConfig(parsing: "nope") == nil)
        #expect(BackendConfig(parsing: ":443") == nil)
        #expect(BackendConfig(parsing: "host:abc") == nil)
    }
}
