import Foundation

/// Raw values must match the server's category keys exactly; it rejects unknown keys with a 400.
enum RecipeCategory: String, CaseIterable, Identifiable {
    case useItUp = "use-it-up"
    case healthy
    case sugarFree = "sugar-free"
    case highProtein = "high-protein"
    case lowCarb = "low-carb"
    case vegetarian
    case vegan
    case glutenFree = "gluten-free"
    case dairyFree = "dairy-free"
    case comfort
    case light
    case sweet
    case snack
    case quick

    var id: String { rawValue }

    var label: String {
        switch self {
        case .useItUp: return "Use it up"
        case .healthy: return "Healthier"
        case .sugarFree: return "Sugar-free"
        case .highProtein: return "High protein"
        case .lowCarb: return "Low carb"
        case .vegetarian: return "Vegetarian"
        case .vegan: return "Vegan"
        case .glutenFree: return "Gluten-free"
        case .dairyFree: return "Dairy-free"
        case .comfort: return "Comfort food"
        case .light: return "Light and fresh"
        case .sweet: return "Sweet tooth"
        case .snack: return "Snacks"
        case .quick: return "Under 20 minutes"
        }
    }

    /// Diet-related categories get an "AI-generated, check labels" footnote.
    var showsDietNote: Bool {
        switch self {
        case .sugarFree, .vegan, .glutenFree, .dairyFree: return true
        default: return false
        }
    }
}
