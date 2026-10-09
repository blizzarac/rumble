import Foundation
import Testing
import RumbleServices
@testable import RumbleState

/// Records scheduled and cancelled notifications.
@MainActor
final class RecordingNotifier: TimerNotifier {
    private(set) var scheduled: [String] = []
    private(set) var cancelled: [String] = []
    func schedule(id: String, title: String, fireDate: Date) { scheduled.append(id) }
    func cancel(id: String) { cancelled.append(id) }
}

@MainActor
private func waitUntil(_ condition: () -> Bool) async {
    for _ in 0..<200 where !condition() {
        try? await Task.sleep(for: .milliseconds(10))
    }
}

@MainActor @Suite struct CookTimerTests {
    @Test func remainingCountsDownToZero() {
        let end = Date(timeIntervalSince1970: 1_000)
        let timer = CookTimer(id: "t", label: "t", endDate: end)
        #expect(timer.remaining(at: end.addingTimeInterval(-30)) == 30)
        #expect(timer.remaining(at: end.addingTimeInterval(5)) == 0)
        #expect(timer.isFinished(at: end))
        #expect(!timer.isFinished(at: end.addingTimeInterval(-1)))
    }
}

@MainActor @Suite struct CookingStoreTests {
    private func makeStore(notifier: RecordingNotifier = .init(), pantry: InMemoryPantryService = .init()) -> CookingStore {
        let recipe = SampleData.recipes[0]
        return CookingStore(recipe: recipe, pantry: pantry, notifier: notifier, now: { Date(timeIntervalSince1970: 0) })
    }

    @Test func navigationStaysInBounds() {
        let store = makeStore()
        store.back()
        #expect(store.stepIndex == 0)
        for _ in 0..<20 { store.next() }
        #expect(store.isLastStep)
        #expect(store.stepIndex == store.recipe.steps.count - 1)
    }

    @Test func timersStoreEndTimesAndNotify() {
        let notifier = RecordingNotifier()
        let store = makeStore(notifier: notifier)
        let step = store.recipe.steps[0]
        store.startTimer(for: step)
        #expect(store.timers.count == 1)
        #expect(store.timers[0].endDate == Date(timeIntervalSince1970: TimeInterval(step.timerSeconds!)))
        #expect(notifier.scheduled.count == 1)

        store.startTimer(for: store.recipe.steps[1])
        #expect(store.timers.count == 2)

        store.cancelTimer(id: store.timers[0].id)
        #expect(store.timers.count == 1)
        #expect(notifier.cancelled.count == 1)
    }

    @Test func stepsWithoutTimerIgnoreStart() {
        let store = makeStore()
        store.startTimer(for: store.recipe.steps[2])
        #expect(store.timers.isEmpty)
    }

    @Test func finishingRemovesIngredientsFromPantry() async throws {
        let pantry = InMemoryPantryService()
        let store = makeStore(pantry: pantry)
        await store.finish()
        #expect(store.isFinished)
        let names = try await pantry.items().map(\.id)
        #expect(!names.contains("spaghetti"))
        #expect(names.contains("eggs"))
    }
}

@MainActor @Suite struct DeckStoreTests {
    private func makeStore(mode: DeckMode = .shop, bufferSize: Int = 20) -> DeckStore {
        let deck = FakeDeckService(streamDelay: .zero)
        return DeckStore(mode: mode, deck: deck, outbox: SwipeOutbox(deck: deck), bufferSize: bufferSize)
    }

    @Test func fillsBufferAndExhausts() async {
        let store = makeStore()
        store.start()
        await waitUntil { store.isExhausted }
        #expect(store.cards.count == SampleData.dishes.count)
        #expect(store.visibleCards.count == 3)
    }

    @Test func bufferIsCapped() async {
        let store = makeStore(bufferSize: 2)
        store.start()
        await waitUntil { store.cards.count == 2 }
        try? await Task.sleep(for: .milliseconds(50))
        #expect(store.cards.count == 2)
        #expect(!store.isExhausted)
    }

