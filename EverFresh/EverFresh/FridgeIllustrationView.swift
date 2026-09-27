import SwiftUI

/// A simple, clean illustration matching FridgeLayout's zones — outer frame, shelf dividers,
/// door bin outlines, and a crisper drawer outline. Not photorealistic, just recognizable.
/// Draws in screen space: pass the same scale/offset FridgeCanvasView computed for item
/// positions so the drawing and the draggable icons line up.
struct FridgeIllustrationView: View {
    let scale: CGFloat
    let offset: CGSize

    private func screenRect(_ rect: CGRect) -> CGRect {
        CGRect(
            x: rect.minX * scale + offset.width,
            y: rect.minY * scale + offset.height,
            width: rect.width * scale,
            height: rect.height * scale
        )
    }

    private var outerRect: CGRect {
        screenRect(CGRect(origin: .zero, size: FridgeLayout.size))
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 20)
                .fill(Color(.secondarySystemBackground))
                .frame(width: outerRect.width, height: outerRect.height)
                .position(x: outerRect.midX, y: outerRect.midY)

            RoundedRectangle(cornerRadius: 20)
                .strokeBorder(Color.secondary.opacity(0.6), lineWidth: 3)
                .frame(width: outerRect.width, height: outerRect.height)
                .position(x: outerRect.midX, y: outerRect.midY)

            shelfDivider(atLogicalY: FridgeLayout.rects[.middleShelf]!.minY)
            shelfDivider(atLogicalY: FridgeLayout.rects[.bottomShelf]!.minY)
            shelfDivider(atLogicalY: FridgeLayout.rects[.crisperDrawer]!.minY)

            zoneOutline(.leftDoorBin, cornerRadius: 8)
            zoneOutline(.rightDoorBin, cornerRadius: 8)
            zoneOutline(.crisperDrawer, cornerRadius: 12)
        }
    }

    private func shelfDivider(atLogicalY y: CGFloat) -> some View {
        let screenY = y * scale + offset.height
        return Rectangle()
            .fill(Color.secondary.opacity(0.4))
            .frame(width: outerRect.width - 12, height: 1.5)
            .position(x: outerRect.midX, y: screenY)
    }

    private func zoneOutline(_ zone: FridgeZone, cornerRadius: CGFloat) -> some View {
        let rect = screenRect(FridgeLayout.rects[zone]!)
        return RoundedRectangle(cornerRadius: cornerRadius)
            .fill(Color.secondary.opacity(0.08))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .strokeBorder(Color.secondary.opacity(0.5), lineWidth: 2)
            )
            .frame(width: max(rect.width - 8, 0), height: max(rect.height - 8, 0))
            .position(x: rect.midX, y: rect.midY)
    }
}

#Preview {
    FridgeIllustrationView(scale: 1, offset: .zero)
        .frame(width: FridgeLayout.size.width, height: FridgeLayout.size.height)
        .background(Color(.systemBackground))
}
