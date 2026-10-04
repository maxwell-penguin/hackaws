import SwiftUI

/// Line-art fridge drawn entirely from FridgeLayout's geometry (no layout math lives here).
/// Pass the same scale/offset FridgeVisualView uses for item positions so the drawing and the
/// icons line up. Line widths and label size are screen points, not scaled.
struct FridgeIllustrationView: View {
    let scale: CGFloat
    let offset: CGSize
    var highlightedZone: FridgeZone? = nil

    private static let lineWidth: CGFloat = 1.5

    var body: some View {
        Canvas { context, _ in
            let transform = CGAffineTransform(translationX: offset.width, y: offset.height).scaledBy(x: scale, y: scale)
            let steel = GraphicsContext.Shading.color(Color.shelfSteel)

            func stroke(_ path: Path, width: CGFloat = Self.lineWidth, shading: GraphicsContext.Shading? = nil) {
                context.stroke(path.applying(transform), with: shading ?? steel, lineWidth: width)
            }
            func line(_ x0: CGFloat, _ x1: CGFloat, y: CGFloat) -> Path {
                var p = Path()
                p.move(to: CGPoint(x: x0, y: y))
                p.addLine(to: CGPoint(x: x1, y: y))
                return p
            }

            // Body and seam.
            let body = FridgeLayout.bodyRect
            stroke(Path(roundedRect: body, cornerRadius: 20))
            var seam = Path()
            seam.move(to: CGPoint(x: FridgeLayout.seamX, y: body.minY))
            seam.addLine(to: CGPoint(x: FridgeLayout.seamX, y: body.maxY))
            stroke(seam)

            // Glass shelf rails: a 1.5pt line with a thin 0.75pt line 3pt below.
            for zone in [FridgeZone.topShelf, .middleShelf, .bottomShelf] {
                let rect = FridgeLayout.rects[zone]!
                let y = FridgeLayout.railY(for: zone)
                stroke(line(rect.minX + 6, rect.maxX - 6, y: y))
                stroke(line(rect.minX + 6, rect.maxX - 6, y: y + 3), width: 0.75)
            }

            // Crisper: outlined drawer with a short handle at top center.
            let crisper = FridgeLayout.rects[.crisperDrawer]!
            stroke(Path(roundedRect: crisper.insetBy(dx: 6, dy: 4), cornerRadius: 12))
            stroke(line(crisper.midX - 10, crisper.midX + 10, y: crisper.minY + 9))

            // Door bins: a body with a slightly lipped, rounded top.
            for zone in [FridgeZone.doorBinTop, .doorBinMiddle, .doorBinBottom] {
                let rect = FridgeLayout.rects[zone]!.insetBy(dx: 6, dy: 2)
                stroke(Path(roundedRect: CGRect(x: rect.minX, y: rect.minY + 5, width: rect.width, height: rect.height - 5),
                            cornerRadius: 8))
                stroke(Path(roundedRect: CGRect(x: rect.minX - 2, y: rect.minY, width: rect.width + 4, height: 6),
                            cornerRadius: 3))
            }

            // Bottle rack: tall rounded rect with one bar across.
            let rack = FridgeLayout.rects[.bottleRack]!.insetBy(dx: 6, dy: 2)
            stroke(Path(roundedRect: rack, cornerRadius: 10))
            let barY = rack.minY + FridgeLayout.labelStripHeight + (rack.height - FridgeLayout.labelStripHeight) / 2
            stroke(line(rack.minX + 6, rack.maxX - 6, y: barY))

            // Zone names.
            for zone in FridgeLayout.displayOrder {
                let rect = FridgeLayout.rects[zone]!
                let label = Text(zone.displayName)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.shelfSteel)
                let origin = CGPoint(x: rect.minX + 14, y: rect.minY + FridgeLayout.labelStripHeight / 2 + 2)
                context.draw(label, at: origin.applying(transform), anchor: .leading)
            }

            if let zone = highlightedZone {
                let rect = FridgeLayout.rects[zone]!.insetBy(dx: 2, dy: 2)
                stroke(Path(roundedRect: rect, cornerRadius: 10), shading: .color(Color.freezerUltramarine))
            }
        }
    }
}

#Preview {
    FridgeIllustrationView(scale: 1, offset: .zero, highlightedZone: .crisperDrawer)
        .frame(width: FridgeLayout.size.width, height: FridgeLayout.size.height)
        .background(Color.enamel)
}
