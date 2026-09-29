import SwiftUI

/// Stub for the receipt review flow — just lists what was parsed off the receipt for now.
/// Sequential per-item confirmation (mirroring ItemConfirmationView) is a follow-up step.
struct ReceiptReviewFlow: View {
    let items: [ScannedItem]

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List(items) { item in
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.name)
                        .font(.headline)
                    if let category = item.category {
                        Text(category)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("\(items.count) Item\(items.count == 1 ? "" : "s") Found")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

#Preview {
    ReceiptReviewFlow(items: [])
}
