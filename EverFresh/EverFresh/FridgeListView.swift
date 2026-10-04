import SwiftUI

/// Read-only, zone-grouped view of the same items FridgeVisualView shows, grouped by the
/// same slot assignments so the two modes always agree. Tapping navigates to detail.
struct FridgeListView: View {
    let items: [ScannedItem]
    let assignments: [String: SlotAssignment]
    let onConsume: (ScannedItem) -> Void

    private var sections: [(zone: FridgeZone, items: [ScannedItem])] {
        let grouped = Dictionary(grouping: items) { assignments[$0.documentId]?.zone ?? FridgeLayout.displayOrder[0] }
        return FridgeLayout.displayOrder.compactMap { zone in
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
                Section {
                    ForEach(section.items) { item in
                        NavigationLink {
                            ItemDetailView(item: item)
                        } label: {
                            FridgeListRow(item: item)
                        }
                        .swipeActions {
                            Button("Mark as Consumed", role: .destructive) {
                                onConsume(item)
                            }
                        }
                        .listRowBackground(Color.frost)
                    }
                } header: {
                    Text(section.zone.displayName).everFreshSectionHeader()
                }
            }
        }
        .scrollContentBackground(.hidden)
    }
}

private struct FridgeListRow: View {
    let item: ScannedItem

    var body: some View {
        HStack {
            Image(systemName: CategoryIcons.symbol(for: item.category ?? "other"))
                .foregroundStyle(Color.shelfSteel)
                .frame(width: 24)
            Text(item.name)
                .font(.everFreshItemName)
                .tracking(-0.2)
            Spacer()
            DateTape(expiryDate: item.expiryDate, style: .compact)
        }
    }
}

#Preview {
    NavigationStack {
        FridgeListView(items: [], assignments: [:], onConsume: { _ in })
    }
}
