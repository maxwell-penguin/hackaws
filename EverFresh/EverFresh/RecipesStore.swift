import Combine
import SwiftUI

/// A recipe with its ingredients sorted by what the cook has, can skip, or must buy.
struct ResolvedRecipe {
    struct Match {
        let ingredient: RecipeIngredient
        let item: ScannedItem?
    }

    let recipe: RecipeSuggestion
    /// Required ingredients that resolve to a current fridge item.
    let fromFridge: [Match]
    /// Optional ingredients; carries the matching item when one still resolves.
    let optionalAddOns: [Match]
    /// Required ingredients with no resolvable item.
    let toBuy: [RecipeIngredient]
    /// Matched fridge items whose urgency is not fresh, soonest first.
    let expiringUsed: [ScannedItem]
    /// Matched fridge items, soonest-expiring first (nil dates last).
    let matchedItems: [ScannedItem]

    var buyCount: Int { toBuy.count }
}

@MainActor
final class RecipesStore: ObservableObject {
    enum Slot {
        case idle
        case loading
        case loaded([RecipeSuggestion])
        case failed(String)
        case nothingExpiring
        case emptyFridge
    }

    struct InlineError {
        enum Retry { case more, refresh }
        let message: String
        let retry: Retry
    }

    enum StepsState {
        case idle
        case loading
        case loaded(steps: [String], tip: String?)
        case failed(String)
    }

    private static let batchSize = 3
    private static let maxInventory = 40
    private static let excludeLimit = 20

    @Published var selected: RecipeCategory = .useItUp
    @Published private(set) var slots: [RecipeCategory: Slot] = [:]
    @Published private(set) var loadingMore: Set<RecipeCategory> = []
    @Published private(set) var inlineErrors: [RecipeCategory: InlineError] = [:]
    @Published private(set) var items: [ScannedItem] = []
    @Published private(set) var itemsById: [String: ScannedItem] = [:]

    /// Cooking steps by recipe id; kept for the session so reopening a recipe is instant.
    @Published private(set) var steps: [UUID: StepsState] = [:]

    private var inventorySignature: String?
    private var inventoryLoaded = false
    /// Bumped whenever caches are cleared, so results from requests started earlier are dropped.
    private var epoch = 0

    func slot(_ category: RecipeCategory) -> Slot { slots[category] ?? .idle }

    var isBusy: Bool {
        if case .loading = slot(selected) { return true }
        return loadingMore.contains(selected)
    }

    // MARK: Inventory

    /// Call whenever the Recipes tab appears. A changed set of items clears every cached category.
    func loadInventory() async {
        do {
            let fetched = try await ItemService.fetchActiveItems()
            inventoryLoaded = true
            items = fetched
            itemsById = Dictionary(fetched.map { ($0.documentId, $0) }, uniquingKeysWith: { first, _ in first })

            let signature = fetched.map(\.documentId).sorted().joined(separator: ",")
            guard signature != inventorySignature else { return }
            inventorySignature = signature
            epoch += 1
            slots = [:]
            loadingMore = []
            inlineErrors = [:]
            await fetchFirst(selected)
        } catch {
            // Keep showing what we have; only surface the error if there's nothing yet.
            if !inventoryLoaded {
                slots[selected] = .failed("Couldn't load your fridge. \(error.localizedDescription)")
            }
        }
    }

    /// What gets sent to the backend: not expired, not empty, most urgent first, capped.
    private func payload() -> [RecipeInventoryItem] {
        items
            .compactMap { item -> RecipeInventoryItem? in
                let daysLeft = StrapiDate.daysUntil(item.expiryDate)
                if let daysLeft, daysLeft < 0 { return nil }
                if item.quantity == 0 { return nil }
                return RecipeInventoryItem(
                    id: item.documentId,
                    name: item.name,
                    category: item.category,
                    daysLeft: daysLeft,
                    percentLeft: item.quantity
                )
            }
            .sorted { ($0.daysLeft ?? Int.max) < ($1.daysLeft ?? Int.max) }
            .prefix(Self.maxInventory)
            .map { $0 }
    }

    // MARK: Fetching

    func select(_ category: RecipeCategory) {
        selected = category
        if case .idle = slot(category) {
            Task { await fetchFirst(category) }
        }
    }

    /// First load for a category (or a retry after it failed / found nothing).
    func fetchFirst(_ category: RecipeCategory) async {
        if case .loading = slot(category) { return }
        let inventory = payload()
        if inventory.isEmpty {
            slots[category] = .emptyFridge
            return
        }
        if category == .useItUp,
           !inventory.contains(where: { $0.daysLeft.map { ExpiryUrgency.from(daysLeft: $0) != .fresh } ?? false }) {
            slots[category] = .nothingExpiring
            return
        }

        slots[category] = .loading
        let requestEpoch = epoch
        do {
            let recipes = try await fetchBatch(category, inventory: inventory, exclude: [])
            guard requestEpoch == epoch else { return }
            slots[category] = recipes.isEmpty ? .failed("No ideas came back this time.") : .loaded(recipes)
        } catch {
            guard requestEpoch == epoch else { return }
            slots[category] = .failed(Self.message(for: error))
        }
    }

