import SwiftUI

struct MainTabView: View {
    @EnvironmentObject private var appState: AppState
    @ObservedObject private var reminders = ReminderScheduler.shared
    @State private var showPrompt = false

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
        .onAppear { routePendingDestination(); offerPromptIfNeeded() }
        .onChange(of: reminders.pendingDestination) { routePendingDestination() }
        .onChange(of: appState.selectedTab) { offerPromptIfNeeded() }
        .onChange(of: reminders.offerPending) { offerPromptIfNeeded() }
        .sheet(isPresented: $showPrompt) { RemindersPromptSheet() }
    }

    /// A tapped reminder may have arrived before this view existed, so this runs on appear too.
    private func routePendingDestination() {
        guard let destination = reminders.pendingDestination else { return }
        if destination == "fridge" { appState.selectedTab = .fridge }
        reminders.pendingDestination = nil
    }

    /// Waits briefly so a dismissing flow (receipt review, confirmation sheet) can finish first.
    private func offerPromptIfNeeded() {
        guard reminders.offerPending, appState.selectedTab == .fridge else { return }
        Task {
            try? await Task.sleep(for: .seconds(0.6))
            guard reminders.offerPending, appState.selectedTab == .fridge else { return }
            reminders.offerPending = false
            showPrompt = true
        }
    }
}

#Preview {
    MainTabView()
        .environmentObject(AppState())
}
