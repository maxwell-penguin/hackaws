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
                            .buttonStyle(.borderedProminent)
                    }
                } else if items.isEmpty {
                    ContentUnavailableView(
                        "No items yet",
                        systemImage: "tray",
                        description: Text("Items you scan or import will show up here.")
                    )
                } else {
                    List {
                        if hasResolvedItems { wasteHeader }
                        ForEach(dayGroups, id: \.label) { group in
                            Section {
                                ForEach(group.items) { item in
                                    NavigationLink {
                                        ItemDetailView(item: item)
                                    } label: {
                                        GroceryHistoryRow(item: item)
                                    }
                                    .listRowBackground(Color.frost)
                                }
                            } header: {
                                Text(group.label).everFreshSectionHeader()
                            }
                        }
                    }
                    .scrollContentBackground(.hidden)
                }
            }
            .background(Color.enamel)
            .navigationTitle("History")
            .onAppear { Task { await load() } }
        }
    }

    private var hasResolvedItems: Bool {
        items.contains { $0.status == "wasted" || $0.status == "consumed" }
    }

    private var wasteHeader: some View {
        let s = summarize(items: items, month: Date())
        let money = { (v: Double) in v.formatted(.currency(code: "USD")) }
        let month = Date().formatted(.dateTime.month(.wide))
        let nothing = s.wastedCount == 0 && s.usedCount == 0
        return Section {
            NavigationLink {
                WasteDetailView()
            } label: {
                if nothing {
                    Text("Nothing logged this month").font(.everFreshBody).foregroundStyle(Color.shelfSteel)
                } else {
                    HStack(alignment: .top, spacing: 24) {
                        wasteColumn("Wasted", money(s.wastedValue), "\(s.wastedCount) item\(s.wastedCount == 1 ? "" : "s") thrown out")
                        wasteColumn("Used", money(s.usedValue), "\(s.usedCount) item\(s.usedCount == 1 ? "" : "s") used up")
                    }
                }
            }
            .listRowBackground(Color.frost)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(nothing
                ? "\(month): nothing logged this month"
                : "\(month): wasted \(money(s.wastedValue)), \(s.wastedCount) thrown out. Used \(money(s.usedValue)), \(s.usedCount) used up.")
            .accessibilityAddTraits(.isLink)
        } header: {
            Text(month).everFreshSectionHeader()
        }
    }

    private func wasteColumn(_ label: String, _ value: String, _ detail: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.caption).foregroundStyle(Color.shelfSteel)
            Text(value).font(.system(size: 28, weight: .heavy, design: .monospaced))
            Text(detail).font(.footnote).foregroundStyle(Color.shelfSteel)
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
        switch item.source {
        case "receipt": return "receipt"
        case "manual-scan": return "camera.viewfinder"
        default: return "questionmark.circle"
        }
    }

    var body: some View {
        HStack {
            Image(systemName: sourceIcon)
                .foregroundStyle(Color.shelfSteel)
                .frame(width: 20)
            VStack(alignment: .leading) {
                Text(item.name)
                    .font(.everFreshItemName)
                    .tracking(-0.2)
                if let resolution = ItemResolution(status: item.status) {
                    Text(resolution.historyLabel)
                        .font(.everFreshBody)
                        .foregroundStyle(Color.shelfSteel)
                }
                Text(item.category ?? "Uncategorized")
                    .font(.everFreshBody)
                    .foregroundStyle(Color.shelfSteel)
            }
            Spacer()
            Text(priceLabel)
                .font(.everFreshStamp)
        }
    }
}

#Preview {
    GroceryHistoryView()
}
