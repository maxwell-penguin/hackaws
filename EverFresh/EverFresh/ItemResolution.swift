import SwiftUI

/// The two ways to take an item out of the fridge. Every entry point goes through this.
enum ItemResolution {
    case usedUp, threwOut

    var title: String { self == .usedUp ? "Used it up" : "Threw it out" }
    var historyLabel: String { self == .usedUp ? "Used up" : "Thrown out" }

    /// The resolution an item's status records, if it has been resolved.
    init?(status: String) {
        switch status {
        case "consumed": self = .usedUp
        case "wasted": self = .threwOut
        default: return nil
        }
    }

    @MainActor
    func perform(on item: ScannedItem) async throws {
        switch self {
        case .usedUp: try await ItemService.markConsumed(documentId: item.documentId)
        case .threwOut: try await ItemService.markWasted(documentId: item.documentId)
        }
    }
}

/// "Throwing it out counts about $2.10 as wasted, based on 60% left." nil when there's no price.
func wasteNote(for item: ScannedItem) -> String? {
    guard let price = item.pricePaid, price > 0 else { return nil }
    let percent = item.quantity ?? 100
    let amount = (price * percent / 100).formatted(.currency(code: "USD"))
    return "Throwing it out counts about \(amount) as wasted, based on \(Int(percent.rounded()))% left."
}

struct ResolveFailure: Identifiable {
    let id = UUID()
    let itemName: String
    let message: String
}

extension View {
    /// "Couldn't update <name>" with the error text.
    func resolveFailureAlert(_ failure: Binding<ResolveFailure?>) -> some View {
        alert(
            "Couldn't update \(failure.wrappedValue?.itemName ?? "item")",
            isPresented: Binding(get: { failure.wrappedValue != nil }, set: { if !$0 { failure.wrappedValue = nil } })
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(failure.wrappedValue?.message ?? "")
        }
    }

    /// Dialog offering Used it up / Threw it out for `item`. `onResolved` runs only after the
    /// request succeeds; on failure an alert explains and nothing changes.
    func resolveDialog(
        item: Binding<ScannedItem?>,
        onResolved: @escaping (ScannedItem, ItemResolution) -> Void
    ) -> some View {
        modifier(ResolveDialog(item: item, onResolved: onResolved))
    }

    /// Trailing swipe actions that resolve directly, with no dialog.
    func resolveSwipeActions(
        for item: ScannedItem,
        failure: Binding<ResolveFailure?>,
        onResolved: @escaping (ScannedItem, ItemResolution) -> Void
    ) -> some View {
        swipeActions(edge: .trailing, allowsFullSwipe: false) {
            ForEach([ItemResolution.usedUp, .threwOut], id: \.title) { resolution in
                Button(resolution.title) {
                    Task { @MainActor in
                        do {
                            try await resolution.perform(on: item)
                            onResolved(item, resolution)
                        } catch {
                            failure.wrappedValue = ResolveFailure(itemName: item.name, message: error.localizedDescription)
                        }
                    }
                }
                .tint(resolution == .threwOut ? Color.useByRed : nil)
            }
        }
    }
}

private struct ResolveDialog: ViewModifier {
    @Binding var item: ScannedItem?
    let onResolved: (ScannedItem, ItemResolution) -> Void
    @State private var failure: ResolveFailure?

    func body(content: Content) -> some View {
        content
            .confirmationDialog(
                item?.name ?? "",
                isPresented: Binding(get: { item != nil }, set: { if !$0 { item = nil } }),
                titleVisibility: .visible,
                presenting: item
            ) { target in
                ForEach([ItemResolution.usedUp, .threwOut], id: \.title) { resolution in
                    Button(resolution.title) { run(resolution, on: target) }
                }
                Button("Cancel", role: .cancel) {}
            } message: { target in
                if let note = wasteNote(for: target) { Text(note) }
            }
            .resolveFailureAlert($failure)
    }

    private func run(_ resolution: ItemResolution, on target: ScannedItem) {
        Task { @MainActor in
            do {
                try await resolution.perform(on: target)
                onResolved(target, resolution)
            } catch {
                failure = ResolveFailure(itemName: target.name, message: error.localizedDescription)
            }
        }
    }
}
