import SwiftUI

/// Free-form draggable canvas of active items. Positions come from Strapi's positionX/positionY
/// when present; unplaced items get a grid fallback that's only persisted once the user drags them.
struct FridgeCanvasView: View {
    var onScanTapped: () -> Void = {}

    @State private var items: [ScannedItem] = []
    @State private var positions: [String: CGPoint] = [:]
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var selectedItem: ScannedItem?
    @State private var isDetailPresented = false

    var body: some View {
        NavigationStack {
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
                    GeometryReader { geometry in
                        ZStack {
                            ForEach(items) { item in
                                DraggableItemView(
                                    item: item,
                                    basePosition: positions[item.documentId] ?? .zero,
                                    onTap: {
                                        selectedItem = item
                                        isDetailPresented = true
                                    },
                                    onDragEnded: { newPosition in
                                        positions[item.documentId] = newPosition
                                        Task { await persistPosition(item: item, point: newPosition) }
                                    }
                                )
                            }
                        }
                        .frame(width: geometry.size.width, height: geometry.size.height)
                        .onAppear { assignFallbackPositions(in: geometry.size) }
                    }
                }
            }
            .navigationTitle("Fridge")
            .navigationDestination(isPresented: $isDetailPresented) {
                if let selectedItem {
                    ItemDetailView(item: selectedItem)
                }
            }
            .task { await load() }
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

    private func assignFallbackPositions(in size: CGSize) {
        guard size.width > 0, size.height > 0 else { return }
        let columns = max(1, Int(size.width / 90))
        let columnWidth = size.width / CGFloat(columns)
        let rowHeight: CGFloat = 100

        for (index, item) in items.enumerated() {
            guard positions[item.documentId] == nil else { continue }
            if let x = item.positionX, let y = item.positionY {
                positions[item.documentId] = CGPoint(x: x, y: y)
            } else {
                let row = index / columns
                let column = index % columns
                positions[item.documentId] = CGPoint(
                    x: columnWidth * (CGFloat(column) + 0.5),
                    y: rowHeight * (CGFloat(row) + 0.5) + 40
                )
            }
        }
    }

    private func persistPosition(item: ScannedItem, point: CGPoint) async {
        // Best-effort: the drag already moved it locally, so a failed save just means it
        // reverts to the last saved position next time the fridge is loaded.
        try? await ItemService.updatePosition(documentId: item.documentId, x: point.x, y: point.y)
    }
}

private struct DraggableItemView: View {
    let item: ScannedItem
    let basePosition: CGPoint
    let onTap: () -> Void
    let onDragEnded: (CGPoint) -> Void

    @State private var dragTranslation: CGSize = .zero

    private var displayPosition: CGPoint {
        CGPoint(x: basePosition.x + dragTranslation.width, y: basePosition.y + dragTranslation.height)
    }

    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: CategoryIcons.symbol(for: item.category))
                .font(.system(size: 26))
                .frame(width: 56, height: 56)
                .background(.thinMaterial, in: Circle())
            Text(item.name)
                .font(.caption2)
                .lineLimit(1)
                .frame(maxWidth: 72)
        }
        .position(displayPosition)
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    dragTranslation = value.translation
                }
                .onEnded { value in
                    let distance = hypot(value.translation.width, value.translation.height)
                    dragTranslation = .zero
                    if distance < 8 {
                        onTap()
                    } else {
                        let newPosition = CGPoint(
                            x: basePosition.x + value.translation.width,
                            y: basePosition.y + value.translation.height
                        )
                        onDragEnded(newPosition)
                    }
                }
        )
    }
}

#Preview {
    FridgeCanvasView()
}
