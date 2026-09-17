import SwiftUI

struct ItemConfirmationView: View {
    @Environment(\.dismiss) private var dismiss

    private let original: ScannedItem

    @State private var name: String
    @State private var description: String
    @State private var category: String
    @State private var expiryDate: Date
    @State private var priceText: String = ""
    @State private var isSaving = false
    @State private var showError = false
    @State private var errorMessage = ""

    init(item: ScannedItem) {
        self.original = item
        _name = State(initialValue: item.name)
        _description = State(initialValue: item.description ?? "")
        _category = State(initialValue: item.category ?? "")
        _expiryDate = State(initialValue: StrapiDate.date(from: item.expiryDate) ?? Date())
    }

    var body: some View {
        NavigationStack {
            Form {
                if let photoUrlString = original.photoUrl, let photoUrl = URL(string: photoUrlString) {
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
                    TextField("Name", text: $name)
                    TextField("Description", text: $description, axis: .vertical)
                    TextField("Category", text: $category)
                }
                Section("Details") {
                    DatePicker("Expires", selection: $expiryDate, displayedComponents: .date)
                    HStack {
                        Text("Price Paid")
                        Spacer()
                        TextField("0.00", text: $priceText)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                    }
                }
            }
            .navigationTitle("Confirm Item")
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
            try await ItemService.saveItem(updated)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
            showError = true
        }
    }
}

#Preview {
    ItemConfirmationView(item: ScannedItem(
        documentId: "abc123",
        numericId: 1,
        name: "Avocado",
        description: "A ripe Hass avocado.",
        category: "produce",
        expiryDate: "2026-09-20",
        photoUrl: nil,
        source: "manual-scan",
        status: "active",
        quantity: 1,
        pricePaid: 0,
        createdAt: "2026-09-13T10:15:30.000Z"
    ))
}
