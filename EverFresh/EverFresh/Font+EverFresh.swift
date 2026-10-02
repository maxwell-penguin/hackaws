import SwiftUI

extension Font {
    /// Screen titles. Pair with `.tracking(-0.4)` where set on Text (Font can't carry tracking).
    static let everFreshTitle = Font.system(.largeTitle, weight: .heavy)
    /// Item names in rows and cards — same voice as the title, row-sized.
    static let everFreshItemName = Font.system(.headline, weight: .heavy)
    static let everFreshBody = Font.system(.body, weight: .regular)
    /// Dates, prices, percentages.
    static let everFreshStamp = Font.system(.footnote, design: .monospaced, weight: .medium)
    static let everFreshSectionHeader = Font.system(size: 15, weight: .semibold)
}

extension View {
    /// Section headers: Semibold 15pt ShelfSteel, sentence case as written.
    func everFreshSectionHeader() -> some View {
        font(.everFreshSectionHeader)
            .foregroundStyle(Color.shelfSteel)
            .textCase(nil)
    }
}
