import CoreGraphics

/// Named regions inside the fridge template.
enum FridgeZone: CaseIterable, Hashable {
    case topShelf, middleShelf, bottomShelf, crisperDrawer
    case doorBinTop, doorBinMiddle, doorBinBottom, bottleRack

    var displayName: String {
        switch self {
        case .topShelf: return "Top shelf"
        case .middleShelf: return "Middle shelf"
        case .bottomShelf: return "Bottom shelf"
        case .crisperDrawer: return "Crisper drawer"
        case .doorBinTop: return "Door, top bin"
        case .doorBinMiddle: return "Door, middle bin"
        case .doorBinBottom: return "Door, bottom bin"
        case .bottleRack: return "Bottle rack"
        }
    }
}

/// Where one item lives: a zone, a slot in that zone, and the slot's center in logical space.
struct SlotAssignment: Hashable {
    let zone: FridgeZone
    let slotIndex: Int
    let center: CGPoint
}

/// Pure fridge geometry in a fixed 360x640 logical space. Item positions are stored in this
/// space (not screen pixels) so a saved position means the same thing on every device; the
/// views scale it to fit.
enum FridgeLayout {
    static let size = CGSize(width: 360, height: 640)

    /// Icons are 52pt: four across the main compartment leave ~4.8pt gaps (slot width 56.8),
    /// which clears the 4pt minimum, so the 46pt fallback isn't needed.
    static let iconSize: CGFloat = 52

    static let labelStripHeight: CGFloat = 18
    /// How far above a zone's bottom edge the rail (the line items rest on) sits.
    private static let railInset: CGFloat = 14
    private static let bodyInset: CGFloat = 8

    static let displayOrder: [FridgeZone] = [
        .topShelf, .middleShelf, .bottomShelf, .crisperDrawer,
        .doorBinTop, .doorBinMiddle, .doorBinBottom, .bottleRack,
    ]

    static let bodyRect = CGRect(origin: .zero, size: size).insetBy(dx: bodyInset, dy: bodyInset)
    private static let mainWidth = (bodyRect.width * 0.66).rounded()
    /// x of the vertical seam between the main compartment and the door column.
    static let seamX = bodyRect.minX + mainWidth

    private static let shelfHeight = bodyRect.height / 4.4  // 3 shelves + a 1.4x crisper
    private static let binHeight = shelfHeight * 0.85

    static let rects: [FridgeZone: CGRect] = {
        let mainX = bodyRect.minX
        let doorX = seamX
        let doorWidth = bodyRect.maxX - seamX
        let crisperY = bodyRect.minY + shelfHeight * 3
        let rackY = bodyRect.minY + binHeight * 3
        return [
            .topShelf: CGRect(x: mainX, y: bodyRect.minY, width: mainWidth, height: shelfHeight),
            .middleShelf: CGRect(x: mainX, y: bodyRect.minY + shelfHeight, width: mainWidth, height: shelfHeight),
            .bottomShelf: CGRect(x: mainX, y: bodyRect.minY + shelfHeight * 2, width: mainWidth, height: shelfHeight),
            .crisperDrawer: CGRect(x: mainX, y: crisperY, width: mainWidth, height: bodyRect.maxY - crisperY),
            .doorBinTop: CGRect(x: doorX, y: bodyRect.minY, width: doorWidth, height: binHeight),
            .doorBinMiddle: CGRect(x: doorX, y: bodyRect.minY + binHeight, width: doorWidth, height: binHeight),
            .doorBinBottom: CGRect(x: doorX, y: bodyRect.minY + binHeight * 2, width: doorWidth, height: binHeight),
            .bottleRack: CGRect(x: doorX, y: rackY, width: doorWidth, height: bodyRect.maxY - rackY),
        ]
    }()

    static func columns(for zone: FridgeZone) -> Int {
        switch zone {
        case .topShelf, .middleShelf, .bottomShelf, .crisperDrawer: return 4
        case .doorBinTop, .doorBinMiddle, .doorBinBottom, .bottleRack: return 2
        }
    }

    static func rows(for zone: FridgeZone) -> Int {
        switch zone {
        case .crisperDrawer, .bottleRack: return 2
        default: return 1
        }
    }

    /// The y that items in this zone rest on.
    static func railY(for zone: FridgeZone) -> CGFloat {
        rects[zone]!.maxY - railInset
    }

