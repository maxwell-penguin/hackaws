import SwiftUI

/// Stub: the full detail screen comes later. Shows only the name and summary for now.
struct RecipeDetailView: View {
    let recipe: RecipeSuggestion

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(recipe.name)
                .font(.everFreshTitle)
                .tracking(-0.4)
            Text(recipe.summary)
                .font(.everFreshBody)
                .foregroundStyle(Color.shelfSteel)
            Spacer()
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.enamel)
        .navigationBarTitleDisplayMode(.inline)
    }
}
