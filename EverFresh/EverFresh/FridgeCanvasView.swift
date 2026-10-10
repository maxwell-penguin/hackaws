import SwiftUI

enum FridgeViewMode: String, CaseIterable {
    case visual = "Visual"
    case list = "List"
}

/// Top-level Fridge tab container. Fetches active items, resolves each into a slot with
/// FridgeLayout.resolve, and hosts either the visual canvas or a zone-grouped list, both fed
/// the same items and assignments so they can never disagree.
struct FridgeCanvasView: View {
    private static let modeDefaultsKey = "FridgeCanvasView.mode"

    var onScanTapped: () -> Void

    @State private var items: [ScannedItem] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var assignments: [String: SlotAssignment] = [:]
    @ObservedObject private var scheduler = ReminderScheduler.shared
    @State private var showReminders = false
    @State private var migrationTask: Task<Void, Never>?
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
                                .buttonStyle(.borderedProminent)
                        }
                    } else if items.isEmpty {
                        ContentUnavailableView {
                            Label("Nothing tracked yet", systemImage: "refrigerator")
                        } description: {
                            Text("Scan your first item to see it here.")
                        } actions: {
                            Button("Scan an Item", action: onScanTapped)
                                .buttonStyle(.borderedProminent)
                        }
                    } else {
                        switch mode {
                        case .visual:
                            FridgeVisualView(items: items, assignments: assignments, onMove: moveItem, onConsume: markConsumed)
                        case .list:
                            FridgeListView(items: items, assignments: assignments, onConsume: markConsumed)
                        }
                    }
                }
            }
            .background(Color.enamel)
            .navigationTitle("Fridge")
            .navigationSubtitle(subtitle)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button { showReminders = true } label: {
                        Image(systemName: scheduler.remindersEnabled ? "bell" : "bell.slash")
                    }
                    .accessibilityLabel("Reminders")
                }
            }
            .sheet(isPresented: $showReminders) { RemindersSettingsView() }
            .onAppear { Task { await load() } }
            .onChange(of: mode) { _, newMode in
                UserDefaults.standard.set(newMode.rawValue, forKey: Self.modeDefaultsKey)
            }
        }
    }

    private var subtitle: String {
        guard !items.isEmpty else { return "" }
        let soon = items.filter {
            StrapiDate.daysUntil($0.expiryDate).map { ExpiryUrgency.from(daysLeft: $0) != .fresh } ?? false
        }.count
        return "\(items.count) item\(items.count == 1 ? "" : "s"), \(soon) need\(soon == 1 ? "s" : "") using soon"
    }

    private func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            items = try await ItemService.fetchActiveItems()
            assignments = FridgeLayout.resolve(items: items)
            persistAssignments()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Writes each item's assigned slot center back to the server when it differs from what's
    /// stored, one at a time and best-effort, so Visual and List agree after the next reload too.
    private func persistAssignments() {
        migrationTask?.cancel()
        let pending = items.compactMap { item -> (String, CGPoint)? in
            guard let assignment = assignments[item.documentId] else { return nil }
            if let x = item.positionX, let y = item.positionY,
               abs(x - assignment.center.x) <= 0.5, abs(y - assignment.center.y) <= 0.5 { return nil }
            return (item.documentId, assignment.center)
        }
        guard !pending.isEmpty else { return }
        migrationTask = Task {
            for (documentId, center) in pending {
                if Task.isCancelled { return }
                // The user may have dragged this item since the load; don't overwrite their move.
                guard assignments[documentId]?.center == center else { continue }
                try? await ItemService.updatePosition(documentId: documentId, x: center.x, y: center.y)
                if let index = items.firstIndex(where: { $0.documentId == documentId }) {
                    items[index].positionX = center.x
                    items[index].positionY = center.y
                }
            }
        }
    }

    /// Drag-and-drop landing: the container stays the source of truth, so both view modes see
    /// the new slot immediately; the save itself is best-effort.
    private func moveItem(documentId: String, to assignment: SlotAssignment) {
        assignments[documentId] = assignment
        if let index = items.firstIndex(where: { $0.documentId == documentId }) {
            items[index].positionX = assignment.center.x
            items[index].positionY = assignment.center.y
        }
        Task { try? await ItemService.updatePosition(documentId: documentId, x: assignment.center.x, y: assignment.center.y) }
    }

    /// Shared by both view modes: mark consumed on the server, then drop it from the local
    /// array so it disappears immediately without a full refetch. Best-effort — if the PATCH
    /// fails, the item still vanishes locally and simply reappears as active on the next reload.
    private func markConsumed(_ item: ScannedItem) {
        Task {
            try? await ItemService.markConsumed(documentId: item.documentId)
            items.removeAll { $0.documentId == item.documentId }
        }
    }
}

#Preview {
    FridgeCanvasView()
        .environmentObject(AppState())
}
