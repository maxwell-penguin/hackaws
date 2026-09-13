import SwiftUI

struct RecipeSuggestionsView: View {
    private enum ViewState {
        case loading
        case noExpiringItems
        case error(String)
        case loaded([RecipeSuggestion])
    }

    @State private var state: ViewState = .loading

    var body: some View {
        NavigationStack {
            Group {
                switch state {
                case .loading:
                    ProgressView("Cooking up some ideas…\nThis can take a few seconds.")
                        .multilineTextAlignment(.center)

                case .noExpiringItems:
                    ContentUnavailableView(
                        "Nothing expiring",
                        systemImage: "checkmark.circle",
                        description: Text("No suggestions needed right now.")
                    )

                case .error(let message):
                    ContentUnavailableView {
                        Label("Couldn't load suggestions", systemImage: "exclamationmark.triangle")
                    } description: {
                        Text(message)
                    } actions: {
                        Button("Retry") { Task { await load() } }
                    }

                case .loaded(let recipes) where recipes.isEmpty:
                    ContentUnavailableView(
                        "No recipe ideas",
                        systemImage: "fork.knife",
                        description: Text("Couldn't come up with anything this time.")
                    )

                case .loaded(let recipes):
                    ScrollView {
                        VStack(spacing: 12) {
                            ForEach(recipes) { recipe in
                                RecipeCard(recipe: recipe)
                            }
                        }
                        .padding()
                    }
                }
            }
            .navigationTitle("Recipes")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        Task { await load() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .disabled(isLoading)
                }
            }
            .task { await load() }
        }
    }

    private var isLoading: Bool {
        if case .loading = state { return true }
        return false
    }

    private func load() async {
        state = .loading
        do {
            let expiring = try await ItemService.fetchExpiringSoon(withinDays: 3)
            guard !expiring.isEmpty else {
                state = .noExpiringItems
                return
            }
            let active = try await ItemService.fetchActiveItems()
            let recipes = try await ItemService.fetchRecipeSuggestions(
                expiringItems: expiring.map(\.name),
                activeInventory: active.map(\.name)
            )
            state = .loaded(recipes)
        } catch {
            state = .error(error.localizedDescription)
        }
    }
}

private struct RecipeCard: View {
    let recipe: RecipeSuggestion

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(recipe.name)
                .font(.headline)

            if !recipe.usesExpiring.isEmpty {
                HStack(alignment: .top, spacing: 4) {
                    Image(systemName: "clock.badge.exclamationmark")
                        .foregroundStyle(.orange)
                    Text("Uses: \(recipe.usesExpiring.joined(separator: ", "))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if !recipe.missingIngredients.isEmpty {
                Text("Missing: \(recipe.missingIngredients.joined(separator: ", "))")
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }
}

#Preview {
    RecipeSuggestionsView()
}
