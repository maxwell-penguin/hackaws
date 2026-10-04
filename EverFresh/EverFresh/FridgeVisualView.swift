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

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var selectedItem: ScannedItem?
    @State private var isDetailPresented = false
    /// True only while the once-per-launch door swing plays; the flat layout is used at all other times.
    @State private var isSwinging = Motion.doorSwingEnabled && !Motion.hasPlayedDoorSwing
    @State private var doorOpen = false
    @State private var highlightedZone: FridgeZone?

    /// Slot for a drop at `point`, or nil if that zone is full. The item's own slot counts as free.
    private func dropAssignment(for documentId: String, at point: CGPoint) -> SlotAssignment? {
        let zone = FridgeLayout.zone(for: point)
        let occupied = Set(assignments.filter { $0.key != documentId && $0.value.zone == zone }.map(\.value.slotIndex))
        guard let index = FridgeLayout.nearestFreeSlot(in: zone, to: point, occupied: occupied) else { return nil }
        return SlotAssignment(zone: zone, slotIndex: index, center: FridgeLayout.slots(for: zone)[index])
    }

    private func isDoorItem(_ item: ScannedItem) -> Bool {
        assignments[item.documentId]?.zone.isDoor ?? false
    }

    @ViewBuilder
    private func tiles(_ list: [ScannedItem], transform: CanvasTransform) -> some View {
        ForEach(list) { item in
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

    /// Door layer + door tiles, hinged on the fridge's trailing edge. Swings from ~80 degrees to flat
    /// (positive angle brings the free edge toward the viewer); under Reduce Motion it only fades in.
    private func doorGroup(transform: CanvasTransform, size: CGSize) -> some View {
        let hingeX = transform.toScreen(CGPoint(x: FridgeLayout.bodyRect.maxX, y: 0)).x
        return ZStack {
            FridgeIllustrationView(
                scale: transform.scale,
                offset: transform.offset,
                highlightedZone: highlightedZone,
                layer: .door
            )
            tiles(items.filter(isDoorItem), transform: transform)
        }
        .opacity(doorOpen ? 1 : 0)
        .animation(reduceMotion ? Motion.doorReducedFade : Motion.doorFade, value: doorOpen)
        .rotation3DEffect(
            .degrees(doorOpen || reduceMotion ? 0 : 80),
            axis: (x: 0, y: 1, z: 0),
            anchor: UnitPoint(x: hingeX / max(size.width, 1), y: 0.5),
            perspective: 0.5
        )
        .animation(Motion.doorSwing, value: doorOpen)
    }

    private func startDoorSwingIfNeeded() {
        guard isSwinging, !Motion.hasPlayedDoorSwing else { return }
        Motion.hasPlayedDoorSwing = true
        doorOpen = true
        Task {
            try? await Task.sleep(for: .seconds(reduceMotion ? 0.2 : Motion.doorSwingDuration))
            isSwinging = false
        }
    }

    var body: some View {
        GeometryReader { geometry in
            let transform = CanvasTransform(fitting: FridgeLayout.size, in: geometry.size)

            ZStack {
                FridgeIllustrationView(
                    scale: transform.scale,
                    offset: transform.offset,
                    highlightedZone: highlightedZone,
                    layer: .body
                )

                if isSwinging {
                    // While swinging, the door column and its tiles move as one unit; everything
                    // else sits still. Dragging is off (hit testing disabled) for these 0.4s.
                    doorGroup(transform: transform, size: geometry.size)
                    tiles(items.filter { !isDoorItem($0) }, transform: transform)
                } else {
                    FridgeIllustrationView(
                        scale: transform.scale,
                        offset: transform.offset,
                        highlightedZone: highlightedZone,
                        layer: .door
                    )
                    tiles(items, transform: transform)
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
        .allowsHitTesting(!isSwinging)
        .onAppear { startDoorSwingIfNeeded() }
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

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var dragTranslation: CGSize = .zero
    /// Lifted once the drag passes the tap threshold; cleared as the tile lands.
    @State private var isLifted = false
    /// Stays true until the landing animation has fully finished, so the tile never dips under neighbors mid-flight.
    @State private var isRaised = false
    @State private var isDragInProgress = false
    @State private var didLongPress = false
    @State private var showConsumeConfirmation = false

    private var side: CGFloat { FridgeLayout.iconSize * transform.scale }
    private var screenBase: CGPoint { transform.toScreen(baseCenter) }

    private var displayPosition: CGPoint {
        CGPoint(x: screenBase.x + dragTranslation.width, y: screenBase.y + dragTranslation.height)
    }

    private var snapAnimation: Animation { Motion.resolve(Motion.snapSpring, reduceMotion: reduceMotion) }

    var body: some View {
        ItemTile(item: item, size: side, showsName: true, isLifted: isLifted)
            .overlay(alignment: .topTrailing) {
                DateTape(expiryDate: item.expiryDate, style: .compact)
                    .offset(x: 12, y: -6)
            }
            .scaleEffect(isLifted && !reduceMotion ? Motion.liftScale : 1)
            .position(displayPosition)
            .zIndex(isRaised ? 1 : 0)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        if !isDragInProgress {
                            isDragInProgress = true
                            Haptics.prepare()
                        }
                        dragTranslation = value.translation
                        if !isLifted, hypot(value.translation.width, value.translation.height) >= 8 {
                            isRaised = true
                            withAnimation(Motion.resolve(Motion.liftSpring, reduceMotion: reduceMotion)) { isLifted = true }
                            Haptics.lift()
                        }
                        onDragChanged(FridgeLayout.zone(for: transform.toLogical(displayPosition)))
                    }
                    .onEnded { value in
                        let distance = hypot(value.translation.width, value.translation.height)
                        isDragInProgress = false
                        onDragChanged(nil)
                        // A long press already handled this touch (the confirmation dialog is up,
                        // or was just dismissed) — don't also treat the release as a tap or a drop.
                        if didLongPress {
                            didLongPress = false
                            land()
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
            land()
            return
        }
        // Commit now so List mode updates immediately, then spring from where the finger
        // left it: the base jumps to the slot, so re-express the visual offset against it
        // (no animation) and animate that offset to zero on the next tick.
        let newBase = transform.toScreen(target.center)
        onMove(target)
        dragTranslation = CGSize(width: visual.x - newBase.x, height: visual.y - newBase.y)
        DispatchQueue.main.async {
            Haptics.settle()
            land()
        }
    }

    /// Springs the tile to rest at its base slot and lowers it once that has fully finished.
    private func land() {
        withAnimation(snapAnimation, completionCriteria: .logicallyComplete) {
            dragTranslation = .zero
            isLifted = false
        } completion: {
            isRaised = false
        }
    }
}

#Preview {
    NavigationStack {
        FridgeVisualView(items: [], assignments: [:], onMove: { _, _ in }, onConsume: { _ in })
    }
}
