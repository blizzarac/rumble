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
        let allCookable = seen.allSatisfy { $0.canCookNow }
        #expect(allCookable)
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

// MARK: - Auth, deadlines, persistence

private actor CountingRefresher: TokenRefresher {
    private(set) var calls = 0
    let result: Result<AuthToken, ServiceError>

    init(_ result: Result<AuthToken, ServiceError>) { self.result = result }

    func refresh(refreshToken: String) async throws -> AuthToken {
        calls += 1
        try await Task.sleep(for: .milliseconds(30))
        return try result.get()
    }
}

private let fixedNow = Date(timeIntervalSince1970: 10_000)
private func token(_ access: String, expiresIn: TimeInterval) -> AuthToken {
    AuthToken(accessToken: access, refreshToken: "r-\(access)", expiresAt: fixedNow.addingTimeInterval(expiresIn))
}

@Suite struct AuthTests {
    @Test func validTokenIsReturnedWithoutRefresh() async throws {
        let refresher = CountingRefresher(.success(token("new", expiresIn: 3600)))
        let session = AuthSession(store: InMemoryTokenStore(token: token("old", expiresIn: 600)), refresher: refresher, now: { fixedNow })
        #expect(try await session.accessToken() == "old")
        #expect(await refresher.calls == 0)
    }

    @Test func expiringTokenIsRefreshedOnceForConcurrentCallers() async throws {
        let refresher = CountingRefresher(.success(token("new", expiresIn: 3600)))
        let store = InMemoryTokenStore(token: token("old", expiresIn: 5))
        let session = AuthSession(store: store, refresher: refresher, now: { fixedNow })
        async let a = session.accessToken()
        async let b = session.accessToken()
        async let c = session.accessToken()
        let results = try await [a, b, c]
        #expect(results == ["new", "new", "new"])
        #expect(await refresher.calls == 1)
        #expect(await store.load()?.accessToken == "new")
    }

    @Test func rejectedRefreshTokenSignsOut() async {
        let refresher = CountingRefresher(.failure(.unauthenticated))
        let store = InMemoryTokenStore(token: token("old", expiresIn: -1))
        let session = AuthSession(store: store, refresher: refresher, now: { fixedNow })
        await #expect(throws: ServiceError.unauthenticated) { try await session.accessToken() }
        #expect(await store.load() == nil)
    }

    @Test func withAuthRefreshesOnceOnUnauthenticatedAndRetries() async throws {
        let refresher = CountingRefresher(.success(token("new", expiresIn: 3600)))
        let session = AuthSession(store: InMemoryTokenStore(token: token("old", expiresIn: 600)), refresher: refresher, now: { fixedNow })
        let used = try await withAuth(session) { accessToken -> String in
            if accessToken == "old" { throw ServiceError.unauthenticated }
            return accessToken
        }
        #expect(used == "new")
        #expect(await refresher.calls == 1)
    }
}

@Suite struct DeadlineTests {
    @Test func slowOperationTimesOut() async {
        await #expect(throws: ServiceError.deadlineExceeded) {
            try await withDeadline(.milliseconds(30)) {
                try await Task.sleep(for: .seconds(5))
                return 1
            }
        }
    }

    @Test func fastOperationReturns() async throws {
        let value = try await withDeadline(.seconds(5)) { 42 }
        #expect(value == 42)
    }

    @Test func pipelineRetriesTimeoutsThenSucceeds() async throws {
        let session = AuthSession(store: InMemoryTokenStore(token: token("t", expiresIn: 600)), refresher: CountingRefresher(.failure(.unauthenticated)), now: { fixedNow })
        let pipeline = CallPipeline(auth: session, retry: RetryPolicy(maxAttempts: 3, baseDelay: .milliseconds(1), multiplier: 1))
        let calls = Counter()
        let result = try await pipeline.run(deadline: .milliseconds(50)) { accessToken in
            if calls.increment() == 1 { try await Task.sleep(for: .seconds(5)) }
            return accessToken
        }
        #expect(result == "t")
        #expect(calls.current == 2)
    }
}

