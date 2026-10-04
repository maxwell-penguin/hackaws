import SwiftUI

/// Walks the user through confirming a batch of receipt-scanned items one at a time, then shows
/// a summary grid. Each item was already created as a draft in Strapi by the receipt scan — this
/// flow only edits/confirms them, so leaving early never loses anything that was already
/// confirmed; later items just keep their unedited draft values.
struct ReceiptReviewFlow: View {
    let items: [ScannedItem]

    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss

    /// Working copy of the batch; edits and server responses land here so the strip and sheet reflect them.
    @State private var localItems: [ScannedItem]
    @State private var currentIndex = 0
    @State private var confirmedItems: [ScannedItem] = []

    /// Occupied slot indices per zone, from the rest of the fridge. nil if the fetch failed.
    @State private var occupied: [FridgeZone: Set<Int>]?
    /// Explicit zone choices by documentId (value nil = Auto). No entry means "use the suggestion".
    @State private var chosenZones: [String: FridgeZone?] = [:]

    @State private var isSaving = false
    @State private var showError = false
    @State private var errorMessage = ""
    @State private var showEdit = false
    @State private var showStopConfirm = false

    private static let cardTransition: AnyTransition = .asymmetric(
        insertion: .move(edge: .trailing).combined(with: .opacity),
        removal: .move(edge: .leading).combined(with: .opacity)
    )

    init(items: [ScannedItem]) {
        self.items = items
        _localItems = State(initialValue: items)
    }

