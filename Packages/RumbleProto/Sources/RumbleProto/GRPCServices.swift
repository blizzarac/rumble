import Foundation
import GRPCCore
import RumbleServices

struct GRPCDeckService: DeckService {
    let backend: GRPCBackend

    /// Server streaming: cards arrive as the backend picks them.
    func streamDeck(mode: DeckMode) -> AsyncThrowingStream<Dish, Error> {
        let backend = backend
        let request: Rumble_V1_DeckRequest = {
            var request = Rumble_V1_DeckRequest()
            request.mode = Rumble_V1_DeckMode(mode)
            request.limit = 20
            return request
        }()
        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    try await backend.authenticated { metadata in
                        let client = Rumble_V1_DeckService.Client(wrapping: backend.client)
                        try await client.streamDeck(request, metadata: metadata) { response in
                            for try await card in response.messages {
                                continuation.yield(Dish(card))
                            }
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// Unary, short deadline: the outbox queues swipes while this fails.
    func recordSwipe(_ swipe: Swipe) async throws {
        let request = Rumble_V1_Swipe(swipe)
        try await backend.unary(deadline: CallDeadline.swipe) { metadata in
            let client = Rumble_V1_DeckService.Client(wrapping: backend.client)
            _ = try await client.recordSwipe(request, metadata: metadata)
        }
    }
}

struct GRPCRecipeService: RecipeService {
    let backend: GRPCBackend

    func recipe(id: String) async throws -> Recipe {
        let request: Rumble_V1_RecipeId = {
            var request = Rumble_V1_RecipeId()
            request.id = id
            return request
        }()
        return try await backend.unary { metadata in
            let client = Rumble_V1_RecipeService.Client(wrapping: backend.client)
            return Recipe(try await client.getRecipe(request, metadata: metadata))
        }
    }
}

struct GRPCPlanService: PlanService {
    let backend: GRPCBackend

    func buildPlan(dishIDs: [String]) async throws -> Plan {
        let request: Rumble_V1_PlanRequest = {
            var request = Rumble_V1_PlanRequest()
            request.dishIds = dishIDs
            return request
        }()
        return try await backend.unary { metadata in
            let client = Rumble_V1_PlanService.Client(wrapping: backend.client)
            return Plan(try await client.buildPlan(request, metadata: metadata))
        }
    }

    func shoppingList(planID: String) async throws -> ShoppingList {
        let request: Rumble_V1_PlanId = {
            var request = Rumble_V1_PlanId()
            request.id = planID
            return request
        }()
        return try await backend.unary { metadata in
            let client = Rumble_V1_PlanService.Client(wrapping: backend.client)
            return ShoppingList(try await client.getShoppingList(request, metadata: metadata))
        }
    }
}

/// Bidirectional streaming. How the server answers a sync (full state or only changes) is still
/// an open question from the design doc; this assumes the server replies with the current items.
struct GRPCPantryService: PantryService {
    let backend: GRPCBackend

    func items() async throws -> [PantryItem] {
        try await backend.authenticated { metadata in
            let client = Rumble_V1_PantryService.Client(wrapping: backend.client)
            return try await client.syncPantry(metadata: metadata, requestProducer: { _ in }) { response in
                var items: [PantryItem] = []
                for try await change in response.messages {
                    if case .upsert(let item)? = change.change { items.append(PantryItem(item)) }
                }
                return items
            }
        }
    }

    func apply(_ changes: [PantryChange]) async throws {
        let wire = changes.map(Rumble_V1_PantryChange.init)
        try await backend.authenticated { metadata in
            let client = Rumble_V1_PantryService.Client(wrapping: backend.client)
            try await client.syncPantry(
                metadata: metadata,
                requestProducer: { writer in try await writer.write(contentsOf: wire) }
            ) { response in
                for try await _ in response.messages {}
            }
        }
    }
}
