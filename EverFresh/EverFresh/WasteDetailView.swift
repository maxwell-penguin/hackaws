import SwiftUI

struct WasteDetailView: View {
    @State private var items: [ScannedItem] = []
    @State private var month = Calendar.current.date(from: Calendar.current.dateComponents([.year, .month], from: Date()))!

    private let calendar = Calendar.current
    private var currentMonth: Date { calendar.date(from: calendar.dateComponents([.year, .month], from: Date()))! }
    private var summary: MonthSummary { summarize(items: items, month: month) }
    private var earliest: Date? { earliestActivityMonth(items: items) }
    private var monthName: String { month.formatted(.dateTime.month(.wide)) }

    private func money(_ value: Double) -> String { value.formatted(.currency(code: "USD")) }
    private func plural(_ n: Int, _ one: String, _ many: String) -> String { n == 1 ? one : many }

    var body: some View {
        let s = summary
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                stepper
                if s.wastedCount == 0 && s.usedCount == 0 {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Nothing logged for \(monthName).").font(.everFreshBody)
                        Text("When you mark items as used up or thrown out, totals show up here.")
                            .font(.everFreshBody)
                            .foregroundStyle(Color.shelfSteel)
                    }
                } else {
                    stats(s)
                    if !s.topWastedCategories.isEmpty {
                        section("Most wasted") {
                            ForEach(Array(s.topWastedCategories.enumerated()), id: \.offset) { index, entry in
                                if index > 0 { rule }
                                HStack {
                                    Text(entry.name).font(.everFreshBody)
                                    Spacer()
                                    Text(money(entry.value)).font(.everFreshStamp)
                                }
                                .padding(.vertical, 8)
                            }
                        }
                    }
                    thrownOut(s)
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Color.enamel)
        .navigationTitle("Waste")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { Task { if let fetched = try? await ItemService.fetchAllItems() { items = fetched } } }
    }

    private var rule: some View { Rectangle().fill(Color.shelfSteel).frame(height: 0.5) }

    private var stepper: some View {
        HStack {
            Button { month = calendar.date(byAdding: .month, value: -1, to: month) ?? month } label: {
                Image(systemName: "chevron.left")
            }
            .disabled(earliest.map { month <= $0 } ?? true)
            .accessibilityLabel("Previous month")
            Spacer()
            Text(month.formatted(.dateTime.month(.wide).year()))
                .font(.everFreshTitle)
                .tracking(-0.4)
                .minimumScaleFactor(0.7)
                .lineLimit(1)
            Spacer()
            Button { month = calendar.date(byAdding: .month, value: 1, to: month) ?? month } label: {
                Image(systemName: "chevron.right")
            }
            .disabled(month >= currentMonth)
            .accessibilityLabel("Next month")
        }
        .foregroundStyle(Color.compressor)
        .buttonStyle(.plain)
        .font(.system(size: 18, weight: .semibold))
    }

    private func stats(_ s: MonthSummary) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Wasted").font(.caption).foregroundStyle(Color.shelfSteel)
                Text(money(s.wastedValue)).font(.system(size: 34, weight: .heavy, design: .monospaced))
                Text("\(s.wastedCount) \(plural(s.wastedCount, "item", "items")) thrown out")
                    .font(.footnote).foregroundStyle(Color.shelfSteel)
                if s.unpricedWastedCount > 0 {
                    Text("\(s.unpricedWastedCount) had no price, so \(s.unpricedWastedCount == 1 ? "it isn't" : "they aren't") in the total")
                        .font(.footnote).foregroundStyle(Color.shelfSteel)
                }
            }
            VStack(alignment: .leading, spacing: 2) {
                Text("Used").font(.caption).foregroundStyle(Color.shelfSteel)
                Text(money(s.usedValue)).font(.system(size: 34, weight: .heavy, design: .monospaced))
                Text("\(s.usedCount) \(plural(s.usedCount, "item", "items")) used up")
                    .font(.footnote).foregroundStyle(Color.shelfSteel)
            }
            if let rate = s.wasteRate, s.wastedCount > 0 {
                Text("Of the food you finished this month, \(Int((rate * 100).rounded()))% by value was thrown out.")
                    .font(.everFreshBody)
            }
        }
    }

    @ViewBuilder
    private func thrownOut(_ s: MonthSummary) -> some View {
        let lines = s.wastedLines
        if !lines.isEmpty {
            section("Thrown out") {
                ForEach(Array(lines.enumerated()), id: \.element.item.documentId) { index, line in
                    if index > 0 { rule }
                    NavigationLink {
                        ItemDetailView(item: line.item)
                    } label: {
                        HStack(spacing: 12) {
                            ItemTile(item: line.item, size: 36, showsName: false)
                            Text(line.item.name).font(.everFreshBody).lineLimit(1)
                            Spacer(minLength: 8)
                            Text(line.resolvedDate.formatted(.dateTime.month(.abbreviated).day()))
                                .font(.everFreshBody).foregroundStyle(Color.shelfSteel)
                            Text(line.value > 0 ? money(line.value) : "—").font(.everFreshStamp)
                        }
                        .padding(.vertical, 8)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).everFreshSectionHeader()
            content()
        }
    }
}