    var body: some View {
        NavigationStack {
            Group {
                if items.isEmpty {
                    emptyState
                } else if currentIndex < localItems.count {
                    itemScreen
                        .id(localItems[currentIndex].documentId)
                        .transition(Self.cardTransition)
                } else {
                    ReceiptSummaryView(items: confirmedItems) {
                        appState.selectedTab = .fridge
                        dismiss()
                    }
                    .transition(Self.cardTransition)
                }
            }
            .background(Color.enamel)
            .navigationTitle(navigationTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(currentIndex < localItems.count ? .hidden : .visible, for: .navigationBar)
            .task { await loadOccupancy() }
        }
    }

    private var navigationTitle: String {
        "\(confirmedItems.count) Item\(confirmedItems.count == 1 ? "" : "s") Added"
    }

    // MARK: Zones

    private func slotCount(_ zone: FridgeZone) -> Int { FridgeLayout.slots(for: zone).count }

    private func isFull(_ zone: FridgeZone) -> Bool {
        (occupied?[zone]?.count ?? 0) >= slotCount(zone)
    }

    /// The explicit choice, else the category's suggested zone if it still has room, else Auto (nil).
    private func effectiveZone(for item: ScannedItem) -> FridgeZone? {
        if let choice = chosenZones[item.documentId] { return choice }
        guard occupied != nil, let suggestion = suggestedZone(forCategory: item.category), !isFull(suggestion) else { return nil }
        return suggestion
    }

    private func loadOccupancy() async {
        guard occupied == nil, let active = try? await ItemService.fetchActiveItems() else { return }
        let batch = Set(items.map(\.documentId))
        let assignments = FridgeLayout.resolve(items: active.filter { !batch.contains($0.documentId) })
        occupied = Dictionary(grouping: assignments.values, by: \.zone).mapValues { Set($0.map(\.slotIndex)) }
    }

    // MARK: Screen

    private var emptyState: some View {
        ContentUnavailableView {
            Label("No items found on this receipt", systemImage: "receipt")
        } actions: {
            Button("Back to Scan") {
                appState.selectedTab = .scan
                dismiss()
            }
            .buttonStyle(.borderedProminent)
        }
    }

    private var itemScreen: some View {
        let item = localItems[currentIndex]
        return VStack(spacing: 0) {
            header
            ThermalStripView(items: localItems, currentIndex: currentIndex)
                .padding(.horizontal, 24)
                .padding(.top, 8)
            progressRule
                .padding(.top, 10)
            itemSheet(item)
            actions
        }
        .sheet(isPresented: $showEdit) {
            ItemEditSheet(item: item) { localItems[currentIndex] = $0 }
        }
        .confirmationDialog(
            "Stop reviewing? The other \(remainingCount) item\(remainingCount == 1 ? " is" : "s are") already in your fridge with the details we found.",
            isPresented: $showStopConfirm,
            titleVisibility: .visible
        ) {
            Button("Stop reviewing", role: .destructive) { dismiss() }
            Button("Keep going", role: .cancel) {}
        }
        .alert("Couldn't save item", isPresented: $showError) {
            Button("Retry") { Task { await confirm() } }
            Button("OK", role: .cancel) {}
        } message: {
            Text("\(errorMessage)\nThis item wasn't confirmed. Retry, or edit it and try again.")
        }
    }

    private var remainingCount: Int { localItems.count - confirmedItems.count }

    private var header: some View {
        HStack {
            Button {
                if remainingCount > 0 { showStopConfirm = true } else { dismiss() }
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 17, weight: .semibold))
                    .frame(width: 44, height: 44, alignment: .leading)
            }
            .accessibilityLabel("Close")
            Spacer()
            Text("\(currentIndex + 1) of \(localItems.count)")
                .font(.everFreshStamp)
                .accessibilityLabel("Item \(currentIndex + 1) of \(localItems.count)")
        }
        .padding(.horizontal, 20)
    }

    private var progressRule: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Rectangle().fill(Color.shelfSteel)
                Rectangle()
                    .fill(Color.freezerUltramarine)
                    .frame(width: geometry.size.width * CGFloat(confirmedItems.count) / CGFloat(max(localItems.count, 1)))
            }
        }
        .frame(height: 2)
    }

    private func itemSheet(_ item: ScannedItem) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center, spacing: 14) {
                ItemTile(item: item, size: 64, showsName: false)
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.name)
                        .font(.everFreshTitle)
                        .tracking(-0.4)
                        .lineLimit(2)
                        .minimumScaleFactor(0.6)
                    Text(item.category ?? "Uncategorized")
                        .font(.everFreshBody)
                        .foregroundStyle(Color.shelfSteel)
                }
            }
            .padding(.bottom, 12)

            sheetRow("Goes in") { zoneMenu(for: item) }
            sheetRow("Use by") {
                if StrapiDate.daysUntil(item.expiryDate) != nil {
                    DateTape(expiryDate: item.expiryDate, style: .full)
                } else {
                    Text("No date").foregroundStyle(Color.shelfSteel)
                }
            }
            sheetRow("Price") {
                Text(item.pricePaid.map { String(format: "%.2f", $0) } ?? "—").font(.everFreshStamp)
            }
            Spacer(minLength: 0)
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color.frost)
        .padding(.top, 12)
    }

    private func sheetRow<Value: View>(_ label: String, @ViewBuilder value: () -> Value) -> some View {
        VStack(spacing: 0) {
            Rectangle().fill(Color.shelfSteel).frame(height: 0.5)
            HStack {
                Text(label).font(.everFreshBody).foregroundStyle(Color.shelfSteel)
                Spacer()
                value().font(.everFreshBody)
            }
            .frame(minHeight: 48)
        }
    }

    private func zoneMenu(for item: ScannedItem) -> some View {
        let current = effectiveZone(for: item)
        return Menu {
            Button { chosenZones[item.documentId] = .some(nil) } label: {
                menuLabel("Auto", selected: current == nil)
            }
            if occupied != nil {
                ForEach(FridgeLayout.displayOrder, id: \.self) { zone in
                    Button { chosenZones[item.documentId] = .some(zone) } label: {
                        menuLabel(isFull(zone) ? "\(zone.displayName) (Full)" : zone.displayName, selected: current == zone)
                    }
                    .disabled(isFull(zone))
                }
            }
        } label: {
            HStack(spacing: 4) {
                Text(current?.displayName ?? "Auto")
                Image(systemName: "chevron.up.chevron.down").font(.caption2).foregroundStyle(Color.shelfSteel)
            }
            .foregroundStyle(Color.compressor)
        }
    }

    @ViewBuilder
    private func menuLabel(_ title: String, selected: Bool) -> some View {
        if selected { Label(title, systemImage: "checkmark") } else { Text(title) }
    }

    private var actions: some View {
        VStack(spacing: 4) {
            Button {
                Task { await confirm() }
            } label: {
                ZStack {
                    if isSaving {
                        ProgressView().tint(.white)
                    } else {
                        Text("Looks right").font(.system(.body, weight: .semibold))
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 50)
                .foregroundStyle(.white)
                .background(Color.freezerUltramarine, in: RoundedRectangle(cornerRadius: 14))
            }
            .disabled(isSaving)

            Button("Edit") { showEdit = true }
                .foregroundStyle(Color.compressor)
                .frame(minHeight: 44)
                .disabled(isSaving)
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 4)
    }

    // MARK: Saving

    private func confirm() async {
        guard !isSaving, currentIndex < localItems.count else { return }
        isSaving = true
        defer { isSaving = false }

        var updated = localItems[currentIndex]
        // Quantity is "percent left" (100 = full); an item just confirmed into the fridge starts full.
        updated.quantity = 100

        do {
            let saved = try await ItemService.saveItem(updated)
            await place(saved)
            localItems[currentIndex] = saved
            confirmedItems.append(saved)
            withAnimation(.easeInOut(duration: 0.3)) {
                currentIndex += 1
            }
        } catch {
            errorMessage = error.localizedDescription
            showError = true
        }
    }

    /// Moves the saved item into its chosen zone's first free slot. Best-effort: a failure here never blocks the flow.
    private func place(_ item: ScannedItem) async {
        guard let zone = effectiveZone(for: item), let taken = occupied,
              let index = FridgeLayout.nearestFreeSlot(in: zone, to: FridgeLayout.slots(for: zone)[0], occupied: taken[zone] ?? [])
        else { return }
        occupied?[zone, default: []].insert(index)
        let center = FridgeLayout.slots(for: zone)[index]
        try? await ItemService.updatePosition(documentId: item.documentId, x: center.x, y: center.y)
    }
}

private struct ReceiptSummaryView: View {
    let items: [ScannedItem]
    let onDone: () -> Void

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 16), count: 3)

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                LazyVGrid(columns: columns, spacing: 20) {
                    ForEach(items) { item in
                        VStack(spacing: 8) {
                            Image(systemName: CategoryIcons.symbol(for: item.category ?? "other"))
                                .font(.system(size: 26))
                                .frame(width: 56, height: 56)
                                .background(Color.frost, in: Circle())
                                .overlay(Circle().strokeBorder(Color.shelfSteel, lineWidth: 1))
                            Text(item.name)
                                .font(.system(.caption, weight: .heavy))
                                .multilineTextAlignment(.center)
                                .lineLimit(2)
                        }
                    }
                }
                .padding()
            }

            Button("Done", action: onDone)
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .padding()
        }
    }
}

#Preview {
    ReceiptReviewFlow(items: [])
        .environmentObject(AppState())
}
