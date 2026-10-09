import SwiftUI

struct RecipeSuggestionsView: View {
    @EnvironmentObject private var appState: AppState
    @StateObject private var store = RecipesStore()

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                categoryTabs
                content
            }
            .background(Color.enamel)
            .navigationTitle("Recipes")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        Task { await store.refresh() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .disabled(store.isBusy)
                    .accessibilityLabel("Get new ideas")
                }
            }
            .onAppear { Task { await store.loadInventory() } }
        }
    }

    // MARK: Category tabs

    private var categoryTabs: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 20) {
                ForEach(RecipeCategory.allCases) { category in
                    let isSelected = category == store.selected
                    Button {
                        store.select(category)
                    } label: {
                        Text(category.label)
                            .font(.system(.body, weight: .medium))
                            .foregroundStyle(isSelected ? Color.compressor : Color.shelfSteel)
                            .padding(.vertical, 8)
                            .overlay(alignment: .bottom) {
                                if isSelected {
                                    Rectangle().fill(Color.freezerUltramarine).frame(height: 2)
                                }
                            }
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(isSelected ? .isSelected : [])
                }
            }
            .padding(.horizontal, 20)
            .transaction { $0.animation = nil }
        }
        .overlay(alignment: .bottom) {
            Rectangle().fill(Color.shelfSteel).frame(height: 0.5)
        }
    }

    // MARK: States

    @ViewBuilder
    private var content: some View {
        switch store.slot(store.selected) {
        case .idle, .loading:
            VStack(spacing: 6) {
                ProgressView()
                Text("Finding ideas from your fridge").font(.everFreshBody)
                Text("This takes a few seconds").font(.everFreshBody).foregroundStyle(Color.shelfSteel)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .failed(let message):
            stateMessage(title: "Couldn't get recipe ideas", message: message) {
                Button("Try again") { Task { await store.refresh() } }
                    .buttonStyle(.borderedProminent)
            }
        case .nothingExpiring:
            stateMessage(
                title: "Nothing needs using soon",
                message: "Pick another category for ideas from what you have."
            ) { EmptyView() }
        case .emptyFridge:
            stateMessage(
                title: "Your fridge is empty",
                message: "Scan something and recipe ideas will show up here."
            ) {
                Button("Scan an item") { appState.selectedTab = .scan }
                    .buttonStyle(.borderedProminent)
            }
        case .loaded(let recipes):
            recipeList(recipes)
        }
    }

    private func stateMessage<Action: View>(title: String, message: String, @ViewBuilder action: () -> Action) -> some View {
        VStack(spacing: 8) {
            Text(title).font(.everFreshItemName)
            Text(message)
                .font(.everFreshBody)
                .foregroundStyle(Color.shelfSteel)
                .multilineTextAlignment(.center)
            action().padding(.top, 8)
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: List

    private func recipeList(_ recipes: [RecipeSuggestion]) -> some View {
        let category = store.selected
        return List {
            ForEach(recipes) { recipe in
                NavigationLink {
                    RecipeDetailView(recipe: recipe, store: store)
                } label: {
                    RecipeRow(resolved: store.resolve(recipe))
                }
                .listRowBackground(Color.enamel)
                .listRowSeparatorTint(Color.shelfSteel)
            }

            Group {
                if let error = store.inlineErrors[category] {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(error.message).font(.everFreshBody).foregroundStyle(Color.shelfSteel)
                        Button("Try again") { Task { await store.retryInline(category) } }
                            .foregroundStyle(Color.freezerUltramarine)
                    }
                } else {
                    Button {
                        Task { await store.moreIdeas() }
                    } label: {
                        if store.loadingMore.contains(category) {
                            ProgressView()
                        } else {
                            Text("More ideas").font(.system(.body, weight: .semibold))
                        }
                    }
                    .foregroundStyle(Color.freezerUltramarine)
                    .disabled(store.loadingMore.contains(category))
                }

                if category.showsDietNote {
                    Text("AI-generated suggestions. Check ingredient labels if you have an allergy or medical diet.")
                        .font(.footnote)
                        .foregroundStyle(Color.shelfSteel)
                }
            }
            .listRowBackground(Color.enamel)
            .listRowSeparator(.hidden)
        }
        .listStyle(.plain)
        .buttonStyle(.borderless)
        .scrollContentBackground(.hidden)
    }
}

private struct RecipeRow: View {
    let resolved: ResolvedRecipe

    private var recipe: RecipeSuggestion { resolved.recipe }

    private var buyLine: String {
        guard resolved.buyCount > 0 else { return "Nothing to buy" }
        var line = "Buy \(resolved.buyCount) thing\(resolved.buyCount == 1 ? "" : "s")"
        if let cost = recipe.buyCostEstimate, cost > 0 { line += " about $\(Int(cost.rounded()))" }
        return line
    }

    private var metaParts: [String] {
        var parts: [String] = []
        if let minutes = recipe.minutes { parts.append("\(minutes) min") }
        if let calories = recipe.nutrition?.calories { parts.append("\(calories) kcal") }
        if let protein = recipe.nutrition?.proteinG { parts.append("\(protein) g protein") }
        return parts
    }

    private var accessibilityText: String {
        var parts = [recipe.name, recipe.summary]
        if resolved.expiringUsed.isEmpty {
            parts.append("Uses \(resolved.fromFridge.count) of your items")
        } else {
            parts.append("Uses expiring: " + resolved.expiringUsed.prefix(3).map { item in
                DateTapeSpeech.describe(item.name, expiryDate: item.expiryDate)
            }.joined(separator: ", "))
        }
        if let minutes = recipe.minutes { parts.append("\(minutes) minutes") }
        if let calories = recipe.nutrition?.calories { parts.append("\(calories) calories") }
        if let protein = recipe.nutrition?.proteinG { parts.append("\(protein) grams of protein") }
        parts.append(buyLine)
        return parts.filter { !$0.isEmpty }.joined(separator: ". ")
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            tileCluster
            VStack(alignment: .leading, spacing: 6) {
                Text(recipe.name)
                    .font(.system(size: 22, weight: .heavy))
                    .tracking(-0.4)
                if !recipe.summary.isEmpty {
                    Text(recipe.summary).font(.everFreshBody)
                }
                expiringLines
                if !metaParts.isEmpty {
                    HStack(spacing: 12) {
                        ForEach(metaParts, id: \.self) { Text($0) }
                    }
                    .font(.everFreshStamp)
                    .foregroundStyle(Color.shelfSteel)
                }
                Text(buyLine).font(.everFreshBody).foregroundStyle(Color.shelfSteel)
            }
        }
        .padding(.vertical, 8)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    private var tileCluster: some View {
        let shown = Array(resolved.matchedItems.prefix(3))
        return HStack(spacing: -14) {
            ForEach(Array(shown.enumerated()), id: \.element.documentId) { index, item in
                ItemTile(item: item, size: 40, showsName: false)
                    .zIndex(Double(shown.count - index))
            }
        }
    }

    @ViewBuilder
    private var expiringLines: some View {
        let expiring = resolved.expiringUsed
        if expiring.isEmpty {
            Text("Uses \(resolved.fromFridge.count) of your items")
                .font(.everFreshBody)
                .foregroundStyle(Color.shelfSteel)
        } else {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(expiring.prefix(3), id: \.documentId) { item in
                    HStack(spacing: 8) {
                        Text(item.name).font(.everFreshBody)
                        DateTape(expiryDate: item.expiryDate, style: .compact)
                    }
                }
                if expiring.count > 3 {
                    Text("and \(expiring.count - 3) more")
                        .font(.everFreshBody)
                        .foregroundStyle(Color.shelfSteel)
                }
            }
        }
    }
}

/// Plain-words expiry for row-level accessibility text (DateTape's own labels are hidden once a row is combined).
private enum DateTapeSpeech {
    static func describe(_ name: String, expiryDate: String?) -> String {
        guard let days = StrapiDate.daysUntil(expiryDate) else { return name }
        if days < 0 { return "\(name), expired" }
        if days == 0 { return "\(name), expires today" }
        return "\(name), expires in \(days) day\(days == 1 ? "" : "s")"
    }
}

#Preview {
    RecipeSuggestionsView()
        .environmentObject(AppState())
}
