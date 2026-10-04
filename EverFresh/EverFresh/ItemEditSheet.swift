import SwiftUI

/// Edit sheet shared by ItemDetailView and ReceiptReviewFlow: ItemEditFormFields plus Cancel/Save chrome.
struct ItemEditSheet: View {
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
