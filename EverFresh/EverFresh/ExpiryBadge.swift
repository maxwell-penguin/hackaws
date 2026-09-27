import SwiftUI

/// A compact clock + days-left chip, colored red (expired/today), orange (within 3 days), or
/// neutral otherwise. Shared by the visual canvas's floating icons and the zone list's rows so
/// both always agree on urgency coloring.
struct ExpiryBadge: View {
    let daysLeft: Int

    private var color: Color {
        daysLeft <= 0 ? .red : (daysLeft <= 3 ? .orange : .secondary)
    }

    var body: some View {
        HStack(spacing: 2) {
            Image(systemName: "clock.fill")
                .font(.system(size: 8))
            Text(daysLeft <= 0 ? "!" : "\(daysLeft)")
                .font(.system(size: 9, weight: .bold))
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 2)
        .background(color, in: Capsule())
        .foregroundStyle(.white)
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
