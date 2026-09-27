import SwiftUI

/// Read-only, zone-grouped view of the same items FridgeVisualView shows — grouped by each
/// item's actual saved position (falling back to (0,0) when unset), not the visual canvas's
/// ephemeral fallback layout. Tapping still navigates to detail; there's no dragging here.
struct FridgeListView: View {
    let items: [ScannedItem]

    private static let orderedZones: [FridgeZone] = [
        .topShelf, .middleShelf, .bottomShelf, .leftDoorBin, .rightDoorBin, .crisperDrawer,
    ]

    private var sections: [(zone: FridgeZone, items: [ScannedItem])] {
        let grouped = Dictionary(grouping: items) { item in
            FridgeLayout.zone(for: CGPoint(x: item.positionX ?? 0, y: item.positionY ?? 0))
        }
        return Self.orderedZones.compactMap { zone in
            guard let zoneItems = grouped[zone], !zoneItems.isEmpty else { return nil }
            return (zone, zoneItems.sorted(by: Self.byExpiryAscending))
        }
    }

    /// Soonest-expiring first; items with no expiryDate sort after every item that has one.
    private static func byExpiryAscending(_ lhs: ScannedItem, _ rhs: ScannedItem) -> Bool {
        switch (StrapiDate.date(from: lhs.expiryDate), StrapiDate.date(from: rhs.expiryDate)) {
        case let (l?, r?):
            return l < r
        case (nil, _):
            return false
        case (_, nil):
            return true
        }
    }

    var body: some View {
        List {
            ForEach(sections, id: \.zone) { section in
                Section(section.zone.displayName) {
                    ForEach(section.items) { item in
                        NavigationLink {
                            ItemDetailView(item: item)
                        } label: {
                            FridgeListRow(item: item)
                        }
                    }
                }
            }
        }
    }
}

private struct FridgeListRow: View {
    let item: ScannedItem

    var body: some View {
        HStack {
            Image(systemName: CategoryIcons.symbol(for: item.category ?? "other"))
                .foregroundStyle(.secondary)
                .frame(width: 24)
            Text(item.name)
            Spacer()
            if let daysLeft = StrapiDate.daysUntil(item.expiryDate) {
                ExpiryBadge(daysLeft: daysLeft)
            }
        }
    }
}

#Preview {
    NavigationStack {
        FridgeListView(items: [])
    }
}
