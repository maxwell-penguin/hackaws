import Combine

enum AppTab: Hashable {
    case scan, fridge, expiring, history, recipes
}

/// Shared app-wide state — currently just which tab is active, so any view (e.g. a save
/// confirmation) can navigate the user to a different tab.
final class AppState: ObservableObject {
    @Published var selectedTab: AppTab = .scan
}
