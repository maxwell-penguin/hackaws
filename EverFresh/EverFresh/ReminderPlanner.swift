import Foundation

struct PlannedReminder: Equatable {
    let id: String
    let fireDate: Date
    let title: String
    let body: String
    let expiryDay: Date
}

/// Pure planning: which local notifications should exist right now. No I/O.
///
/// StrapiDate.date(from:) parses "yyyy-MM-dd" as UTC midnight, so the day is read from its UTC
/// components and rebuilt in `calendar`; that way "Oct 4" is Oct 4 for the user, in any time zone.
func planReminders(
    items: [ScannedItem],
    now: Date,
    calendar: Calendar,
    reminderMinutes: Int,
    limit: Int = 60
) -> [PlannedReminder] {
    var utc = Calendar(identifier: .gregorian)
    utc.timeZone = TimeZone(identifier: "UTC")!

    var byDay: [Date: [String]] = [:]
    for item in items where item.quantity != 0 {
        guard let parsed = StrapiDate.date(from: item.expiryDate) else { continue }
        let c = utc.dateComponents([.year, .month, .day], from: parsed)
        guard let day = calendar.date(from: DateComponents(year: c.year, month: c.month, day: c.day)) else { continue }
        byDay[calendar.startOfDay(for: day), default: []].append(item.name)
    }

    func copy(_ names: [String], _ when: String) -> (title: String, body: String) {
        let sorted = names.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
        if sorted.count == 1 { return ("Expires \(when)", sorted[0]) }
        var body = sorted.prefix(3).joined(separator: ", ")
        if sorted.count > 3 { body += " and \(sorted.count - 3) more" }
        return ("\(sorted.count) items expire \(when)", body)
    }

    let idFormatter = DateFormatter()
    idFormatter.calendar = calendar
    idFormatter.timeZone = calendar.timeZone
    idFormatter.locale = Locale(identifier: "en_US_POSIX")
    idFormatter.dateFormat = "yyyy-MM-dd"

    var planned: [PlannedReminder] = []
    for (day, names) in byDay {
        let dayString = idFormatter.string(from: day)
        let kinds: [(name: String, offset: Int, when: String)] = [("dayBefore", -1, "tomorrow"), ("dayOf", 0, "today")]
        for kind in kinds {
            guard let base = calendar.date(byAdding: .day, value: kind.offset, to: day),
                  let fire = calendar.date(byAdding: .minute, value: reminderMinutes, to: calendar.startOfDay(for: base)),
                  fire.timeIntervalSince(now) >= 5 else { continue }
            let text = copy(names, kind.when)
            planned.append(PlannedReminder(
                id: "everfresh.expiry.\(dayString).\(kind.name)",
                fireDate: fire, title: text.title, body: text.body, expiryDay: day
            ))
        }
    }
    return Array(planned.sorted { ($0.fireDate, $0.id) < ($1.fireDate, $1.id) }.prefix(limit))
}
