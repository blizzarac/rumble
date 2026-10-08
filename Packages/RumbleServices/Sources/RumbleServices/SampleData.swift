import Foundation

/// Hand-written data for previews, tests and the first runs of the app before the backend exists.
public enum SampleData {
    public static let pantry: [PantryItem] = [
        ("Spaghetti", "500 g"), ("Garlic", "1 bulb"), ("Olive oil", "1 bottle"),
        ("Chili flakes", "1 jar"), ("Eggs", "6"), ("Butter", "250 g"),
        ("Tomato", "3"), ("Salt", "1 box"), ("Rice", "1 kg"), ("Onion", "2"),
    ].map { PantryItem(name: $0.0, amount: $0.1) }

    public static let recipes: [Recipe] = [
        recipe(
            id: "spaghetti-aglio-e-olio", title: "Spaghetti aglio e olio",
            summary: "Garlic, chili and olive oil. Ready in the time it takes to boil pasta.", minutes: 20,
            ingredients: [("Spaghetti", "200 g"), ("Garlic", "4 cloves"), ("Olive oil", "4 tbsp"),
                          ("Chili flakes", "1 tsp"), ("Salt", "1 pinch")],
            steps: [("Boil the spaghetti in well-salted water.", 600),
                    ("Slice the garlic and fry it gently in the olive oil with the chili flakes.", 180),
                    ("Toss the drained pasta in the pan with a splash of pasta water and serve.", nil)]
        ),
        recipe(
            id: "tomato-omelette", title: "Tomato omelette",
            summary: "Soft eggs, buttery tomatoes, one pan.", minutes: 10,
            ingredients: [("Eggs", "3"), ("Tomato", "1"), ("Butter", "1 tbsp"), ("Salt", "1 pinch")],
            steps: [("Dice the tomato and whisk the eggs with the salt.", nil),
                    ("Melt the butter and soften the tomato for a minute.", 60),
                    ("Pour in the eggs, stir gently, fold and serve.", nil)]
        ),
        recipe(
            id: "buttered-rice", title: "Buttered rice with onion",
            summary: "Comfort food from the pantry.", minutes: 25,
            ingredients: [("Rice", "1 cup"), ("Butter", "2 tbsp"), ("Onion", "1"), ("Salt", "1 pinch")],
            steps: [("Cook the rice in salted water.", 720),
                    ("Fry the chopped onion in butter until golden.", 300),
                    ("Stir the onion and butter through the rice.", nil)]
        ),
        recipe(
            id: "fried-rice", title: "Egg fried rice",
            summary: "Day-old rice, eggs and a splash of soy.", minutes: 15,
            ingredients: [("Rice", "2 cups cooked"), ("Eggs", "2"), ("Onion", "1"),
                          ("Soy sauce", "2 tbsp"), ("Spring onion", "2")],
            steps: [("Fry the onion until soft.", 240),
                    ("Push aside, scramble the eggs, then add the rice and soy sauce.", nil),
                    ("Top with sliced spring onion.", nil)]
        ),
        recipe(
            id: "chicken-curry", title: "Quick chicken curry",
            summary: "Coconut milk, curry paste, tender thighs.", minutes: 40,
            ingredients: [("Chicken thighs", "600 g"), ("Onion", "1"), ("Curry paste", "2 tbsp"),
                          ("Coconut milk", "1 can"), ("Rice", "1 cup")],
            steps: [("Brown the chicken and the onion.", 420),
                    ("Stir in the curry paste, then the coconut milk.", nil),
                    ("Simmer until the chicken is cooked through; serve over rice.", 1200)]
        ),
        recipe(
            id: "caprese-salad", title: "Caprese salad",
            summary: "Tomato, mozzarella, basil. No cooking.", minutes: 5,
            ingredients: [("Tomato", "3"), ("Mozzarella", "2 balls"), ("Basil", "1 bunch"), ("Olive oil", "2 tbsp")],
            steps: [("Slice the tomato and mozzarella.", nil),
                    ("Layer with basil, drizzle with olive oil and serve.", nil)]
        ),
        recipe(
            id: "garlic-mushrooms", title: "Garlic butter mushrooms",
            summary: "Golden mushrooms on toast or alone.", minutes: 15,
            ingredients: [("Mushrooms", "400 g"), ("Butter", "2 tbsp"), ("Garlic", "2 cloves"), ("Parsley", "1 bunch")],
            steps: [("Fry the mushrooms in a dry pan until browned.", 300),
                    ("Add butter and garlic, cook for a minute.", 60),
                    ("Finish with chopped parsley.", nil)]
        ),
    ]

    /// Deck cards, derived from the recipes: whatever the sample pantry lacks counts as missing.
    public static let dishes: [Dish] = {
        let have = Set(pantry.map(\.id))
        return recipes.map { recipe in
            Dish(
                id: recipe.id,
                title: recipe.title,
                summary: recipe.summary,
                imageURL: recipe.imageURL,
                minutes: recipe.minutes,
                missingIngredients: recipe.ingredients.filter { !have.contains($0.id) }.map(\.name)
            )
        }
    }()

    private static func recipe(
        id: String,
        title: String,
        summary: String,
        minutes: Int,
        ingredients: [(String, String)],
        steps: [(String, Int?)]
    ) -> Recipe {
        Recipe(
            id: id,
            title: title,
            summary: summary,
            minutes: minutes,
            ingredients: ingredients.map { Ingredient(name: $0.0, amount: $0.1) },
            steps: steps.enumerated().map { RecipeStep(id: $0.offset, instruction: $0.element.0, timerSeconds: $0.element.1) }
        )
    }
}
