import SwiftUI

/// Read/adjust view for an already-saved Item. Push this onto a NavigationStack from a list.
struct ItemDetailView: View {
    @State private var item: ScannedItem
    @State private var quantity: Double
    @State private var isSaving = false
    @State private var showSaved = false
    @State private var showError = false
    @State private var errorMessage = ""
    @State private var showEdit = false
    @State private var showDeleteConfirm = false
    @State private var showDeleteError = false
    @Environment(\.dismiss) private var dismiss

    init(item: ScannedItem) {
        _item = State(initialValue: item)
        _quantity = State(initialValue: item.quantity ?? 0)
    }

    private var expiryLabel: String {
        guard let days = StrapiDate.daysUntil(item.expiryDate) else { return item.expiryDate ?? "Unknown" }
        if days < 0 { return "Expired" }
        if days == 0 { return "Expires today" }
        return "\(days) day\(days == 1 ? "" : "s") left"
    }

    private var expiryColor: Color {
        guard let days = StrapiDate.daysUntil(item.expiryDate) else { return .shelfSteel }
        return ExpiryBadge.urgencyColor(daysLeft: days) ?? .compressor
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

            Section {
                LabeledContent("Name") {
                    Text(item.name).font(.everFreshItemName).tracking(-0.2)
                }
                if let description = item.description, !description.isEmpty {
                    LabeledContent("Description", value: description)
                }
                LabeledContent("Category", value: item.category ?? "Uncategorized")
            } header: {
                Text("Item").everFreshSectionHeader()
            }
            .listRowBackground(Color.frost)

            Section {
                LabeledContent("Expires") {
                    Text(expiryLabel).font(.everFreshStamp).foregroundStyle(expiryColor)
                }
                LabeledContent("Price Paid") {
                    Text(priceLabel).font(.everFreshStamp)
                }
            } header: {
                Text("Details").everFreshSectionHeader()
            }
            .listRowBackground(Color.frost)

            Section {
                HStack {
                    Text("\(Int(quantity))% left")
                        .font(.everFreshStamp)
                    Spacer()
                    if isSaving {
                        ProgressView()
                            .controlSize(.small)
                    } else if showSaved {
                        Label("Saved", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(Color.freezerUltramarine)
                            .font(.everFreshBody)
                    }
                }
                Slider(value: $quantity, in: 0...100, step: 5) { isEditing in
                    guard !isEditing else { return }
                    Task { await updateQuantity() }
                }
            } header: {
                Text("Quantity").everFreshSectionHeader()
            }
            .listRowBackground(Color.frost)

            Section {
                Button("Delete Item", role: .destructive) { showDeleteConfirm = true }
                    .foregroundStyle(Color.useByRed)
                    .frame(maxWidth: .infinity)
            }
            .listRowBackground(Color.frost)
        }
        .scrollContentBackground(.hidden)
        .background(Color.enamel)
        .navigationTitle(item.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Edit") { showEdit = true }
            }
        }
        .sheet(isPresented: $showEdit) {
            ItemEditSheet(item: item) { item = $0 }
        }
        .confirmationDialog("Delete this item?", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
            Button("Delete Item", role: .destructive) { Task { await delete() } }
        } message: {
            Text("This can't be undone.")
        }
        .alert("Couldn't update quantity", isPresented: $showError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage)
        }
        .alert("Couldn't delete item", isPresented: $showDeleteError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage)
        }
    }

    private func delete() async {
        do {
            try await ItemService.deleteItem(documentId: item.documentId)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
            showDeleteError = true
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
            quantity = item.quantity ?? 0
            errorMessage = error.localizedDescription
            showError = true
        }
    }
}

/// Edit sheet for ItemDetailView: ItemEditFormFields plus Cancel/Save chrome.
private struct ItemEditSheet: View {
    @Environment(\.dismiss) private var dismiss

    let original: ScannedItem
    let onSaved: (ScannedItem) -> Void

    @State private var name: String
    @State private var description: String
    @State private var category: String
    @State private var expiryDate: Date
    @State private var priceText: String
    @State private var isSaving = false
    @State private var showError = false
    @State private var errorMessage = ""

    init(item: ScannedItem, onSaved: @escaping (ScannedItem) -> Void) {
        original = item
        self.onSaved = onSaved
        _name = State(initialValue: item.name)
        _description = State(initialValue: item.description ?? "")
        _category = State(initialValue: item.category ?? "")
        _expiryDate = State(initialValue: StrapiDate.date(from: item.expiryDate) ?? Date())
        _priceText = State(initialValue: item.pricePaid.map { String($0) } ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                ItemEditFormFields(
                    photoUrl: original.photoUrl,
                    name: $name,
                    description: $description,
                    category: $category,
                    expiryDate: $expiryDate,
                    priceText: $priceText
                )
            }
            .scrollContentBackground(.hidden)
            .background(Color.enamel)
            .navigationTitle("Edit Item")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { Task { await save() } }
                        .disabled(isSaving || name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .disabled(isSaving)
            .alert("Couldn't save item", isPresented: $showError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage)
            }
        }
    }

    private func save() async {
        isSaving = true
        defer { isSaving = false }

        var updated = original
        updated.name = name
        updated.description = description
        updated.category = category
        updated.expiryDate = StrapiDate.string(from: expiryDate)
        updated.pricePaid = Double(priceText)

        do {
            onSaved(try await ItemService.saveItem(updated))
            dismiss()
        } catch {
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
            quantity: 75,
            pricePaid: 1.5,
            createdAt: "2026-09-13T10:15:30.000Z"
        ))
    }
}
