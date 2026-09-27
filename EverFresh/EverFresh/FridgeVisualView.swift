import SwiftUI

/// The draggable canvas mode — items positioned over a two-door fridge illustration. Positions
/// are stored in FridgeLayout's fixed logical space (not raw screen pixels), then scaled to fit
/// whatever device this is shown on — that's what keeps a saved position consistent across
/// different screen sizes.
struct FridgeVisualView: View {
    let items: [ScannedItem]
    let onPositionChanged: (String, CGPoint) -> Void

    @State private var positions: [String: CGPoint] = [:]
    @State private var selectedItem: ScannedItem?
    @State private var isDetailPresented = false
    @State private var highlightedZone: FridgeZone?

    var body: some View {
        GeometryReader { geometry in
            let transform = CanvasTransform(fitting: FridgeLayout.size, in: geometry.size)

            ZStack {
                FridgeIllustrationView(
                    scale: transform.scale,
                    offset: transform.offset,
                    highlightedZone: highlightedZone
                )

                ForEach(items) { item in
                    DraggableItemView(
                        item: item,
                        basePosition: positions[item.documentId] ?? .zero,
                        transform: transform,
                        onTap: {
                            selectedItem = item
                            isDetailPresented = true
                        },
                        onDragChanged: { zone in
                            highlightedZone = zone
                        },
                        onDragEnded: { newLogicalPosition in
                            highlightedZone = nil
                            let adjusted = adjustedPosition(for: item.documentId, near: newLogicalPosition)
                            positions[item.documentId] = adjusted
                            Task { await persistPosition(item: item, point: adjusted) }
                        }
                    )
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
        .navigationDestination(isPresented: $isDetailPresented) {
            if let selectedItem {
                ItemDetailView(item: selectedItem)
            }
        }
        .task(id: items.map(\.documentId)) {
            assignFallbackPositions()
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

    /// If the drop point is too close to another item's current position, nudge it by a small
    /// fixed offset so icons in the same zone don't stack exactly on top of each other. This
    /// only avoids near-exact overlap — it isn't a full grid-packing pass.
    private func adjustedPosition(for documentId: String, near point: CGPoint) -> CGPoint {
        let overlapThreshold: CGFloat = 28
        let nudge: CGFloat = 22

        let overlapsExisting = positions.contains { key, otherPoint in
            key != documentId && hypot(otherPoint.x - point.x, otherPoint.y - point.y) < overlapThreshold
        }
        guard overlapsExisting else { return point }

        return CGPoint(x: point.x + nudge, y: point.y + nudge)
    }

    private func persistPosition(item: ScannedItem, point: CGPoint) async {
        // Best-effort: the drag already moved it locally, so a failed save just means it
        // reverts to the last saved position next time the fridge is loaded.
        try? await ItemService.updatePosition(documentId: item.documentId, x: point.x, y: point.y)
        onPositionChanged(item.documentId, point)
    }
}

/// Maps between FridgeLayout's fixed logical space and this view's actual on-screen size —
/// a uniform "aspect fit" scale, centered.
struct CanvasTransform {
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
    let onDragChanged: (FridgeZone?) -> Void
    let onDragEnded: (CGPoint) -> Void

    @State private var dragTranslation: CGSize = .zero

    private var displayPosition: CGPoint {
        let screenBase = transform.toScreen(basePosition)
        return CGPoint(x: screenBase.x + dragTranslation.width, y: screenBase.y + dragTranslation.height)
    }

    private func logicalPoint(forScreenTranslation translation: CGSize) -> CGPoint {
        let screenBase = transform.toScreen(basePosition)
        let screenPoint = CGPoint(x: screenBase.x + translation.width, y: screenBase.y + translation.height)
        return transform.toLogical(screenPoint)
    }

    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: CategoryIcons.symbol(for: item.category ?? "other"))
                .font(.system(size: 26))
                .frame(width: 56, height: 56)
                .background(.thinMaterial, in: Circle())
                .overlay(alignment: .topTrailing) {
                    if let daysLeft = StrapiDate.daysUntil(item.expiryDate) {
                        ExpiryBadge(daysLeft: daysLeft)
                            .offset(x: 8, y: -8)
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
                    let liveZone = FridgeLayout.zone(for: logicalPoint(forScreenTranslation: value.translation))
                    onDragChanged(liveZone)
                }
                .onEnded { value in
                    let distance = hypot(value.translation.width, value.translation.height)
                    dragTranslation = .zero
                    onDragChanged(nil)
                    if distance < 8 {
                        onTap()
                    } else {
                        onDragEnded(logicalPoint(forScreenTranslation: value.translation))
                    }
                }
        )
    }
}

#Preview {
    NavigationStack {
        FridgeVisualView(items: [], onPositionChanged: { _, _ in })
    }
}
