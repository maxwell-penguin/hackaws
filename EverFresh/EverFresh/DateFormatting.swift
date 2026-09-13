import Foundation

/// Strapi's date fields (e.g. expiryDate) are plain "yyyy-MM-dd" strings with no time component.
enum StrapiDate {
    static let formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter
    }()

    static func date(from string: String) -> Date? {
        formatter.date(from: string)
    }

    static func string(from date: Date) -> String {
        formatter.string(from: date)
    }

    /// Whole days from today until `dateString`'s day. Negative means already past.
    static func daysUntil(_ dateString: String, from now: Date = Date()) -> Int? {
        guard let target = date(from: dateString) else { return nil }
        let today = Calendar.current.startOfDay(for: now)
        return Calendar.current.dateComponents([.day], from: today, to: target).day
    }
}
