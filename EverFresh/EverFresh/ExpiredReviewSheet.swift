import SwiftUI

/// Where the user clears items past their date. Nothing is auto-marked. The container owns the
/// items; this sheet just reports what happened so the two stay in sync.
struct ExpiredReviewSheet: View {
    let items: [ScannedItem]
    let onRemoved: (ScannedItem) -> Void
    let onExtended: (ScannedItem, String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var failure: ResolveFailure?
    @State private var showThrowAll = false
    @State private var isThrowingAll = false
    @State private var bulkFailure: String?

    /// Most days past first.
    private var sorted: [ScannedItem] {
        items.sorted { (StrapiDate.daysUntil($0.expiryDate) ?? 0) < (StrapiDate.daysUntil($1.expiryDate) ?? 0) }
    }

    private var totalWaste: Double { items.compactMap(wasteAmount(for:)).reduce(0, +) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Past their date").font(.everFreshTitle).tracking(-0.4)
                Text("Dates are estimates. Toss what looks or smells off and keep what's fine.")
                    .font(.everFreshBody)
                    .foregroundStyle(Color.shelfSteel)
            }
            .padding(.horizontal, 20)
            .padding(.top, 24)
            .padding(.bottom, 12)

            List(sorted) { item in
                row(item)
                    .listRowBackground(Color.enamel)
                    .listRowSeparatorTint(Color.shelfSteel)
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .buttonStyle(.borderless)
            .disabled(isThrowingAll)

            if items.count > 1 {
                Group {
                    if isThrowingAll {
                        ProgressView()
                    } else {
                        Button("Throw out all \(items.count)") { showThrowAll = true }
                            .foregroundStyle(Color.useByRed)
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 44)
                .padding(.bottom, 8)
            }
        }
        .background(Color.enamel)
        .presentationDetents([.large])
        .onChange(of: items.isEmpty) { _, empty in if empty { dismiss() } }
        .resolveFailureAlert($failure)
        .confirmationDialog(
            "Throw out all \(items.count) items?",
            isPresented: $showThrowAll,
            titleVisibility: .visible
        ) {
            Button("Throw out all \(items.count)", role: .destructive) { Task { await throwOutAll() } }
            Button("Cancel", role: .cancel) {}
        } message: {
            if totalWaste > 0 { Text("About \(totalWaste.formatted(.currency(code: "USD"))) counts as wasted.") }
        }
        .alert("Not everything was thrown out", isPresented: Binding(get: { bulkFailure != nil }, set: { if !$0 { bulkFailure = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(bulkFailure ?? "")
        }
    }

    private func row(_ item: ScannedItem) -> some View {
        HStack(alignment: .top, spacing: 12) {
            ItemTile(item: item, size: 40, showsName: false)
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Text(item.name).font(.system(.body, weight: .semibold)).lineLimit(1)
                    DateTape(expiryDate: item.expiryDate, style: .compact)
                }
                HStack(spacing: 20) {
                    Button("Threw it out") { Task { await throwOut(item) } }
                        .foregroundStyle(Color.useByRed)
                    Menu("Still good") {
                        Button("3 more days") { Task { await extend(item, days: 3) } }
                        Button("1 more week") { Task { await extend(item, days: 7) } }
                    }
                    .foregroundStyle(Color.freezerUltramarine)
                }
                .font(.everFreshBody)
            }
            Spacer(minLength: 8)
            if let price = item.pricePaid {
                Text(price.formatted(.currency(code: "USD"))).font(.everFreshStamp).foregroundStyle(Color.shelfSteel)
            }
        }
        .padding(.vertical, 4)
    }

    private func throwOut(_ item: ScannedItem) async {
        do {
            try await ItemResolution.threwOut.perform(on: item)
            onRemoved(item)
        } catch {
            failure = ResolveFailure(itemName: item.name, message: error.localizedDescription)
        }
    }

    /// Counts from today, not from the old date. The date is built as UTC midnight of the *local*
    /// calendar day, because StrapiDate.string(from:) formats in UTC.
    private func extend(_ item: ScannedItem, days: Int) async {
        let local = Calendar.current.date(byAdding: .day, value: days, to: Date()) ?? Date()
        let c = Calendar.current.dateComponents([.year, .month, .day], from: local)
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC")!
        let target = utc.date(from: c) ?? local
        do {
            try await ItemService.updateExpiryDate(documentId: item.documentId, to: target)
            onExtended(item, StrapiDate.string(from: target))
        } catch {
            failure = ResolveFailure(itemName: item.name, message: error.localizedDescription)
        }
    }

    private func throwOutAll() async {
        let queue = sorted
        isThrowingAll = true
        defer { isThrowingAll = false }
        for (index, item) in queue.enumerated() {
            do {
                try await ItemResolution.threwOut.perform(on: item)
                onRemoved(item)
            } catch {
                bulkFailure = "Threw out \(index) of \(queue.count). Couldn't update \(item.name)."
                return
            }
        }
    }
}
