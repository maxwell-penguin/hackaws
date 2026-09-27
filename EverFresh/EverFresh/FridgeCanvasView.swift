import SwiftUI

enum FridgeViewMode: String, CaseIterable {
    case visual = "Visual"
    case list = "List"
}

/// Top-level Fridge tab container. Fetches active items once and hosts either the draggable
/// visual canvas or a zone-grouped list, both fed from this same array so they can never
/// disagree — dragging in Visual mode updates this array's cached position so List mode
/// reflects it immediately, without waiting on a refetch.
struct FridgeCanvasView: View {
    private static let modeDefaultsKey = "FridgeCanvasView.mode"

    var onScanTapped: () -> Void

    @EnvironmentObject private var appState: AppState
    @State private var items: [ScannedItem] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var mode: FridgeViewMode

    init(onScanTapped: @escaping () -> Void = {}) {
        self.onScanTapped = onScanTapped
        let savedMode = UserDefaults.standard.string(forKey: Self.modeDefaultsKey)
            .flatMap(FridgeViewMode.init(rawValue:))
        _mode = State(initialValue: savedMode ?? .visual)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if !isLoading && errorMessage == nil && !items.isEmpty {
                    Picker("View Mode", selection: $mode) {
                        ForEach(FridgeViewMode.allCases, id: \.self) { mode in
                            Text(mode.rawValue).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .padding()
                }

                Group {
                    if isLoading && items.isEmpty {
                        ProgressView("Loading…")
                    } else if let errorMessage {
                        ContentUnavailableView {
                            Label("Couldn't load fridge", systemImage: "exclamationmark.triangle")
                        } description: {
                            Text(errorMessage)
                        } actions: {
                            Button("Retry") { Task { await load() } }
                        }
                    } else if items.isEmpty {
                        ContentUnavailableView {
                            Label("Nothing tracked yet", systemImage: "refrigerator")
                        } description: {
                            Text("Scan your first item to see it here.")
                        } actions: {
                            Button("Scan an Item", action: onScanTapped)
                        }
                    } else {
                        switch mode {
                        case .visual:
                            FridgeVisualView(items: items, onPositionChanged: updateLocalPosition)
                        case .list:
                            FridgeListView(items: items)
                        }
                    }
                }
            }
            .navigationTitle("Fridge")
            .task { await load() }
            .onChange(of: appState.selectedTab) { _, newTab in
                guard newTab == .fridge else { return }
                Task { await load() }
            }
            .onChange(of: mode) { _, newMode in
                UserDefaults.standard.set(newMode.rawValue, forKey: Self.modeDefaultsKey)
            }
        }
    }

    private func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            items = try await ItemService.fetchActiveItems()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func updateLocalPosition(documentId: String, point: CGPoint) {
        guard let index = items.firstIndex(where: { $0.documentId == documentId }) else { return }
        items[index].positionX = point.x
        items[index].positionY = point.y
    }
}

#Preview {
    FridgeCanvasView()
        .environmentObject(AppState())
}
