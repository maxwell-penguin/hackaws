import SwiftUI

/// Receipt-paper strip listing every item in the batch, one line each. Decorative: the item
/// sheet carries the same information, so it's hidden from accessibility.
struct ThermalStripView: View {
    let items: [ScannedItem]
    let currentIndex: Int

    private static let lineHeight: CGFloat = 22
    private static let visibleLines = 5

    private func price(_ item: ScannedItem) -> String {
        item.pricePaid.map { String(format: "%.2f", $0) } ?? "—"
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(Array(items.enumerated()), id: \.element.documentId) { index, item in
                        HStack {
                            Text(item.name).lineLimit(1)
                            Spacer(minLength: 12)
                            Text(price(item))
                        }
                        .font(.everFreshStamp)
                        .foregroundStyle(index < currentIndex ? Color.shelfSteel : Color.compressor)
                        .frame(height: Self.lineHeight)
                        .overlay(alignment: .bottom) {
                            if index == currentIndex {
                                Rectangle().fill(Color.freezerUltramarine).frame(height: 2)
                            }
                        }
                        .id(item.documentId)
                    }
                }
                .padding(.horizontal, 16)
            }
            .scrollDisabled(true)
            .scrollIndicators(.hidden)
            .frame(height: Self.lineHeight * CGFloat(Self.visibleLines))
            .padding(.top, 20)
            .padding(.bottom, 14)
            .onAppear { scroll(proxy) }
            .onChange(of: currentIndex) { scroll(proxy) }
        }
        .background(Color.frost)
        .overlay(alignment: .top) { PerforationRow().padding(.top, 8) }
        .clipShape(TornBottomShape())
        .rotationEffect(.degrees(-1))
        .accessibilityHidden(true)
    }

    private func scroll(_ proxy: ScrollViewProxy) {
        guard items.indices.contains(currentIndex) else { return }
        var transaction = Transaction(animation: nil)
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            proxy.scrollTo(items[currentIndex].documentId, anchor: .center)
        }
    }
}

/// A dotted row of small holes in the page color, so they read as cut-outs.
private struct PerforationRow: View {
    var body: some View {
        Canvas { context, size in
            let spacing: CGFloat = 9, radius: CGFloat = 1.75
            var x = spacing
            while x < size.width - spacing / 2 {
                context.fill(
                    Path(ellipseIn: CGRect(x: x - radius, y: size.height / 2 - radius, width: radius * 2, height: radius * 2)),
                    with: .color(Color.enamel)
                )
                x += spacing
            }
        }
        .frame(height: 4)
    }
}

/// Straight top, left and right edges; torn zig-zag bottom. Jag depths come from a fixed
/// table so the tear is identical on every redraw.
struct TornBottomShape: Shape {
    private static let depths: [CGFloat] = [4, 1.5, 5, 2, 3.5, 1, 4.5, 2.5]

    func path(in rect: CGRect) -> Path {
        let teeth = max(Int(rect.width / 7), 2)
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        for i in stride(from: teeth - 1, through: 1, by: -1) {
            let x = rect.minX + rect.width * CGFloat(i) / CGFloat(teeth)
            let rise = i.isMultiple(of: 2) ? 0 : Self.depths[(i / 2) % Self.depths.count]
            path.addLine(to: CGPoint(x: x, y: rect.maxY - rise))
        }
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}
