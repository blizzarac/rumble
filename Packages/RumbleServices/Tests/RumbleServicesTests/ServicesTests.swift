import Foundation
import Testing
@testable import RumbleServices

/// Thread-safe counter for use inside @Sendable closures.
private final class Counter: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0
    func increment() -> Int { lock.lock(); defer { lock.unlock() }; value += 1; return value }
    var current: Int { lock.lock(); defer { lock.unlock() }; return value }
}

@Suite struct RetryTests {
    @Test func retriesUnavailableThenSucceeds() async throws {
        let calls = Counter()
        let result = try await withRetry(sleep: { _ in }) {
            if calls.increment() < 3 { throw ServiceError.unavailable }
            return "ok"
        }
        #expect(result == "ok")
        #expect(calls.current == 3)
    }

    @Test func doesNotRetryOtherErrors() async {
        let calls = Counter()
        await #expect(throws: ServiceError.unauthenticated) {
            try await withRetry(sleep: { _ in }) {
                _ = calls.increment()
                throw ServiceError.unauthenticated
            } as Int
        }
        #expect(calls.current == 1)
    }

    @Test func givesUpAfterMaxAttempts() async {
        let calls = Counter()
        let policy = RetryPolicy(maxAttempts: 3, baseDelay: .milliseconds(1), multiplier: 2)
        await #expect(throws: ServiceError.deadlineExceeded) {
            try await withRetry(policy: policy, sleep: { _ in }) {
                _ = calls.increment()
                throw ServiceError.deadlineExceeded
            } as Int
        }
        #expect(calls.current == 3)
    }

    @Test func backoffDoubles() {
        let policy = RetryPolicy(maxAttempts: 4, baseDelay: .milliseconds(100), multiplier: 2)
        #expect(policy.delay(afterAttempt: 1) == .milliseconds(100))
        #expect(policy.delay(afterAttempt: 3) == .milliseconds(400))
    }
}

/// Fails while `isOnline` is false, records what arrives.
private actor FlakyDeck: DeckService {
    var isOnline = false
    private(set) var received: [String] = []

    func setOnline(_ value: Bool) { isOnline = value }

    nonisolated func streamDeck(mode: DeckMode) -> AsyncThrowingStream<Dish, Error> {
        AsyncThrowingStream { $0.finish() }
    }

    func recordSwipe(_ swipe: Swipe) async throws {
        guard isOnline else { throw ServiceError.unavailable }
        received.append(swipe.dishID)
    }
}

@Suite struct OutboxTests {
    @Test func keepsSwipesQueuedOfflineAndSendsInOrderOnFlush() async {
        let deck = FlakyDeck()
        let outbox = SwipeOutbox(deck: deck)
        await outbox.enqueue(Swipe(dishID: "a", direction: .yes, date: .now))
        await outbox.enqueue(Swipe(dishID: "b", direction: .no, date: .now))
        #expect(await outbox.pendingCount == 2)

        await deck.setOnline(true)
        await outbox.flush()
        #expect(await outbox.pendingCount == 0)
        #expect(await deck.received == ["a", "b"])
    }
}

@Suite struct SampleDataTests {
    @Test func someDishesCanBeCookedNowAndSomeCannot() {
        #expect(SampleData.dishes.contains { $0.canCookNow })
        #expect(SampleData.dishes.contains { !$0.canCookNow })
    }

    @Test func everyDishHasARecipe() async throws {
        let service = FakeRecipeService()
        for dish in SampleData.dishes {
            let recipe = try await service.recipe(id: dish.id)
            #expect(!recipe.steps.isEmpty)
        }
    }

    @Test func shoppingListContainsOnlyWhatThePantryLacks() async throws {
        let plans = FakePlanService()
        let plan = try await plans.buildPlan(dishIDs: ["fried-rice", "chicken-curry"])
        let list = try await plans.shoppingList(planID: plan.id)
        let names = Set(list.items.map(\.name))
        #expect(names.contains("Soy sauce"))
        #expect(names.contains("Coconut milk"))
        #expect(!names.contains("Rice"))
        #expect(!names.contains("Onion"))
    }

    @Test func fakeDeckOnlyOffersCookableDishesInCookMode() async throws {
        let deck = FakeDeckService(streamDelay: .zero)
        var seen: [Dish] = []
        for try await dish in deck.streamDeck(mode: .cook) { seen.append(dish) }
        #expect(!seen.isEmpty)
        #expect(seen.allSatisfy(\.canCookNow))
    }
}

@Suite struct PantryTests {
    @Test func swiftDataPantryRoundTrips() async throws {
        let container = try RumbleStorage.makeContainer(inMemory: true)
        let pantry = SwiftDataPantryService(modelContainer: container)
        try await pantry.seedIfEmpty(SampleData.pantry)
        #expect(try await pantry.items().count == SampleData.pantry.count)

        try await pantry.apply([.remove(id: "eggs"), .upsert(PantryItem(name: "Flour", amount: "1 kg"))])
        let names = try await pantry.items().map(\.name)
        #expect(!names.contains("Eggs"))
        #expect(names.contains("Flour"))

        // Seeding again must not duplicate.
        try await pantry.seedIfEmpty(SampleData.pantry)
        #expect(try await pantry.items().count == SampleData.pantry.count)
    }
}