@Suite struct LocalStoreTests {
    private func makeStore() throws -> SwiftDataLocalStore {
        SwiftDataLocalStore(modelContainer: try RumbleStorage.makeContainer(inMemory: true))
    }

    @Test func recipeCacheRoundTrips() async throws {
        let store = try makeStore()
        let recipe = SampleData.recipes[0]
        #expect(try await store.cachedRecipe(id: recipe.id) == nil)
        try await store.cache(recipe)
        #expect(try await store.cachedRecipe(id: recipe.id) == recipe)
    }

    @Test func shoppingListRoundTripsAndClears() async throws {
        let store = try makeStore()
        let list = ShoppingList(planID: "p", items: [ShoppingItem(id: "soy sauce", name: "Soy sauce", amount: "2 tbsp", isChecked: true)])
        try await store.saveShoppingList(list)
        #expect(try await store.loadShoppingList() == list)
        try await store.saveShoppingList(nil)
        #expect(try await store.loadShoppingList() == nil)
    }

    @Test func swipeQueueKeepsOrder() async throws {
        let store = try makeStore()
        try await store.appendSwipe(Swipe(dishID: "a", direction: .yes, date: .now))
        try await store.appendSwipe(Swipe(dishID: "b", direction: .no, date: .now))
        try await store.removeOldestSwipe()
        #expect(try await store.pendingSwipes().map(\.dishID) == ["b"])
    }

    @Test func outboxSurvivesRelaunch() async throws {
        let store = try makeStore()
        let offline = FlakyDeck()
        let first = SwipeOutbox(deck: offline, storage: store)
        await first.enqueue(Swipe(dishID: "a", direction: .yes, date: .now))
        #expect(await first.pendingCount == 1)

        // New launch, backend reachable again.
        let online = FlakyDeck()
        await online.setOnline(true)
        let second = SwipeOutbox(deck: online, storage: store)
        await second.restore()
        #expect(await online.received == ["a"])
        #expect(try await store.pendingSwipes().isEmpty)
    }

    @Test func cachingRecipeServiceServesCacheWhenRemoteIsDown() async throws {
        struct DownRemote: RecipeService {
            func recipe(id: String) async throws -> Recipe { throw ServiceError.unavailable }
        }
        let store = try makeStore()
        let recipe = SampleData.recipes[1]
        let warm = CachingRecipeService(remote: FakeRecipeService(), cache: store)
        _ = try await warm.recipe(id: recipe.id)

        let offline = CachingRecipeService(remote: DownRemote(), cache: store)
        #expect(try await offline.recipe(id: recipe.id) == recipe)
        await #expect(throws: ServiceError.unavailable) { try await offline.recipe(id: "never-cached") }
    }
}

// MARK: - Image cache

private final class StubURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var requestCount = 0
    private static let lock = NSLock()

    static func reset() { lock.lock(); requestCount = 0; lock.unlock() }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.lock.lock(); Self.requestCount += 1; Self.lock.unlock()
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data("photo".utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

@Suite(.serialized) struct ImageCacheTests {
    private func makeCache() -> ImageCache {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        StubURLProtocol.reset()
        return ImageCache(session: URLSession(configuration: configuration))
    }

    @Test func secondRequestIsServedFromMemory() async throws {
        let cache = makeCache()
        let url = URL(string: "https://cdn.example.com/a.jpg")!
        #expect(try await cache.data(for: url) == Data("photo".utf8))
        _ = try await cache.data(for: url)
        #expect(StubURLProtocol.requestCount == 1)
    }

    @Test func concurrentRequestsShareOneDownload() async throws {
        let cache = makeCache()
        let url = URL(string: "https://cdn.example.com/b.jpg")!
        async let a = cache.data(for: url)
        async let b = cache.data(for: url)
        _ = try await (a, b)
        #expect(StubURLProtocol.requestCount == 1)
    }
}
