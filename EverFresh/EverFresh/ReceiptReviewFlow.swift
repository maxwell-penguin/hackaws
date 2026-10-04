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

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private enum SheetPhase { case resting, exiting, below }
    /// Which item the sheet content shows; trails `currentIndex` while the old sheet is leaving.
    @State private var sheetIndex = 0
    @State private var sheetPhase = SheetPhase.resting
    @State private var isTransitioning = false

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
                } else {
                    ReceiptSummaryView(items: confirmedItems) {
                        appState.selectedTab = .fridge
                        dismiss()
                    }
                }
            }
            .background(Color.enamel)
            .toolbar(.hidden, for: .navigationBar)
            .task { await loadOccupancy() }
        }
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
        let item = localItems[min(sheetIndex, localItems.count - 1)]
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
            ItemEditSheet(item: item) { localItems[sheetIndex] = $0 }
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
        .opacity(sheetPhase == .resting ? 1 : 0)
        .offset(y: reduceMotion ? 0 : (sheetPhase == .exiting ? -16 : (sheetPhase == .below ? 28 : 0)))
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
            .disabled(isSaving || isTransitioning)

            Button("Edit") { showEdit = true }
                .foregroundStyle(Color.compressor)
                .frame(minHeight: 44)
                .disabled(isSaving || isTransitioning)
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 4)
    }

    // MARK: Saving

    private func confirm() async {
        guard !isSaving, currentIndex < localItems.count else { return }
        isSaving = true

        var updated = localItems[currentIndex]
        // Quantity is "percent left" (100 = full); an item just confirmed into the fridge starts full.
        updated.quantity = 100

        do {
            let saved = try await ItemService.saveItem(updated)
            await place(saved)
            localItems[currentIndex] = saved
            confirmedItems.append(saved)
            isSaving = false
            await advance()
        } catch {
            isSaving = false
            errorMessage = error.localizedDescription
            showError = true
        }
    }

    /// Paper-feed: the strip ticks (it watches `currentIndex`) while the old sheet content exits,
    /// then the next content rises in. After the last item the sheet exits and the summary appears.
    private func advance() async {
        isTransitioning = true
        defer { isTransitioning = false }
        let exit = reduceMotion ? Motion.reducedFade : Motion.sheetExit
        let enter = reduceMotion ? Motion.reducedFade : Motion.sheetEnter
        let isLast = currentIndex + 1 >= localItems.count

        if !isLast { currentIndex += 1 }
        withAnimation(exit) { sheetPhase = .exiting }
        try? await Task.sleep(for: .seconds(reduceMotion ? 0.15 : 0.18))

        if isLast {
            currentIndex += 1  // summary replaces the screen; no tick, no entrance
            return
        }
        var instant = Transaction(animation: nil)
        instant.disablesAnimations = true
        withTransaction(instant) {
            sheetIndex = currentIndex
            sheetPhase = .below
        }
        withAnimation(enter) { sheetPhase = .resting }
        try? await Task.sleep(for: .seconds(reduceMotion ? 0.15 : 0.4))  // let the spring settle before re-enabling
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

    private struct Section: Identifiable {
        let zone: FridgeZone?  // nil = ungrouped
        let items: [ScannedItem]
        var id: String { zone.map { "\($0)" } ?? "ungrouped" }
    }

    /// nil until the fridge fetch finishes; `failed` means fall back to one ungrouped section.
    @State private var assignments: [String: SlotAssignment]?
    @State private var failed = false
    /// Flipped just after the sections first render, so only on-screen tiles animate in.
    @State private var landed = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let columns = [GridItem(.adaptive(minimum: 76), spacing: 20, alignment: .top)]

    private var pricedTotal: Double { items.compactMap(\.pricePaid).reduce(0, +) }
    private var unpricedCount: Int { items.filter { $0.pricePaid == nil }.count }

    /// Position of each tile across all sections, in the order they appear on screen.
    private var globalIndex: [String: Int] {
        var result: [String: Int] = [:]
        for item in sections.flatMap(\.items) { result[item.documentId] = result.count }
        return result
    }

    private func entrance(for item: ScannedItem?) -> Animation {
        let index = item.flatMap { globalIndex[$0.documentId] } ?? 0
        let delay = min(Double(index) * Motion.tileStagger, Motion.tileStaggerCap)
        return (reduceMotion ? Motion.reducedFade : Motion.tileDrop).delay(delay)
    }

    private var sections: [Section] {
        guard let assignments else { return failed ? [Section(zone: nil, items: items)] : [] }
        let grouped = Dictionary(grouping: items) { assignments[$0.documentId]?.zone }
        var result = FridgeLayout.displayOrder.compactMap { zone in
            grouped[zone].map { Section(zone: zone, items: $0) }
        }
        // Anything the fridge doesn't know about still gets shown.
        if let orphans = grouped[nil] { result.append(Section(zone: nil, items: orphans)) }
        return result
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("\(items.count) item\(items.count == 1 ? "" : "s") added")
                    .font(.everFreshTitle)
                    .tracking(-0.4)

                if items.contains(where: { $0.pricePaid != nil }) {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("Total").font(.everFreshBody).foregroundStyle(Color.shelfSteel)
                            Spacer()
                            Text(pricedTotal.formatted(.currency(code: "USD")))
                                .font(.everFreshStamp.weight(.bold))
                        }
                        if unpricedCount > 0 {
                            Text("\(unpricedCount) item\(unpricedCount == 1 ? " had" : "s had") no price")
                                .font(.footnote)
                                .foregroundStyle(Color.shelfSteel)
                        }
                    }
                }

                ForEach(sections) { section in
                    VStack(alignment: .leading, spacing: 12) {
                        if let zone = section.zone {
                            Text(zone.displayName).everFreshSectionHeader()
                                .opacity(landed ? 1 : 0)
                                .animation(entrance(for: section.items.first), value: landed)
                        }
                        LazyVGrid(columns: Self.columns, spacing: 20) {
                            ForEach(section.items) { item in
                                ItemTile(item: item, size: 72, showsName: true)
                                    .overlay(alignment: .topTrailing) {
                                        DateTape(expiryDate: item.expiryDate, style: .compact)
                                            .offset(x: 12, y: -6)
                                    }
                                    .scaleEffect(landed || reduceMotion ? 1 : 0.96)
                                    .offset(y: landed || reduceMotion ? 0 : -24)
                                    .opacity(landed ? 1 : 0)
                                    .animation(entrance(for: item), value: landed)
                            }
                        }
                    }
                }
            }
            .padding(20)
        }
        .background(Color.enamel)
        .safeAreaInset(edge: .bottom) {
            Button(action: onDone) {
                Text("Put it all away")
                    .font(.system(.body, weight: .semibold))
                    .frame(maxWidth: .infinity, minHeight: 50)
                    .foregroundStyle(.white)
                    .background(Color.freezerUltramarine, in: RoundedRectangle(cornerRadius: 14))
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 8)
            .background(Color.enamel)
        }
        .task {
            do {
                assignments = FridgeLayout.resolve(items: try await ItemService.fetchActiveItems())
            } catch {
                failed = true
            }
            try? await Task.sleep(for: .seconds(0.05))
            landed = true
        }
    }
}

#Preview {
    ReceiptReviewFlow(items: [])
        .environmentObject(AppState())
}
