import SwiftUI

struct MainTabView: View {
    var body: some View {
        TabView {
            ItemScanView()
                .tabItem { Label("Scan", systemImage: "camera") }

            ExpiringSoonView()
                .tabItem { Label("Expiring", systemImage: "clock.badge.exclamationmark") }

            GroceryHistoryView()
                .tabItem { Label("History", systemImage: "clock.arrow.circlepath") }

            Text("Coming soon")
                .tabItem { Label("Recipes", systemImage: "fork.knife") }
        }
    }
}

#Preview {
    MainTabView()
}
