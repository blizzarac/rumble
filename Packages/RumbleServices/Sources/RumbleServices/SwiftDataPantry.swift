import Foundation
import SwiftData

@Model
public final class PantryRecord {
    @Attribute(.unique) public var id: String
    public var name: String
    public var amount: String

    public init(id: String, name: String, amount: String) {
        self.id = id
        self.name = name
        self.amount = amount
    }
}

public enum RumbleStorage {
    /// One container for everything stored on the device.
    public static func makeContainer(inMemory: Bool = false) throws -> ModelContainer {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: inMemory)
        return try ModelContainer(
            for: PantryRecord.self, RecipeRecord.self, ShoppingListRecord.self, SwipeRecord.self,
            configurations: configuration
        )
    }
}

/// The pantry on disk, so the app knows what is at home with no connection.
@ModelActor
public actor SwiftDataPantryService: PantryService {
    public func items() async throws -> [PantryItem] {
        let records = try modelContext.fetch(FetchDescriptor<PantryRecord>(sortBy: [SortDescriptor(\.name)]))
        return records.map { PantryItem(id: $0.id, name: $0.name, amount: $0.amount) }
    }

    public func apply(_ changes: [PantryChange]) async throws {
        for change in changes {
            switch change {
            case .upsert(let item):
                if let record = try record(id: item.id) {
                    record.name = item.name
                    record.amount = item.amount
                } else {
                    modelContext.insert(PantryRecord(id: item.id, name: item.name, amount: item.amount))
                }
            case .remove(let id):
                if let record = try record(id: id) {
                    modelContext.delete(record)
                }
            }
        }
        try modelContext.save()
    }

    /// Fills an empty pantry on first launch.
    public func seedIfEmpty(_ items: [PantryItem]) async throws {
        guard try modelContext.fetchCount(FetchDescriptor<PantryRecord>()) == 0 else { return }
        try await apply(items.map { .upsert($0) })
    }

    private func record(id: String) throws -> PantryRecord? {
        var descriptor = FetchDescriptor<PantryRecord>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first
    }
}
