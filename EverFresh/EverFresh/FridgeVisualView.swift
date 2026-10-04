import SwiftUI

/// The canvas mode — items sitting in their assigned slots over the fridge illustration.
/// Slot centers live in FridgeLayout's fixed logical space and are scaled to fit the device.
/// Dragging is disabled for now; tap opens detail, long-press offers Mark as Consumed.
struct FridgeVisualView: View {
    let items: [ScannedItem]
    let assignments: [String: SlotAssignment]
    let onConsume: (ScannedItem) -> Void

    @State private var selectedItem: ScannedItem?
    @State private var isDetailPresented = false

    var body: some View {
        GeometryReader { geometry in
            let transform = CanvasTransform(fitting: FridgeLayout.size, in: geometry.size)

            ZStack {
                FridgeIllustrationView(scale: transform.scale, offset: transform.offset)

                ForEach(items) { item in
                    if let assignment = assignments[item.documentId] {
                        FridgeItemIcon(
                            item: item,
                            center: transform.toScreen(assignment.center),
                            scale: transform.scale,
                            onTap: {
                                selectedItem = item
                                isDetailPresented = true
                            },
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

private struct FridgeItemIcon: View {
    let item: ScannedItem
    let center: CGPoint
    let scale: CGFloat
    let onTap: () -> Void
    let onConsume: () -> Void

    @State private var showConsumeConfirmation = false

    private var diameter: CGFloat { FridgeLayout.iconSize * scale }

    var body: some View {
        Image(systemName: CategoryIcons.symbol(for: item.category ?? "other"))
            .font(.system(size: diameter * 0.46))
            .frame(width: diameter, height: diameter)
            .background(Color.frost, in: Circle())
            .overlay(Circle().strokeBorder(Color.shelfSteel, lineWidth: 1))
            .overlay(alignment: .topTrailing) {
                DateTape(expiryDate: item.expiryDate, style: .compact)
                    .offset(x: 12, y: -6)
            }
            .overlay(alignment: .bottom) {
                Text(item.name)
                    .font(.system(.caption2, weight: .heavy))
                    .lineLimit(1)
                    .frame(maxWidth: 72)
                    .offset(y: 14)
            }
            .position(center)
            .onTapGesture(perform: onTap)
            .onLongPressGesture(minimumDuration: 0.5) { showConsumeConfirmation = true }
            .confirmationDialog(
                "Mark \"\(item.name)\" as Consumed?",
                isPresented: $showConsumeConfirmation,
                titleVisibility: .visible
            ) {
                Button("Mark as Consumed", role: .destructive, action: onConsume)
                Button("Cancel", role: .cancel) {}
            }
    }
}

#Preview {
    NavigationStack {
        FridgeVisualView(items: [], assignments: [:], onConsume: { _ in })
    }
}
