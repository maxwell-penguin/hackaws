import SwiftUI

/// Read/adjust view for an already-saved Item. Push this onto a NavigationStack from a list.
struct ItemDetailView: View {
    @State private var item: ScannedItem
    @State private var quantity: Double
    @State private var isSaving = false
    @State private var showSaved = false
    @State private var showError = false
    @State private var errorMessage = ""

    init(item: ScannedItem) {
        _item = State(initialValue: item)
        _quantity = State(initialValue: item.quantity)
    }

    private var expiryLabel: String {
        guard let days = StrapiDate.daysUntil(item.expiryDate) else { return item.expiryDate }
        if days < 0 { return "Expired" }
        if days == 0 { return "Expires today" }
        return "\(days) day\(days == 1 ? "" : "s") left"
    }

    private var expiryColor: Color {
        guard let days = StrapiDate.daysUntil(item.expiryDate) else { return .secondary }
        return days < 0 ? .red : .secondary
    }

    private var priceLabel: String {
        item.pricePaid.map { $0.formatted(.currency(code: "USD")) } ?? "—"
    }

    var body: some View {
        Form {
            if let photoUrlString = item.photoUrl, let photoUrl = URL(string: photoUrlString) {
                Section {
                    AsyncImage(url: photoUrl) { image in
                        image.resizable().scaledToFit()
                    } placeholder: {
                        ProgressView()
                    }
                    .frame(maxWidth: .infinity, maxHeight: 200)
                }
            }

            Section("Item") {
                LabeledContent("Name", value: item.name)
                if !item.description.isEmpty {
                    LabeledContent("Description", value: item.description)
                }
                LabeledContent("Category", value: item.category)
            }

            Section("Details") {
                LabeledContent("Expires") {
                    Text(expiryLabel).foregroundStyle(expiryColor)
                }
                LabeledContent("Price Paid", value: priceLabel)
            }

            Section("Quantity") {
                HStack {
                    Text(quantity.formatted(.number.precision(.fractionLength(0...1))))
                        .font(.headline)
                        .monospacedDigit()
                    Spacer()
                    if isSaving {
                        ProgressView()
                            .controlSize(.small)
                    } else if showSaved {
                        Label("Saved", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                            .font(.caption)
                    }
                }
                Slider(value: $quantity, in: 0...10, step: 0.5) { isEditing in
                    guard !isEditing else { return }
                    Task { await updateQuantity() }
                }
            }
        }
        .navigationTitle(item.name)
        .navigationBarTitleDisplayMode(.inline)
        .alert("Couldn't update quantity", isPresented: $showError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage)
        }
    }

    private func updateQuantity() async {
        isSaving = true
        showSaved = false
        defer { isSaving = false }

        do {
            try await ItemService.updateQuantity(documentId: item.documentId, quantity: quantity)
            item.quantity = quantity
            showSaved = true
            try? await Task.sleep(for: .seconds(1.5))
            showSaved = false
        } catch {
            quantity = item.quantity
            errorMessage = error.localizedDescription
            showError = true
        }
    }
}

#Preview {
    NavigationStack {
        ItemDetailView(item: ScannedItem(
            documentId: "abc123",
            numericId: 1,
            name: "Avocado",
            description: "A ripe Hass avocado.",
            category: "produce",
            expiryDate: "2026-09-20",
            photoUrl: nil,
            source: "manual-scan",
            status: "active",
            quantity: 2,
            pricePaid: 1.5
        ))
    }
}
