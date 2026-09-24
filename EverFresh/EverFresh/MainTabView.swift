import SwiftUI

struct MainTabView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        TabView(selection: $appState.selectedTab) {
            ItemScanView()
                .tabItem { Label("Scan", systemImage: "camera") }
                .tag(AppTab.scan)

            FridgeCanvasView(onScanTapped: { appState.selectedTab = .scan })
                .tabItem { Label("Fridge", systemImage: "refrigerator") }
                .tag(AppTab.fridge)

            ExpiringSoonView()
                .tabItem { Label("Expiring", systemImage: "clock.badge.exclamationmark") }
                .tag(AppTab.expiring)

            GroceryHistoryView()
                .tabItem { Label("History", systemImage: "clock.arrow.circlepath") }
                .tag(AppTab.history)

            RecipeSuggestionsView()
                .tabItem { Label("Recipes", systemImage: "fork.knife") }
                .tag(AppTab.recipes)
        }
    }
}

#Preview {
    MainTabView()
        .environmentObject(AppState())
}
