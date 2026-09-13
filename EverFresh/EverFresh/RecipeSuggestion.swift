import Foundation

/// A single recipe suggestion from POST /api/recipe-suggestions.
struct RecipeSuggestion: Codable, Identifiable {
    var name: String
    var usesExpiring: [String]
    var missingIngredients: [String]

    var id: String { name }
}

struct RecipeSuggestionsResponse: Codable {
    let recipes: [RecipeSuggestion]
}
