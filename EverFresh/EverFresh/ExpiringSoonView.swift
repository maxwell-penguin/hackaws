import SwiftUI

struct ExpiringSoonView: View {
    private let withinDays = 3

    @State private var items: [ScannedItem] = []
    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Group {
                if isLoading && items.isEmpty {
                    ProgressView("Loading…")
                } else if let errorMessage {
                    ContentUnavailableView {
                        Label("Couldn't load items", systemImage: "exclamationmark.triangle")
                    } description: {
                        Text(errorMessage)
                    } actions: {
                        Button("Retry") { Task { await load() } }
                    }
                } else if items.isEmpty {
                    ContentUnavailableView(
                        "Nothing expiring soon",
                        systemImage: "checkmark.circle",
                        description: Text("Items expiring within \(withinDays) days will show up here.")
                    )
                } else {
                    List(items) { item in
                        NavigationLink {
                            ItemDetailView(item: item)
                        } label: {
                            ExpiringSoonRow(item: item)
                        }
                    }
                }
            }
            .navigationTitle("Expiring Soon")
            .task { await load() }
        }
    }

    private func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            items = try await ItemService.fetchExpiringSoon(withinDays: withinDays)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct ExpiringSoonRow: View {
    let item: ScannedItem

    private var daysLeft: Int? { StrapiDate.daysUntil(item.expiryDate) }

    private var label: String {
        guard let daysLeft else { return item.expiryDate ?? "Unknown" }
        if daysLeft < 0 { return "Expired" }
        if daysLeft == 0 { return "Today" }
        return "\(daysLeft)d left"
    }

    private var color: Color {
        guard let daysLeft else { return .secondary }
        return daysLeft <= 0 ? .red : .orange
    }

    var body: some View {
        HStack {
            VStack(alignment: .leading) {
                Text(item.name)
                    .font(.headline)
                Text(item.category ?? "Uncategorized")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(color)
        }
    }
}

#Preview {
    ExpiringSoonView()
}