    @Test func swipeYesNotifiesAndNoDoesNot() async {
        let store = makeStore()
        var accepted: [String] = []
        store.onAccept = { accepted.append($0.id) }
        store.start()
        await waitUntil { store.cards.count >= 2 }
        let first = store.cards[0].id
        store.swipe(.yes)
        store.swipe(.no)
        #expect(accepted == [first])
        #expect(store.swipeCount == 2)
    }
}

@MainActor @Suite struct PlanStoreTests {
    @Test func buildsListAfterTargetAndFinishFillsPantry() async throws {
        let pantry = InMemoryPantryService()
        let store = PlanStore(plans: FakePlanService(), pantry: pantry, targetCount: 2)
        let dishes = SampleData.dishes
        let fried = dishes.first { $0.id == "fried-rice" }!
        let caprese = dishes.first { $0.id == "caprese-salad" }!

        store.add(fried)
        #expect(store.shoppingList == nil)
        store.add(caprese)
        await waitUntil { store.shoppingList != nil }

        let list = try #require(store.shoppingList)
        let soy = try #require(list.items.first { $0.name == "Soy sauce" })
        store.toggle(itemID: soy.id)
        #expect(store.checkedCount == 1)

        await store.finishShopping()
        #expect(store.shoppingList == nil)
        #expect(store.selected.isEmpty)
        #expect(try await pantry.items().map(\.id).contains("soy sauce"))
    }
}

@MainActor @Suite struct AppStoreTests {
    @Test func cookMatchThenCookingThenFinishUpdatesPantry() async throws {
        let store = AppStore(services: .fake(streamDelay: .zero))
        await store.start()
        await waitUntil { !store.cookDeck.cards.isEmpty }

        store.cookDeck.swipe(.yes)
        let dish = try #require(store.match)
        await store.startCooking(dish)
        #expect(store.match == nil)
        let cooking = try #require(store.cooking)
        #expect(cooking.recipe.id == dish.id)

        let before = store.pantryItems.count
        await store.finishCooking()
        #expect(store.cooking == nil)
        #expect(store.pantryItems.count < before)
    }

    @Test func shopSwipesFeedThePlan() async {
        let store = AppStore(services: .fake(streamDelay: .zero))
        store.mode = .shop
        store.shopDeck.start()
        await waitUntil { store.shopDeck.cards.count >= 3 }
        store.shopDeck.swipe(.yes)
        store.shopDeck.swipe(.no)
        #expect(store.plan.selected.count == 1)
    }
}

@MainActor
final class RecordingActivities: CookingActivityController {
    private(set) var updates: [[TimerSnapshot]] = []
    private(set) var endCount = 0
    func update(recipeTitle: String, timers: [TimerSnapshot]) { updates.append(timers) }
    func end() { endCount += 1 }
}

@MainActor @Suite struct LiveActivitySyncTests {
    @Test func timersAreMirroredAndActivityEndsWhenNoneLeft() {
        let activities = RecordingActivities()
        let store = CookingStore(
            recipe: SampleData.recipes[0], pantry: InMemoryPantryService(),
            notifier: RecordingNotifier(), activities: activities, now: { Date(timeIntervalSince1970: 0) }
        )
        store.startTimer(for: store.recipe.steps[0])
        store.startTimer(for: store.recipe.steps[1])
        #expect(activities.updates.last?.count == 2)

        store.cancelTimer(id: store.timers[0].id)
        #expect(activities.updates.last?.count == 1)
        store.cancelTimer(id: store.timers[0].id)
        #expect(activities.endCount == 1)
    }
}

@MainActor @Suite struct PersistenceWiringTests {
    @Test func shoppingListIsRestoredAfterRelaunch() async throws {
        let container = try RumbleStorage.makeContainer(inMemory: true)
        let local = SwiftDataLocalStore(modelContainer: container)

        let first = PlanStore(plans: FakePlanService(), pantry: InMemoryPantryService(), persistence: local, targetCount: 1)
        first.add(SampleData.dishes.first { $0.id == "fried-rice" }!)
        await waitUntil { first.shoppingList != nil }
        try? await Task.sleep(for: .milliseconds(50))  // let the save land

        let second = PlanStore(plans: FakePlanService(), pantry: InMemoryPantryService(), persistence: local, targetCount: 1)
        await second.restore()
        #expect(second.shoppingList == first.shoppingList)
    }
}