    /// Slot centers, left to right then top to bottom. Single-row zones rest the icon's bottom
    /// edge on the rail; multi-row zones spread rows evenly between the label strip and the rail.
    static func slots(for zone: FridgeZone) -> [CGPoint] { slotTable[zone]! }

    private static let slotTable: [FridgeZone: [CGPoint]] = {
        var table: [FridgeZone: [CGPoint]] = [:]
        for zone in FridgeZone.allCases {
            let rect = rects[zone]!
            let cols = columns(for: zone), rows = rows(for: zone)
            let rail = rect.maxY - railInset
            let top = rect.minY + labelStripHeight
            var points: [CGPoint] = []
            for row in 0..<rows {
                let y: CGFloat
                if rows == 1 {
                    y = rail - iconSize / 2
                } else {
                    let rowHeight = (rail - top) / CGFloat(rows)
                    y = top + rowHeight * (CGFloat(row) + 0.5)
                }
                for col in 0..<cols {
                    points.append(CGPoint(x: rect.minX + rect.width * (CGFloat(col) + 0.5) / CGFloat(cols), y: y))
                }
            }
            table[zone] = points
        }
        return table
    }()

    /// Which zone a point falls in; outside every zone, the nearest one (ties go to displayOrder).
    static func zone(for position: CGPoint) -> FridgeZone {
        for zone in displayOrder where rects[zone]!.contains(position) { return zone }
        return displayOrder.min { distance(rects[$0]!, to: position) < distance(rects[$1]!, to: position) }!
    }

    static func nearestFreeSlot(in zone: FridgeZone, to point: CGPoint, occupied: Set<Int>) -> Int? {
        let free = slots(for: zone).enumerated().filter { !occupied.contains($0.offset) }
        return free.min { hypot($0.element.x - point.x, $0.element.y - point.y) < hypot($1.element.x - point.x, $1.element.y - point.y) }?.offset
    }

    /// Deterministic, total: every item gets an assignment. See the numbered steps inline.
    static func resolve(items: [ScannedItem]) -> [String: SlotAssignment] {
        let ordered = items.sorted { ($0.createdAt, $0.documentId) < ($1.createdAt, $1.documentId) }
        var result: [String: SlotAssignment] = [:]
        var occupied: [FridgeZone: Set<Int>] = [:]

        func claim(_ item: ScannedItem, _ zone: FridgeZone, _ index: Int) {
            occupied[zone, default: []].insert(index)
            result[item.documentId] = SlotAssignment(zone: zone, slotIndex: index, center: slots(for: zone)[index])
        }

        // a/b. Items already sitting exactly on a slot center keep that slot (earlier item wins).
        for item in ordered {
            guard let x = item.positionX, let y = item.positionY else { continue }
            for zone in displayOrder {
                guard let index = slots(for: zone).firstIndex(where: { abs($0.x - x) <= 0.5 && abs($0.y - y) <= 0.5 }) else { continue }
                if !occupied[zone, default: []].contains(index) { claim(item, zone, index) }
                break
            }
        }

        // c/d. Everything else: nearest free slot in its zone, overflowing to the nearest zone with room.
        for item in ordered where result[item.documentId] == nil {
            let point: CGPoint
            let target: FridgeZone
            if let x = item.positionX, let y = item.positionY {
                point = CGPoint(x: x, y: y)
                target = zone(for: point)
            } else {
                target = displayOrder.first { occupied[$0, default: []].count < slots(for: $0).count } ?? displayOrder[0]
                point = slots(for: target)[0]
            }

            let candidates = [target] + displayOrder
                .filter { $0 != target }
                .sorted { distance(rects[$0]!, to: point) < distance(rects[$1]!, to: point) }
            var placed = false
            for zone in candidates {
                if let index = nearestFreeSlot(in: zone, to: point, occupied: occupied[zone, default: []]) {
                    claim(item, zone, index)
                    placed = true
                    break
                }
            }
            if !placed {
                print("[FridgeLayout] Fridge is full; \(item.name) shares a slot in \(target.displayName)")
                claim(item, target, slots(for: target).count - 1)
            }
        }
        return result
    }

    private static func distance(_ rect: CGRect, to point: CGPoint) -> CGFloat {
        let clampedX = min(max(point.x, rect.minX), rect.maxX)
        let clampedY = min(max(point.y, rect.minY), rect.maxY)
        return hypot(point.x - clampedX, point.y - clampedY)
    }
}
