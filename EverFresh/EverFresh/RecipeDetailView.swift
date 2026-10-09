import SwiftUI

struct RecipeDetailView: View {
    let recipe: RecipeSuggestion
    @ObservedObject var store: RecipesStore

    private var resolved: ResolvedRecipe { store.resolve(recipe) }

    private func isNotFresh(_ item: ScannedItem) -> Bool {
        StrapiDate.daysUntil(item.expiryDate).map { ExpiryUrgency.from(daysLeft: $0) != .fresh } ?? false
    }

    private var addOnsToBuy: [RecipeIngredient] {
        resolved.optionalAddOns.filter { $0.item == nil }.map(\.ingredient)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                nutrition
                ingredientSections
                stepsSection
                shareButton
                if recipe.category.showsDietNote {
                    Text("AI-generated suggestions. Check ingredient labels if you have an allergy or medical diet.")
                        .font(.footnote)
                        .foregroundStyle(Color.shelfSteel)
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Color.enamel)
        .navigationBarTitleDisplayMode(.inline)
        .task { await store.loadSteps(for: recipe) }
    }

    // MARK: Header and nutrition

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(recipe.name)
                .font(.system(size: 22, weight: .heavy))
                .tracking(-0.4)
            if !recipe.summary.isEmpty {
                Text(recipe.summary).font(.everFreshBody)
            }
            let facts = [
                recipe.minutes.map { "\($0) min" },
                recipe.servings.map { "\($0) serving\($0 == 1 ? "" : "s")" },
            ].compactMap { $0 }
            if !facts.isEmpty {
                HStack(spacing: 16) {
                    ForEach(facts, id: \.self) { Text($0) }
                }
                .font(.everFreshStamp)
            }
        }
    }

    @ViewBuilder
    private var nutrition: some View {
        let n = recipe.nutrition
        let columns: [(value: Int, caption: String)] = [
            n?.calories.map { ($0, "kcal") },
            n?.proteinG.map { ($0, "protein g") },
            n?.carbsG.map { ($0, "carbs g") },
            n?.fatG.map { ($0, "fat g") },
            n?.sugarG.map { ($0, "sugar g") },
        ].compactMap { $0 }
        if !columns.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                rule
                HStack(alignment: .top, spacing: 18) {
                    ForEach(columns, id: \.caption) { column in
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(column.value)").font(.everFreshStamp)
                            Text(column.caption).font(.caption2).foregroundStyle(Color.shelfSteel)
                        }
                    }
                }
                Text("Approximate, per serving").font(.caption2).foregroundStyle(Color.shelfSteel)
                rule
            }
        }
    }

    private var rule: some View {
        Rectangle().fill(Color.shelfSteel).frame(height: 0.5)
    }

    // MARK: Ingredients

    private func sectionHeader(_ title: String) -> some View {
        Text(title).everFreshSectionHeader()
    }

    /// Rows separated by hairlines.
    private func rows<Row: View>(_ count: Int, @ViewBuilder row: @escaping (Int) -> Row) -> some View {
        VStack(spacing: 0) {
            ForEach(0..<count, id: \.self) { index in
                if index > 0 { rule }
                row(index).padding(.vertical, 8)
            }
        }
    }

    private func amountText(_ amount: String?) -> some View {
        Text(amount ?? "").font(.everFreshStamp).foregroundStyle(Color.compressor)
    }

    @ViewBuilder
    private var ingredientSections: some View {
        let r = resolved

        if !r.fromFridge.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                sectionHeader("From your fridge")
                rows(r.fromFridge.count) { i in
                    let match = r.fromFridge[i]
                    HStack(spacing: 10) {
                        if let item = match.item { ItemTile(item: item, size: 32, showsName: false) }
                        Text(match.ingredient.name).font(.everFreshBody)
                        Spacer(minLength: 8)
                        amountText(match.ingredient.amount)
                        if let item = match.item, isNotFresh(item) {
                            DateTape(expiryDate: item.expiryDate, style: .compact)
                        }
                    }
                }
            }
        }

        if !r.toBuy.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                sectionHeader("To buy")
                rows(r.toBuy.count) { i in
                    HStack {
                        Text(r.toBuy[i].name).font(.everFreshBody)
                        Spacer(minLength: 8)
                        amountText(r.toBuy[i].amount)
                    }
                }
                if let cost = recipe.buyCostEstimate, cost > 0 {
                    Text("About $\(Int(cost.rounded())), rough estimate")
                        .font(.everFreshBody)
                        .foregroundStyle(Color.shelfSteel)
                        .padding(.top, 4)
                }
            }
        }

        if !r.optionalAddOns.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                sectionHeader("Optional add-ons")
                rows(r.optionalAddOns.count) { i in
                    let match = r.optionalAddOns[i]
                    HStack(spacing: 10) {
                        if let item = match.item { ItemTile(item: item, size: 32, showsName: false) }
                        Text(match.ingredient.name).font(.everFreshBody)
                        Spacer(minLength: 8)
                        if let item = match.item {
                            Text("In your fridge").font(.footnote).foregroundStyle(Color.shelfSteel)
                            if isNotFresh(item) { DateTape(expiryDate: item.expiryDate, style: .compact) }
                        }
                        amountText(match.ingredient.amount)
                    }
                }
            }
        }
    }

    // MARK: Steps

    private var stepsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader("Steps")
            switch store.stepsState(for: recipe) {
            case .idle, .loading:
                HStack(spacing: 10) {
                    ProgressView()
                    Text("Writing the steps").font(.everFreshBody).foregroundStyle(Color.shelfSteel)
                }
            case .failed(let message):
                VStack(alignment: .leading, spacing: 8) {
                    Text("Couldn't write the steps. \(message)").font(.everFreshBody).foregroundStyle(Color.shelfSteel)
                    Button("Try again") { Task { await store.loadSteps(for: recipe) } }
                        .buttonStyle(.borderedProminent)
                }
            case .loaded(let steps, let tip):
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                        HStack(alignment: .firstTextBaseline, spacing: 12) {
                            Text("\(index + 1)").font(.everFreshStamp).frame(width: 24, alignment: .leading)
                            Text(step).font(.everFreshBody)
                        }
                        .accessibilityElement(children: .combine)
                    }
                    if let tip {
                        Text(tip).font(.everFreshBody).foregroundStyle(Color.shelfSteel).padding(.top, 4)
                    }
                }
            }
        }
    }

    // MARK: Shopping list

    private func line(_ ingredient: RecipeIngredient) -> String {
        "- " + [ingredient.amount, ingredient.name].compactMap { $0 }.joined(separator: " ")
    }

    @ViewBuilder
    private var shareButton: some View {
        let need = resolved.toBuy
        let optional = addOnsToBuy
        if !need.isEmpty || !optional.isEmpty {
            let text = ["Shopping list for \(recipe.name)"]
                + (need.isEmpty ? [] : ["", "Need:"] + need.map(line))
                + (optional.isEmpty ? [] : ["", "Optional:"] + optional.map(line))
            ShareLink(item: text.joined(separator: "\n")) {
                Text("Share shopping list").font(.system(.body, weight: .semibold))
            }
            .foregroundStyle(Color.freezerUltramarine)
        }
    }
}
