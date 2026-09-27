import SwiftUI

/// Free-form draggable canvas of active items, laid out over a two-door fridge illustration.
/// Item positions are stored in FridgeLayout's fixed logical space (not raw screen pixels),
/// then scaled to fit whatever device this is shown on — that's what keeps a saved position
/// consistent across different screen sizes.
struct FridgeCanvasView: View {
    var onScanTapped: () -> Void = {}

    @EnvironmentObject private var appState: AppState
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
                        let transform = CanvasTransform(fitting: FridgeLayout.size, in: geometry.size)

                        ZStack {
                            FridgeIllustrationView(scale: transform.scale, offset: transform.offset)

                            ForEach(items) { item in
                                DraggableItemView(
                                    item: item,
                                    basePosition: positions[item.documentId] ?? .zero,
                                    transform: transform,
                                    onTap: {
                                        selectedItem = item
                                        isDetailPresented = true
                                    },
                                    onDragEnded: { newLogicalPosition in
                                        positions[item.documentId] = newLogicalPosition
                                        Task { await persistPosition(item: item, point: newLogicalPosition) }
                                    }
                                )
                            }
                        }
                        .frame(width: geometry.size.width, height: geometry.size.height)
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
            .onChange(of: appState.selectedTab) { _, newTab in
                guard newTab == .fridge else { return }
                Task { await load() }
            }
        }
    }

    private func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            items = try await ItemService.fetchActiveItems()
            assignFallbackPositions()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Fills in a grid position (in FridgeLayout's logical space) for any item that doesn't
    /// have one yet. Never persisted until the user actually drags the item.
    private func assignFallbackPositions() {
        let columns = 3
        let columnWidth = FridgeLayout.size.width / CGFloat(columns)
        let rowHeight: CGFloat = 90

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

/// Maps between FridgeLayout's fixed logical space and this view's actual on-screen size —
/// a uniform "aspect fit" scale, centered.
private struct CanvasTransform {
    let scale: CGFloat
    let offset: CGSize

    init(fitting logicalSize: CGSize, in containerSize: CGSize) {
        let rawScale = min(containerSize.width / logicalSize.width, containerSize.height / logicalSize.height)
        scale = rawScale.isFinite && rawScale > 0 ? rawScale : 1
        offset = CGSize(
            width: (containerSize.width - logicalSize.width * scale) / 2,
            height: (containerSize.height - logicalSize.height * scale) / 2
        )
    }

    func toScreen(_ point: CGPoint) -> CGPoint {
        CGPoint(x: point.x * scale + offset.width, y: point.y * scale + offset.height)
    }

    func toLogical(_ point: CGPoint) -> CGPoint {
        CGPoint(x: (point.x - offset.width) / scale, y: (point.y - offset.height) / scale)
    }
}

private struct DraggableItemView: View {
    let item: ScannedItem
    let basePosition: CGPoint
    let transform: CanvasTransform
    let onTap: () -> Void
    let onDragEnded: (CGPoint) -> Void

    @State private var dragTranslation: CGSize = .zero

    private var displayPosition: CGPoint {
        let screenBase = transform.toScreen(basePosition)
        return CGPoint(x: screenBase.x + dragTranslation.width, y: screenBase.y + dragTranslation.height)
    }

    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: CategoryIcons.symbol(for: item.category ?? "other"))
                .font(.system(size: 26))
                .frame(width: 56, height: 56)
                .background(.thinMaterial, in: Circle())
                .overlay(alignment: .topTrailing) {
                    if let daysLeft = StrapiDate.daysUntil(item.expiryDate) {
                        expiryBadge(daysLeft: daysLeft)
                    }
                }
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
                        let screenBase = transform.toScreen(basePosition)
                        let finalScreenPosition = CGPoint(
                            x: screenBase.x + value.translation.width,
                            y: screenBase.y + value.translation.height
                        )
                        onDragEnded(transform.toLogical(finalScreenPosition))
                    }
                }
        )
    }

    private func expiryBadge(daysLeft: Int) -> some View {
        let color: Color = daysLeft <= 0 ? .red : (daysLeft <= 3 ? .orange : .secondary)
        return HStack(spacing: 2) {
            Image(systemName: "clock.fill")
                .font(.system(size: 8))
            Text(daysLeft <= 0 ? "!" : "\(daysLeft)")
                .font(.system(size: 9, weight: .bold))
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 2)
        .background(color, in: Capsule())
        .foregroundStyle(.white)
        .offset(x: 8, y: -8)
    }
}

#Preview {
    FridgeCanvasView()
        .environmentObject(AppState())
}
