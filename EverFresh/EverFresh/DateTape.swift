import SwiftUI

/// The one place expiry urgency thresholds live.
enum ExpiryUrgency {
    case expired  // today or past
    case soon     // 1...3 days
    case fresh    // more than 3 days

    static func from(daysLeft: Int) -> ExpiryUrgency {
        if daysLeft <= 0 { return .expired }
        if daysLeft <= 3 { return .soon }
        return .fresh
    }
}

/// A strip of masking tape carrying an expiry. Draws nothing for a missing/unparseable date.
struct DateTape: View {
    enum Style { case compact, full }

    let expiryDate: String?
    let style: Style

    // Fixed ink for amber: Compressor flips light in dark mode and fails contrast on amber.
    private static let amberInk = Color(red: 0x18 / 255, green: 0x26 / 255, blue: 0x2E / 255)

    private static let useByFormat = Date.FormatStyle(timeZone: TimeZone(identifier: "UTC")!)
        .month(.abbreviated).day()

    var body: some View {
        if let daysLeft = StrapiDate.daysUntil(expiryDate) {
            let urgency = ExpiryUrgency.from(daysLeft: daysLeft)
            Text(label(daysLeft: daysLeft))
                .font(.everFreshStamp)
                .foregroundStyle(ink(urgency))
                .lineLimit(1)
                .fixedSize()
                .padding(.leading, 6)
                .padding(.trailing, 9)
                .padding(.vertical, 2)
                .background(fill(urgency))
                .overlay {
                    if urgency == .fresh {
                        TornTapeShape().stroke(Color.shelfSteel, lineWidth: 0.5)
                    }
                }
                .clipShape(TornTapeShape())
                .rotationEffect(.degrees(-2))
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(spokenLabel(daysLeft: daysLeft))
        }
    }

    @ViewBuilder
    private func fill(_ urgency: ExpiryUrgency) -> some View {
        switch urgency {
        case .fresh: Color.frost
        case .soon: Color.soonAmber
        case .expired: Color.useByRed
        }
    }

    private func ink(_ urgency: ExpiryUrgency) -> Color {
        switch urgency {
        case .fresh: .compressor
        case .soon: Self.amberInk
        case .expired: .white
        }
    }

    private func label(daysLeft: Int) -> String {
        switch style {
        case .full:
            let date = StrapiDate.date(from: expiryDate) ?? Date()
            return "Use by \(date.formatted(Self.useByFormat))"
        case .compact:
            if daysLeft < 0 { return "Expired" }
            if daysLeft == 0 { return "Today" }
            return "\(daysLeft)d"
        }
    }

    private func spokenLabel(daysLeft: Int) -> String {
        if daysLeft == 0 { return "Expires today" }
        let n = abs(daysLeft)
        let days = "\(n) day\(n == 1 ? "" : "s")"
        return daysLeft < 0 ? "Expired \(days) ago" : "Expires in \(days)"
    }
}

/// Straight left edge, torn zig-zag right edge. Jag depths come from a fixed table, so the
/// tear is hand-made-looking but identical on every redraw.
struct TornTapeShape: Shape {
    private static let depths: [CGFloat] = [3, 1, 3.5, 1.5, 2.5, 1, 3, 2]

    func path(in rect: CGRect) -> Path {
        let teeth = max(Int(rect.height / 3.5), 2)
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        for i in 1..<teeth {
            let y = rect.minY + rect.height * CGFloat(i) / CGFloat(teeth)
            let inset = i.isMultiple(of: 2) ? 0 : Self.depths[(i / 2) % Self.depths.count]
            path.addLine(to: CGPoint(x: rect.maxX - inset, y: y))
        }
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

#Preview {
    VStack(alignment: .leading, spacing: 12) {
        ForEach(["2026-09-30", "2026-10-04", "2026-10-06", "2026-10-20", nil], id: \.self) { d in
            HStack {
                DateTape(expiryDate: d, style: .compact)
                DateTape(expiryDate: d, style: .full)
            }
        }
    }
    .padding()
    .background(Color.enamel)
}
