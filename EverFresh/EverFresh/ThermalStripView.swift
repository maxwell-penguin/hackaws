import SwiftUI

/// Receipt-paper strip listing every item in the batch, one line each. Decorative: the item
/// sheet carries the same information, so it's hidden from accessibility.
struct ThermalStripView: View {
    let items: [ScannedItem]
    let currentIndex: Int

    private static let lineHeight: CGFloat = 22
    private static let visibleLines = 5
    /// At rest the current line sits in the window's third row.
    private static let restRow = 2

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var offset: CGFloat
    @State private var tickTask: Task<Void, Never>?

    init(items: [ScannedItem], currentIndex: Int) {
        self.items = items
        self.currentIndex = currentIndex
        _offset = State(initialValue: Self.restOffset(index: currentIndex, count: items.count))
    }

    /// Content offset that puts `index` in the rest row, clamped at the start and end of the list.
    private static func restOffset(index: Int, count: Int) -> CGFloat {
        let firstVisible = min(max(index - restRow, 0), max(count - visibleLines, 0))
        return -CGFloat(firstVisible) * lineHeight
    }

    private func price(_ item: ScannedItem) -> String {
        item.pricePaid.map { String(format: "%.2f", $0) } ?? "—"
    }

    private var shownOffset: CGFloat {
        reduceMotion ? Self.restOffset(index: currentIndex, count: items.count) : offset
    }

    private var lines: some View {
        VStack(spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.element.documentId) { index, item in
                HStack {
                    Text(item.name).lineLimit(1)
                    Spacer(minLength: 12)
                    Text(price(item))
                }
                .font(.everFreshStamp)
                .foregroundStyle(index < currentIndex ? Color.shelfSteel : Color.compressor)
                .animation(reduceMotion ? Motion.reducedFade : Motion.stripTick, value: currentIndex)
                .frame(height: Self.lineHeight)
                .overlay(alignment: .bottom) {
                    if index == currentIndex {
                        Rectangle().fill(Color.freezerUltramarine).frame(height: 2)
                    }
                }
            }
        }
        .padding(.horizontal, 16)
        .offset(y: shownOffset)
    }

    var body: some View {
        let windowHeight = Self.lineHeight * CGFloat(Self.visibleLines)
        ZStack(alignment: .top) {
            // Under Reduce Motion the whole line block cross-fades to its new position.
            lines.id(reduceMotion ? shownOffset : 0).transition(.opacity)
        }
        .frame(height: windowHeight, alignment: .top)
        .animation(reduceMotion ? Motion.reducedFade : nil, value: currentIndex)
        .clipped()
        .mask {
            // Lines leaving the top fade out; no fade while the strip is still at the start.
            LinearGradient(
                stops: [
                    .init(color: .black.opacity(shownOffset < -0.5 ? 0 : 1), location: 0),
                    .init(color: .black, location: Self.lineHeight * 0.8 / windowHeight),
                ],
                startPoint: .top, endPoint: .bottom
            )
        }
        .padding(.top, 20)
        .padding(.bottom, 14)
        .onChange(of: currentIndex) { old, new in tick(from: old, to: new) }
        .onDisappear { tickTask?.cancel() }
        .background(Color.frost)
        .overlay(alignment: .top) { PerforationRow().padding(.top, 8) }
        .clipShape(TornBottomShape())
        .rotationEffect(.degrees(-1))
        .accessibilityHidden(true)
    }

    /// Moves to the new rest offset in equal eased steps; a newer change cancels the old ticks and
    /// first snaps to where they were headed, so the strip never rests mid-step.
    private func tick(from old: Int, to new: Int) {
        tickTask?.cancel()
        let start = Self.restOffset(index: old, count: items.count)
        let target = Self.restOffset(index: new, count: items.count)
        offset = start
        guard !reduceMotion, target != start else { offset = target; return }
        tickTask = Task { @MainActor in
            for step in 1...Motion.stripTickCount {
                withAnimation(Motion.stripTick) {
                    offset = start + (target - start) * CGFloat(step) / CGFloat(Motion.stripTickCount)
                }
                try? await Task.sleep(for: .seconds(Motion.stripTickDuration))
                if Task.isCancelled { return }
            }
            offset = target
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
