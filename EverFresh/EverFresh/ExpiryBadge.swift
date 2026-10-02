import SwiftUI

/// A compact clock + days-left chip. Red (expired/today) and amber (within 3 days) get a filled
/// capsule; fresh items get no colored treatment at all — fresh is the absence of a signal.
/// Shared by the visual canvas's floating icons and the zone list's rows so both always agree.
struct ExpiryBadge: View {
    let daysLeft: Int

    /// nil means fresh: no signal color.
    static func urgencyColor(daysLeft: Int) -> Color? {
        daysLeft <= 0 ? .useByRed : (daysLeft <= 3 ? .soonAmber : nil)
    }

    // Fixed dark ink for the amber capsule: Compressor flips light in dark mode and washes out on amber.
    private var capsuleInk: Color {
        daysLeft <= 0 ? .white : Color(red: 0x18 / 255, green: 0x26 / 255, blue: 0x2E / 255)
    }

    var body: some View {
        let color = Self.urgencyColor(daysLeft: daysLeft)
        HStack(spacing: 2) {
            Image(systemName: "clock.fill")
                .font(.system(size: 8))
            Text(daysLeft <= 0 ? "!" : "\(daysLeft)")
                .font(.system(size: 9, weight: .bold, design: .monospaced))
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 2)
        .background { if let color { Capsule().fill(color) } }
        .foregroundStyle(color == nil ? Color.compressor : capsuleInk)
    }
}

#Preview {
    HStack {
        ExpiryBadge(daysLeft: -1)
        ExpiryBadge(daysLeft: 0)
        ExpiryBadge(daysLeft: 2)
        ExpiryBadge(daysLeft: 10)
    }
    .padding()
}
