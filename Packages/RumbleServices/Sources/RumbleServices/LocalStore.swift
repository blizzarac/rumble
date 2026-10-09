import Foundation
import SwiftData

/// Recipes already matched or planned, cached whole (steps and timers included) so cooking reads only local data.
public protocol RecipeCache: Sendable {
    func cachedRecipe(id: String) async throws -> Recipe?
    func cache(_ recipe: Recipe) async throws
}

public protocol ShoppingListPersistence: Sendable {
    func loadShoppingList() async throws -> ShoppingList?
    /// `nil` clears the saved list.
    func saveShoppingList(_ list: ShoppingList?) async throws
}

/// Swipes not yet acknowledged by the backend, oldest first.
public protocol SwipeQueueStorage: Sendable {
    func pendingSwipes() async throws -> [Swipe]
    func appendSwipe(_ swipe: Swipe) async throws
    func removeOldestSwipe() async throws
}

@Model
final class RecipeRecord {
    @Attribute(.unique) var id: String
    var data: Data

    init(id: String, data: Data) {
        self.id = id
        self.data = data
    }
}

@Model
final class ShoppingListRecord {
    @Attribute(.unique) var id: String
    var data: Data

    init(id: String, data: Data) {
        self.id = id
        self.data = data
    }
}

@Model
final class SwipeRecord {
    @Attribute(.unique) var seq: Int
    var dishID: String
    var directionRaw: String
    var date: Date

    init(seq: Int, dishID: String, directionRaw: String, date: Date) {
        self.seq = seq
        self.dishID = dishID
        self.directionRaw = directionRaw
        self.date = date
    }
}

private let currentListID = "current"

/// Recipe cache, shopping list and swipe queue on disk.
@ModelActor
public actor SwiftDataLocalStore: RecipeCache, ShoppingListPersistence, SwipeQueueStorage {
    // MARK: RecipeCache

    public func cachedRecipe(id: String) async throws -> Recipe? {
        var descriptor = FetchDescriptor<RecipeRecord>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        guard let record = try modelContext.fetch(descriptor).first else { return nil }
        return try JSONDecoder().decode(Recipe.self, from: record.data)
    }

    public func cache(_ recipe: Recipe) async throws {
        let data = try JSONEncoder().encode(recipe)
        let id = recipe.id
        var descriptor = FetchDescriptor<RecipeRecord>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        if let record = try modelContext.fetch(descriptor).first {
            record.data = data
        } else {
            modelContext.insert(RecipeRecord(id: id, data: data))
        }
        try modelContext.save()
    }

    // MARK: ShoppingListPersistence

    public func loadShoppingList() async throws -> ShoppingList? {
        guard let record = try currentListRecord() else { return nil }
        return try JSONDecoder().decode(ShoppingList.self, from: record.data)
    }

    public func saveShoppingList(_ list: ShoppingList?) async throws {
        let existing = try currentListRecord()
        if let list {
            let data = try JSONEncoder().encode(list)
            if let existing {
                existing.data = data
            } else {
                modelContext.insert(ShoppingListRecord(id: currentListID, data: data))
            }
        } else if let existing {
            modelContext.delete(existing)
        }
        try modelContext.save()
    }

    private func currentListRecord() throws -> ShoppingListRecord? {
        let id = currentListID
        var descriptor = FetchDescriptor<ShoppingListRecord>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first
    }

    // MARK: SwipeQueueStorage

    public func pendingSwipes() async throws -> [Swipe] {
        let records = try modelContext.fetch(FetchDescriptor<SwipeRecord>(sortBy: [SortDescriptor(\.seq)]))
        return records.compactMap { record in
            SwipeDirection(rawValue: record.directionRaw).map {
                Swipe(dishID: record.dishID, direction: $0, date: record.date)
            }
        }
    }

    public func appendSwipe(_ swipe: Swipe) async throws {
        var latest = FetchDescriptor<SwipeRecord>(sortBy: [SortDescriptor(\.seq, order: .reverse)])
        latest.fetchLimit = 1
        let next = (try modelContext.fetch(latest).first?.seq ?? 0) + 1
        modelContext.insert(SwipeRecord(seq: next, dishID: swipe.dishID, directionRaw: swipe.direction.rawValue, date: swipe.date))
        try modelContext.save()
    }

    public func removeOldestSwipe() async throws {
        var oldest = FetchDescriptor<SwipeRecord>(sortBy: [SortDescriptor(\.seq)])
        oldest.fetchLimit = 1
        if let record = try modelContext.fetch(oldest).first {
            modelContext.delete(record)
            try modelContext.save()
        }
    }
}

/// Serves recipes from the local cache first, so cooking works with no connection,
/// and caches whatever the backend returns.
public struct CachingRecipeService: RecipeService {
    private let remote: any RecipeService
    private let cache: any RecipeCache

    public init(remote: any RecipeService, cache: any RecipeCache) {
        self.remote = remote
        self.cache = cache
    }

    public func recipe(id: String) async throws -> Recipe {
        if let cached = try? await cache.cachedRecipe(id: id) { return cached }
        let recipe = try await remote.recipe(id: id)
        try? await cache.cache(recipe)
        return recipe
    }
}