    /// Appends a fresh batch, excluding recipes already shown.
    func moreIdeas(_ category: RecipeCategory? = nil) async {
        let category = category ?? selected
        guard case .loaded(let current) = slot(category), !loadingMore.contains(category) else { return }
        loadingMore.insert(category)
        inlineErrors[category] = nil
        let requestEpoch = epoch
        do {
            let fresh = try await fetchBatch(category, inventory: payload(), exclude: Self.recentNames(current))
            guard requestEpoch == epoch else { return }
            if case .loaded(let latest) = slot(category) {
                let known = Set(latest.map { $0.name.lowercased() })
                slots[category] = .loaded(latest + fresh.filter { !known.contains($0.name.lowercased()) })
            }
        } catch {
            guard requestEpoch == epoch else { return }
            inlineErrors[category] = InlineError(message: Self.message(for: error), retry: .more)
        }
        loadingMore.remove(category)
    }

    /// Replaces the category's list with a new batch, excluding what was shown. On failure the old list stays.
    func refresh(_ category: RecipeCategory? = nil) async {
        let category = category ?? selected
        switch slot(category) {
        case .loading:
            return
        case .loaded(let current):
            guard !loadingMore.contains(category) else { return }
            inlineErrors[category] = nil
            slots[category] = .loading
            let requestEpoch = epoch
            do {
                let fresh = try await fetchBatch(category, inventory: payload(), exclude: Self.recentNames(current))
                guard requestEpoch == epoch else { return }
                slots[category] = .loaded(fresh)
            } catch {
                guard requestEpoch == epoch else { return }
                slots[category] = .loaded(current)
                inlineErrors[category] = InlineError(message: Self.message(for: error), retry: .refresh)
            }
        default:
            if !inventoryLoaded {
                await loadInventory()
            } else {
                await fetchFirst(category)
            }
        }
    }

    func retryInline(_ category: RecipeCategory) async {
        switch inlineErrors[category]?.retry {
        case .more: await moreIdeas(category)
        case .refresh: await refresh(category)
        case nil: break
        }
    }

    private func fetchBatch(_ category: RecipeCategory, inventory: [RecipeInventoryItem], exclude: [String]) async throws -> [RecipeSuggestion] {
        let recipes = try await ItemService.fetchRecipeSuggestions(
            category: category, inventory: inventory, count: Self.batchSize, exclude: exclude
        )
        return recipes.map { recipe in
            var tagged = recipe
            tagged.category = category
            return tagged
        }
    }

    private static func recentNames(_ recipes: [RecipeSuggestion]) -> [String] {
        Array(recipes.map(\.name).suffix(excludeLimit))
    }

    private static func message(for error: Error) -> String {
        if let urlError = error as? URLError, urlError.code == .timedOut {
            return "That took too long. Check your connection and try again."
        }
        return error.localizedDescription
    }

    // MARK: Steps

    func stepsState(for recipe: RecipeSuggestion) -> StepsState { steps[recipe.id] ?? .idle }

    /// Does nothing if the steps are already loading or loaded; a failed load can be retried.
    func loadSteps(for recipe: RecipeSuggestion) async {
        switch stepsState(for: recipe) {
        case .loading, .loaded: return
        case .idle, .failed: break
        }
        steps[recipe.id] = .loading
        do {
            let result = try await ItemService.fetchRecipeSteps(
                name: recipe.name,
                servings: recipe.servings,
                category: recipe.category,
                ingredients: recipe.ingredients
            )
            steps[recipe.id] = .loaded(steps: result.steps, tip: result.tip)
        } catch {
            steps[recipe.id] = .failed(Self.message(for: error))
        }
    }

    // MARK: Resolving

    /// Shared by the list rows and the detail screen.
    func resolve(_ recipe: RecipeSuggestion) -> ResolvedRecipe {
        var fromFridge: [ResolvedRecipe.Match] = []
        var addOns: [ResolvedRecipe.Match] = []
        var toBuy: [RecipeIngredient] = []

        for ingredient in recipe.ingredients {
            let item = ingredient.inventoryId.flatMap { itemsById[$0] }
            if ingredient.required {
                if let item { fromFridge.append(.init(ingredient: ingredient, item: item)) } else { toBuy.append(ingredient) }
            } else {
                addOns.append(.init(ingredient: ingredient, item: item))
            }
        }

        func soonest(_ items: [ScannedItem]) -> [ScannedItem] {
            var seen = Set<String>()
            return items
                .filter { seen.insert($0.documentId).inserted }
                .sorted { (StrapiDate.daysUntil($0.expiryDate) ?? Int.max) < (StrapiDate.daysUntil($1.expiryDate) ?? Int.max) }
        }
        let matched = soonest(fromFridge.compactMap(\.item))
        let expiring = matched.filter {
            StrapiDate.daysUntil($0.expiryDate).map { ExpiryUrgency.from(daysLeft: $0) != .fresh } ?? false
        }
        return ResolvedRecipe(
            recipe: recipe,
            fromFridge: fromFridge,
            optionalAddOns: addOns,
            toBuy: toBuy,
            expiringUsed: expiring,
            matchedItems: matched
        )
    }
}
