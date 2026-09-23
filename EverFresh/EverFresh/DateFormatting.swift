import Foundation

/// Strapi's date fields (e.g. expiryDate) are plain "yyyy-MM-dd" strings with no time component.
enum StrapiDate {
    static let formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter
    }()

    static func date(from string: String?) -> Date? {
        guard let string else { return nil }
        return formatter.date(from: string)
    }

    static func string(from date: Date) -> String {
        formatter.string(from: date)
    }

    /// Whole days from today until `dateString`'s day. Negative means already past.
    static func daysUntil(_ dateString: String?, from now: Date = Date()) -> Int? {
        guard let target = date(from: dateString) else { return nil }
        let today = Calendar.current.startOfDay(for: now)
        return Calendar.current.dateComponents([.day], from: today, to: target).day
    }

    private static let dateTimeFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let dateTimeFormatterNoFractionalSeconds: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    /// Parses Strapi's createdAt/updatedAt timestamps, which include a time component.
    static func dateTime(from string: String) -> Date? {
        dateTimeFormatter.date(from: string) ?? dateTimeFormatterNoFractionalSeconds.date(from: string)
    }
}
