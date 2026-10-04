/// Suggests where a category usually lives in a fridge. Pure keyword matching; nil if nothing matches.
func suggestedZone(forCategory category: String?) -> FridgeZone? {
    guard let category = category?.lowercased(), !category.isEmpty else { return nil }
    let rules: [(zone: FridgeZone, keywords: [String])] = [
        (.crisperDrawer, ["produce", "vegetable", "fruit", "salad", "herb"]),
        (.bottomShelf, ["meat", "poultry", "chicken", "beef", "pork", "fish", "seafood"]),
        (.middleShelf, ["dairy", "milk", "cheese", "yogurt", "butter", "egg"]),
        (.bottleRack, ["beverage", "drink", "juice", "soda", "water"]),
        (.doorBinTop, ["condiment", "sauce", "dressing", "jam", "spread"]),
        (.topShelf, ["leftover", "prepared", "deli", "meal"]),
    ]
    return rules.first { rule in rule.keywords.contains { category.contains($0) } }?.zone
}
