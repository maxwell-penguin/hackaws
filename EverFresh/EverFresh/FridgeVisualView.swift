import SwiftUI

/// The canvas mode — items sitting in their assigned slots over the fridge illustration.
/// Slot centers live in FridgeLayout's fixed logical space and are scaled to fit the device.
/// Dragging is local while it's in flight; on drop the item snaps to the nearest free slot in
/// the zone under it and the container (the source of truth) is told via `onMove`.
struct FridgeVisualView: View {
    let items: [ScannedItem]
    let assignments: [String: SlotAssignment]
    let onMove: (String, SlotAssignment) -> Void
    let onConsume: (ScannedItem) -> Void

    @State private var selectedItem: ScannedItem?
    @State private var isDetailPresented = false
    @State private var highlightedZone: FridgeZone?

    /// Slot for a drop at `point`, or nil if that zone is full. The item's own slot counts as free.
    private func dropAssignment(for documentId: String, at point: CGPoint) -> SlotAssignment? {
        let zone = FridgeLayout.zone(for: point)
        let occupied = Set(assignments.filter { $0.key != documentId && $0.value.zone == zone }.map(\.value.slotIndex))
        guard let index = FridgeLayout.nearestFreeSlot(in: zone, to: point, occupied: occupied) else { return nil }
        return SlotAssignment(zone: zone, slotIndex: index, center: FridgeLayout.slots(for: zone)[index])
    }

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
                    if let assignment = assignments[item.documentId] {
                        FridgeItemTile(
                            item: item,
                            baseCenter: assignment.center,
                            transform: transform,
                            dropAssignment: { dropAssignment(for: item.documentId, at: $0) },
                            onTap: {
                                selectedItem = item
                                isDetailPresented = true
                            },
                            onDragChanged: { highlightedZone = $0 },
                            onMove: { onMove(item.documentId, $0) },
                            onConsume: { onConsume(item) }
                        )
                    }
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
        .navigationDestination(isPresented: $isDetailPresented) {
            if let selectedItem {
                ItemDetailView(item: selectedItem)
            }
        }
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

private struct FridgeItemTile: View {
    let item: ScannedItem
    let baseCenter: CGPoint
    let transform: CanvasTransform
    let dropAssignment: (CGPoint) -> SlotAssignment?
    let onTap: () -> Void
    let onDragChanged: (FridgeZone?) -> Void
    let onMove: (SlotAssignment) -> Void
    let onConsume: () -> Void

    private static let snapSpring = Animation.spring(response: 0.3, dampingFraction: 0.75)

    @State private var dragTranslation: CGSize = .zero
    @State private var didLongPress = false
    @State private var showConsumeConfirmation = false

    private var side: CGFloat { FridgeLayout.iconSize * transform.scale }
    private var cornerRadius: CGFloat { 10 * transform.scale }
    private var screenBase: CGPoint { transform.toScreen(baseCenter) }

    private var displayPosition: CGPoint {
        CGPoint(x: screenBase.x + dragTranslation.width, y: screenBase.y + dragTranslation.height)
    }

    private var isDragging: Bool { dragTranslation != .zero }

    private var placeholder: some View {
        ZStack {
            Color.frost
            VStack(spacing: 2) {
                Image(systemName: CategoryIcons.symbol(for: item.category ?? "other"))
                    .font(.system(size: side * 0.4))
                    .foregroundStyle(Color.compressor)
                Text(item.name)
                    .font(.caption2)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .foregroundStyle(Color.compressor)
            }
            .padding(.horizontal, 3)
            RoundedRectangle(cornerRadius: cornerRadius).strokeBorder(Color.shelfSteel, lineWidth: 1)
        }
    }

    @ViewBuilder
    private var tileFace: some View {
        if let urlString = item.photoUrl, let url = URL(string: urlString) {
            AsyncImage(url: url) { phase in
                if let image = phase.image {
                    image.resizable().scaledToFill()
                } else {
                    placeholder
                }
            }
        } else {
            placeholder
        }
    }

    var body: some View {
        tileFace
            .frame(width: side, height: side)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
            .shadow(color: .black.opacity(0.18), radius: 1.5, y: 2)
            .overlay(alignment: .topTrailing) {
                DateTape(expiryDate: item.expiryDate, style: .compact)
                    .offset(x: 12, y: -6)
            }
            .position(displayPosition)
            .zIndex(isDragging ? 1 : 0)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        dragTranslation = value.translation
                        onDragChanged(FridgeLayout.zone(for: transform.toLogical(displayPosition)))
                    }
                    .onEnded { value in
                        let distance = hypot(value.translation.width, value.translation.height)
                        onDragChanged(nil)
                        // A long press already handled this touch (the confirmation dialog is up,
                        // or was just dismissed) — don't also treat the release as a tap or a drop.
                        if didLongPress {
                            didLongPress = false
                            withAnimation(Self.snapSpring) { dragTranslation = .zero }
                            return
                        }
                        if distance < 8 {
                            dragTranslation = .zero
                            onTap()
                        } else {
                            drop(from: displayPosition)
                        }
                    }
            )
            .simultaneousGesture(
                LongPressGesture(minimumDuration: 0.5)
                    .onEnded { _ in
                        didLongPress = true
                        showConsumeConfirmation = true
                    }
            )
            .confirmationDialog(
                "Mark \"\(item.name)\" as Consumed?",
                isPresented: $showConsumeConfirmation,
                titleVisibility: .visible
            ) {
                Button("Mark as Consumed", role: .destructive) {
                    didLongPress = false
                    onConsume()
                }
                Button("Cancel", role: .cancel) {
                    didLongPress = false
                }
            }
    }

    /// Snap to the nearest free slot in the zone under the tile, or spring back if it's full.
    private func drop(from visual: CGPoint) {
        guard let target = dropAssignment(transform.toLogical(visual)) else {
            withAnimation(Self.snapSpring) { dragTranslation = .zero }
            return
        }
        // Commit now so List mode updates immediately, then spring from where the finger
        // left it: the base jumps to the slot, so re-express the visual offset against it
        // (no animation) and animate that offset to zero on the next tick.
        let newBase = transform.toScreen(target.center)
        onMove(target)
        dragTranslation = CGSize(width: visual.x - newBase.x, height: visual.y - newBase.y)
        DispatchQueue.main.async {
            withAnimation(Self.snapSpring) { dragTranslation = .zero }
        }
    }
}

#Preview {
    NavigationStack {
        FridgeVisualView(items: [], assignments: [:], onMove: { _, _ in }, onConsume: { _ in })
    }
}
