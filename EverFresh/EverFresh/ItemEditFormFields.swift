import SwiftUI

/// The editable Item fields shared by ItemConfirmationView and ReceiptReviewFlow's per-item
/// cards. Expects to be placed inside a `Form { ... }` — it returns raw `Section`s, not its
/// own Form, so each caller keeps control of the surrounding toolbar/chrome.
struct ItemEditFormFields: View {
    let photoUrl: String?
    @Binding var name: String
    @Binding var description: String
    @Binding var category: String
    @Binding var expiryDate: Date
    @Binding var priceText: String

    var body: some View {
        Group {
            if let photoUrlString = photoUrl, let photoUrl = URL(string: photoUrlString) {
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
                TextField("Name", text: $name)
                    .font(.everFreshItemName)
                TextField("Description", text: $description, axis: .vertical)
                TextField("Category", text: $category)
            } header: {
                Text("Item").everFreshSectionHeader()
            }
            .listRowBackground(Color.frost)
            Section {
                DatePicker("Expires", selection: $expiryDate, displayedComponents: .date)
                HStack {
                    Text("Price Paid")
                    Spacer()
                    TextField("0.00", text: $priceText)
                        .font(.everFreshStamp)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                }
            } header: {
                Text("Details").everFreshSectionHeader()
            }
            .listRowBackground(Color.frost)
        }
    }
}
