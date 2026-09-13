import SwiftUI

struct GroceryHistoryView: View {
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
                        Label("Couldn't load history", systemImage: "exclamationmark.triangle")
                    } description: {
                        Text(errorMessage)
                    } actions: {
                        Button("Retry") { Task { await load() } }
                    }
                } else if items.isEmpty {
                    ContentUnavailableView(
                        "No items yet",
                        systemImage: "tray",
                        description: Text("Items you scan or import will show up here.")
                    )
                } else {
                    List {
                        ForEach(dayGroups, id: \.label) { group in
                            Section(group.label) {
                                ForEach(group.items) { item in
                                    NavigationLink {
                                        ItemDetailView(item: item)
                                    } label: {
                                        GroceryHistoryRow(item: item)
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("History")
            .task { await load() }
        }
    }

    private struct DayGroup {
        let day: Date
        let label: String
        let items: [ScannedItem]
    }

    /// Items already arrive sorted createdAt:desc from the server, so grouping preserves that order within each day.
    private var dayGroups: [DayGroup] {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: items) { item in
            calendar.startOfDay(for: StrapiDate.dateTime(from: item.createdAt) ?? Date())
        }
        return grouped.keys.sorted(by: >).map { day in
            DayGroup(day: day, label: Self.label(for: day), items: grouped[day] ?? [])
        }
    }

    private static func label(for day: Date) -> String {
        if Calendar.current.isDateInToday(day) { return "Today" }
        if Calendar.current.isDateInYesterday(day) { return "Yesterday" }
        return day.formatted(date: .abbreviated, time: .omitted)
    }

    private func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            items = try await ItemService.fetchAllItems()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct GroceryHistoryRow: View {
    let item: ScannedItem

    private var priceLabel: String {
        item.pricePaid.map { $0.formatted(.currency(code: "USD")) } ?? "—"
    }

    private var sourceIcon: String {
        item.source == "receipt" ? "receipt" : "camera.viewfinder"
    }

    var body: some View {
        HStack {
            Image(systemName: sourceIcon)
                .foregroundStyle(.secondary)
                .frame(width: 20)
            VStack(alignment: .leading) {
                Text(item.name)
                    .font(.headline)
                Text(item.category)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(priceLabel)
                .foregroundStyle(.secondary)
        }
    }
}

#Preview {
    GroceryHistoryView()
}
