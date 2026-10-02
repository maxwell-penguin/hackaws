import SwiftUI

/// Walks the user through confirming a batch of receipt-scanned items one at a time, then shows
/// a summary grid. Each item was already created as a draft in Strapi by the receipt scan — this
/// flow only edits/confirms them, so leaving early (swipe-to-dismiss) never loses anything that
/// was already confirmed; it just means later items keep their unedited draft values.
struct ReceiptReviewFlow: View {
    let items: [ScannedItem]

    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var currentIndex = 0
    @State private var confirmedItems: [ScannedItem] = []

    private static let cardTransition: AnyTransition = .asymmetric(
        insertion: .move(edge: .trailing).combined(with: .opacity),
        removal: .move(edge: .leading).combined(with: .opacity)
    )

    var body: some View {
        NavigationStack {
            Group {
                if currentIndex < items.count {
                    ReceiptItemCardView(
                        item: items[currentIndex],
                        isLast: currentIndex == items.count - 1,
                        onConfirmed: { updated in
                            confirmedItems.append(updated)
                            withAnimation(.easeInOut(duration: 0.3)) {
                                currentIndex += 1
                            }
                        }
                    )
                    .id(items[currentIndex].documentId)
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
        }
    }

    private var navigationTitle: String {
        if currentIndex < items.count {
            return "Item \(currentIndex + 1) of \(items.count)"
        }
        return "\(confirmedItems.count) Item\(confirmedItems.count == 1 ? "" : "s") Added"
    }
}

private struct ReceiptItemCardView: View {
    let item: ScannedItem
    let isLast: Bool
    let onConfirmed: (ScannedItem) -> Void

    @State private var name: String
    @State private var description: String
    @State private var category: String
    @State private var expiryDate: Date
    @State private var priceText: String
    @State private var isSaving = false
    @State private var showError = false
    @State private var errorMessage = ""

    init(item: ScannedItem, isLast: Bool, onConfirmed: @escaping (ScannedItem) -> Void) {
        self.item = item
        self.isLast = isLast
        self.onConfirmed = onConfirmed
        _name = State(initialValue: item.name)
        _description = State(initialValue: item.description ?? "")
        _category = State(initialValue: item.category ?? "")
        _expiryDate = State(initialValue: StrapiDate.date(from: item.expiryDate) ?? Date())
        // Unlike a fresh single-item scan, a receipt line item often already has a parsed price.
        _priceText = State(initialValue: item.pricePaid.map { String(format: "%.2f", $0) } ?? "")
    }

    var body: some View {
        VStack(spacing: 0) {
            Form {
                ItemEditFormFields(
                    photoUrl: item.photoUrl,
                    name: $name,
                    description: $description,
                    category: $category,
                    expiryDate: $expiryDate,
                    priceText: $priceText
                )
            }
            .scrollContentBackground(.hidden)

            Button {
                Task { await confirm() }
            } label: {
                Text(isLast ? "Finish" : "Confirm & Next")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .padding()
            .disabled(isSaving || name.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        .disabled(isSaving)
        .overlay {
            if isSaving {
                ProgressView()
            }
        }
        .alert("Couldn't save item", isPresented: $showError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage)
        }
    }

    private func confirm() async {
        isSaving = true
        defer { isSaving = false }

        var updated = item
        updated.name = name
        updated.description = description
        updated.category = category
        updated.expiryDate = StrapiDate.string(from: expiryDate)
        updated.pricePaid = Double(priceText)
        // Quantity is "percent left" (100 = full); an item just confirmed into the fridge starts full.
        updated.quantity = 100

        do {
            onConfirmed(try await ItemService.saveItem(updated))
        } catch {
            errorMessage = error.localizedDescription
            showError = true
        }
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
