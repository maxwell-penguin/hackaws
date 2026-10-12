import Foundation

struct WastedLine {
    let item: ScannedItem
    let value: Double
    let resolvedDate: Date
}

struct MonthSummary {
    var wastedValue = 0.0
    var wastedCount = 0
    var usedValue = 0.0
    var usedCount = 0
    var unpricedWastedCount = 0
    /// Every wasted item; value descending (unpriced ones last, value 0), then earliest resolved first.
    var wastedLines: [WastedLine] = []
    /// Up to 3, by value descending; zero-value categories omitted.
    var topWastedCategories: [(name: String, value: Double)] = []
    /// wastedValue / (wastedValue + usedValue); nil when there's no value at all.
    var wasteRate: Double? {
        let total = wastedValue + usedValue
        return total > 0 ? wastedValue / total : nil
    }
}

/// Only "wasted"/"consumed" items count. Resolution date is resolvedAt, falling back to updatedAt
/// (older consumed items have no resolvedAt); an item with neither parseable is skipped.
private func resolution(of item: ScannedItem) -> (wasted: Bool, date: Date)? {
    guard item.status == "wasted" || item.status == "consumed" else { return nil }
    let date = item.resolvedAt.flatMap(StrapiDate.dateTime(from:)) ?? item.updatedAt.flatMap(StrapiDate.dateTime(from:))
    guard let date else { return nil }
    return (item.status == "wasted", date)
}

func summarize(items: [ScannedItem], month: Date, calendar: Calendar = .current) -> MonthSummary {
    var summary = MonthSummary()
    var categoryValues: [String: Double] = [:]

    for item in items {
        guard let r = resolution(of: item),
              calendar.isDate(r.date, equalTo: month, toGranularity: .month) else { continue }
        let price = (item.pricePaid ?? 0) > 0 ? item.pricePaid : nil

        if r.wasted {
            summary.wastedCount += 1
            guard let price else {
                // No value, but still listed (shown with a dash) so every thrown-out item is visible.
                summary.unpricedWastedCount += 1
                summary.wastedLines.append(WastedLine(item: item, value: 0, resolvedDate: r.date))
                continue
            }
            let value = price * min(max(item.quantity ?? 100, 0), 100) / 100
            summary.wastedValue += value
            summary.wastedLines.append(WastedLine(item: item, value: value, resolvedDate: r.date))
            categoryValues[item.category ?? "Uncategorized", default: 0] += value
        } else {
            summary.usedCount += 1
            summary.usedValue += price ?? 0
        }
    }

    summary.wastedLines.sort { ($1.value, $0.resolvedDate) < ($0.value, $1.resolvedDate) }
    summary.topWastedCategories = categoryValues
        .filter { $0.value > 0 }
        .sorted { ($1.value, $0.key) < ($0.value, $1.key) }
        .prefix(3)
        .map { (name: $0.key, value: $0.value) }
    return summary
}

/// Start of the earliest month with any counted activity.
func earliestActivityMonth(items: [ScannedItem], calendar: Calendar = .current) -> Date? {
    items.compactMap { resolution(of: $0)?.date }.min()
        .flatMap { calendar.date(from: calendar.dateComponents([.year, .month], from: $0)) }
}
