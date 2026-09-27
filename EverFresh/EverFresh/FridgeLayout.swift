import CoreGraphics

/// Named regions inside the default two-door fridge template.
enum FridgeZone: CaseIterable {
    case topShelf, middleShelf, bottomShelf, leftDoorBin, rightDoorBin, crisperDrawer
}

/// A fixed logical coordinate space representing one default fridge layout. Item positions
/// are stored in this space (not raw screen pixels) so a saved position stays consistent
/// across different device sizes — FridgeCanvasView scales this space to fit whatever screen
/// it's actually shown on.
enum FridgeLayout {
    static let size = CGSize(width: 320, height: 600)

    private static let doorBinWidth: CGFloat = 50
    private static let drawerHeight: CGFloat = 140
    private static let shelvesHeight = size.height - drawerHeight
    private static let shelfHeight = shelvesHeight / 3
    private static let mainX = doorBinWidth
    private static let mainWidth = size.width - doorBinWidth * 2

    static let rects: [FridgeZone: CGRect] = [
        .topShelf: CGRect(x: mainX, y: 0, width: mainWidth, height: shelfHeight),
        .middleShelf: CGRect(x: mainX, y: shelfHeight, width: mainWidth, height: shelfHeight),
        .bottomShelf: CGRect(x: mainX, y: shelfHeight * 2, width: mainWidth, height: shelfHeight),
        .leftDoorBin: CGRect(x: 0, y: 0, width: doorBinWidth, height: shelvesHeight),
        .rightDoorBin: CGRect(x: size.width - doorBinWidth, y: 0, width: doorBinWidth, height: shelvesHeight),
        .crisperDrawer: CGRect(x: 0, y: shelvesHeight, width: size.width, height: drawerHeight),
    ]

    /// Which zone a point falls in. If it's outside every zone (e.g. dragged past an edge),
    /// returns the nearest one instead, so a position is never "zoneless".
    static func zone(for position: CGPoint) -> FridgeZone {
        for (zone, rect) in rects where rect.contains(position) {
            return zone
        }
        return rects.min { distance($0.value, to: position) < distance($1.value, to: position) }!.key
    }

    private static func distance(_ rect: CGRect, to point: CGPoint) -> CGFloat {
        let clampedX = min(max(point.x, rect.minX), rect.maxX)
        let clampedY = min(max(point.y, rect.minY), rect.maxY)
        return hypot(point.x - clampedX, point.y - clampedY)
    }
}
