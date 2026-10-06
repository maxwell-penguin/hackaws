import Foundation

struct RecipeIngredient: Decodable, Hashable {
    let name: String
    let amount: String?
    let inventoryId: String?
    let required: Bool

    private enum CodingKeys: String, CodingKey { case name, amount, inventoryId, required }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = try c.decode(String.self, forKey: .name)
        amount = try? c.decodeIfPresent(String.self, forKey: .amount)
        inventoryId = try? c.decodeIfPresent(String.self, forKey: .inventoryId)
        required = (try? c.decodeIfPresent(Bool.self, forKey: .required)) ?? true
    }
}

struct RecipeNutrition: Decodable, Hashable {
    let calories: Int?
    let proteinG: Int?
    let carbsG: Int?
    let fatG: Int?
    let sugarG: Int?

    private enum CodingKeys: String, CodingKey { case calories, proteinG, carbsG, fatG, sugarG }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        calories = try? c.decodeIfPresent(Int.self, forKey: .calories)
        proteinG = try? c.decodeIfPresent(Int.self, forKey: .proteinG)
        carbsG = try? c.decodeIfPresent(Int.self, forKey: .carbsG)
        fatG = try? c.decodeIfPresent(Int.self, forKey: .fatG)
        sugarG = try? c.decodeIfPresent(Int.self, forKey: .sugarG)
    }
}

/// A single recipe from POST /api/recipe-suggestions. `id` and `category` are client-side:
/// the store sets the category when it adds the recipe.
struct RecipeSuggestion: Identifiable, Decodable {
    let id = UUID()
    let name: String
    let summary: String
    let minutes: Int?
    let servings: Int?
    let nutrition: RecipeNutrition?
    let buyCostEstimate: Double?
    let ingredients: [RecipeIngredient]
    var category: RecipeCategory = .useItUp

    private enum CodingKeys: String, CodingKey {
        case name, summary, minutes, servings, nutrition, buyCostEstimate, ingredients
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = try c.decode(String.self, forKey: .name)
        summary = (try? c.decodeIfPresent(String.self, forKey: .summary)) ?? ""
        minutes = try? c.decodeIfPresent(Int.self, forKey: .minutes)
        servings = try? c.decodeIfPresent(Int.self, forKey: .servings)
        nutrition = try? c.decodeIfPresent(RecipeNutrition.self, forKey: .nutrition)
        buyCostEstimate = try? c.decodeIfPresent(Double.self, forKey: .buyCostEstimate)
        ingredients = (try? c.decodeIfPresent([RecipeIngredient].self, forKey: .ingredients)) ?? []
    }
}

/// Decodes each recipe independently so one malformed recipe never loses the batch.
struct RecipeSuggestionsResponse: Decodable {
    let recipes: [RecipeSuggestion]

    private enum CodingKeys: String, CodingKey { case recipes }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        recipes = try c.decode([FailableDecodable<RecipeSuggestion>].self, forKey: .recipes).compactMap(\.value)
    }
}

/// One fridge item as sent to the recipe backend. `id` is the Strapi documentId.
struct RecipeInventoryItem: Encodable {
    let id: String
    let name: String
    let category: String?
    let daysLeft: Int?
    let percentLeft: Double?
}
