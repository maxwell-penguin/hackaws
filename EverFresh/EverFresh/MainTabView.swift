import SwiftUI

struct MainTabView: View {
    private enum Tab: Hashable {
        case scan, expiring, history, recipes, fridge
    }

    @State private var selectedTab: Tab = .scan

    var body: some View {
        TabView(selection: $selectedTab) {
            ItemScanView()
                .tabItem { Label("Scan", systemImage: "camera") }
                .tag(Tab.scan)

            ExpiringSoonView()
                .tabItem { Label("Expiring", systemImage: "clock.badge.exclamationmark") }
                .tag(Tab.expiring)

            GroceryHistoryView()
                .tabItem { Label("History", systemImage: "clock.arrow.circlepath") }
                .tag(Tab.history)

            RecipeSuggestionsView()
                .tabItem { Label("Recipes", systemImage: "fork.knife") }
                .tag(Tab.recipes)

            FridgeCanvasView(onScanTapped: { selectedTab = .scan })
                .tabItem { Label("Fridge", systemImage: "refrigerator") }
                .tag(Tab.fridge)
        }
    }
}

#Preview {
    MainTabView()
}
