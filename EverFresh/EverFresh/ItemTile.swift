import SwiftUI

/// A square item tile: the photo when there is one, otherwise a Frost symbol tile (with the
/// name inside it only when `showsName`). Corner radius scales with `size` so a tile is the
/// same shape at any size (10pt at FridgeLayout.iconSize).
struct ItemTile: View {
    let item: ScannedItem
    let size: CGFloat
    let showsName: Bool

    private var cornerRadius: CGFloat { 10 * size / FridgeLayout.iconSize }

    private var placeholder: some View {
        ZStack {
            Color.frost
            VStack(spacing: 2) {
                Image(systemName: CategoryIcons.symbol(for: item.category ?? "other"))
                    .font(.system(size: size * 0.4))
                    .foregroundStyle(Color.compressor)
                if showsName {
                    Text(item.name)
                        .font(.caption2)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .foregroundStyle(Color.compressor)
                }
            }
            .padding(.horizontal, 3)
            RoundedRectangle(cornerRadius: cornerRadius).strokeBorder(Color.shelfSteel, lineWidth: 1)
        }
    }

    @ViewBuilder
    private var face: some View {
        if let urlString = item.photoUrl, let url = URL(string: urlString) {
            AsyncImage(url: url) { phase in
                if let image = phase.image {
                    image.resizable().scaledToFill()
                } else {
                    placeholder
                }
            }
        } else {
            placeholder
        }
    }

    var body: some View {
        face
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
            .shadow(color: .black.opacity(0.18), radius: 1.5, y: 2)
    }
}
