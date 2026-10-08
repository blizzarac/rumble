import Foundation

public enum DeckMode: String, Sendable, Codable {
    case cook
    case shop
}

public enum SwipeDirection: String, Sendable, Codable {
    case yes
    case no
}

public struct Swipe: Sendable, Hashable, Codable {
    public let dishID: String
    public let direction: SwipeDirection
    public let date: Date

    public init(dishID: String, direction: SwipeDirection, date: Date) {
        self.dishID = dishID
        self.direction = direction
        self.date = date
    }
}

public struct Dish: Identifiable, Hashable, Sendable, Codable {
    public let id: String
    public var title: String
    public var summary: String
    public var imageURL: URL?
    public var minutes: Int
    public var missingIngredients: [String]

    public var canCookNow: Bool { missingIngredients.isEmpty }

    public init(
        id: String,
        title: String,
        summary: String,
        imageURL: URL? = nil,
        minutes: Int,
        missingIngredients: [String] = []
    ) {
        self.id = id
        self.title = title
        self.summary = summary
        self.imageURL = imageURL
        self.minutes = minutes
        self.missingIngredients = missingIngredients
    }
}

public struct Ingredient: Identifiable, Hashable, Sendable, Codable {
    public var id: String { PantryItem.makeID(name) }
    public let name: String
    /// Display amount, for example "200 g".
    public let amount: String

    public init(name: String, amount: String) {
        self.name = name
        self.amount = amount
    }
}

public struct RecipeStep: Identifiable, Hashable, Sendable, Codable {
    public let id: Int
    public let instruction: String
    public let timerSeconds: Int?

    public init(id: Int, instruction: String, timerSeconds: Int? = nil) {
        self.id = id
        self.instruction = instruction
        self.timerSeconds = timerSeconds
    }
}

public struct Recipe: Identifiable, Hashable, Sendable, Codable {
    public let id: String
    public let title: String
    public let summary: String
    public let minutes: Int
    public let imageURL: URL?
    public let ingredients: [Ingredient]
    public let steps: [RecipeStep]

    public init(
        id: String,
        title: String,
        summary: String,
        minutes: Int,
        imageURL: URL? = nil,
        ingredients: [Ingredient],
        steps: [RecipeStep]
    ) {
        self.id = id
        self.title = title
        self.summary = summary
        self.minutes = minutes
        self.imageURL = imageURL
        self.ingredients = ingredients
        self.steps = steps
    }
}

public struct PantryItem: Identifiable, Hashable, Sendable, Codable {
    public let id: String
    public var name: String
    public var amount: String

    public init(id: String, name: String, amount: String) {
        self.id = id
        self.name = name
        self.amount = amount
    }

    public init(name: String, amount: String) {
        self.init(id: Self.makeID(name), name: name, amount: amount)
    }

    /// Pantry items and ingredients match on their normalised name.
    public static func makeID(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}

public enum PantryChange: Sendable, Hashable {
    case upsert(PantryItem)
    case remove(id: String)
}

public struct Plan: Identifiable, Hashable, Sendable, Codable {
    public let id: String
    public let dishes: [Dish]

    public init(id: String, dishes: [Dish]) {
        self.id = id
        self.dishes = dishes
    }
}

public struct ShoppingItem: Identifiable, Hashable, Sendable, Codable {
    public let id: String
    public let name: String
    public let amount: String
    public var isChecked: Bool

    public init(id: String, name: String, amount: String, isChecked: Bool = false) {
        self.id = id
        self.name = name
        self.amount = amount
        self.isChecked = isChecked
    }
}

public struct ShoppingList: Hashable, Sendable, Codable {
    public let planID: String
    public var items: [ShoppingItem]

    public init(planID: String, items: [ShoppingItem]) {
        self.planID = planID
        self.items = items
    }
}
