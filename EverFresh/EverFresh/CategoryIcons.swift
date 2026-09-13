import Foundation

/// Maps an Item's free-text category to an SF Symbol for the fridge canvas.
enum CategoryIcons {
    private static let symbolsByCategory: [String: String] = [
        "produce": "carrot",
        "dairy": "cup.and.saucer",
        "meat": "flame",
        "grains": "leaf",
        "snacks": "popcorn",
        "beverages": "mug",
        "condiments": "drop",
        "frozen": "snowflake",
        "other": "shippingbox",
    ]

    static func symbol(for category: String) -> String {
        symbolsByCategory[category.lowercased()] ?? "shippingbox"
    }
}
