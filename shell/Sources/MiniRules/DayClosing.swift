import Foundation

public enum DayClosing {
    public static let boundaryHour = 4

    public struct Candidate<Identifier: Hashable> {
        public let identifier: Identifier
        public let lastSelectedAt: Date
        public let isKept: Bool
        public let children: [Candidate]

        public init(identifier: Identifier, lastSelectedAt: Date, isKept: Bool, children: [Candidate]) {
            self.identifier = identifier
            self.lastSelectedAt = lastSelectedAt
            self.isKept = isKept
            self.children = children
        }

        fileprivate func qualifies(before cutoff: Date) -> Bool {
            !isKept && lastSelectedAt < cutoff && children.allSatisfy { $0.qualifies(before: cutoff) }
        }
    }

    public static func day(containing date: Date, calendar: Calendar) -> Date {
        let midnight = calendar.startOfDay(for: date)
        guard calendar.component(.hour, from: date) < boundaryHour else { return midnight }
        guard let previous = calendar.date(byAdding: .day, value: -1, to: midnight) else { preconditionFailure("Calendar cannot step back from \(date)") }
        return previous
    }

    public static func start(ofDay day: Date, calendar: Calendar) -> Date {
        guard let start = calendar.date(bySettingHour: boundaryHour, minute: 0, second: 0, of: day) else { preconditionFailure("Calendar cannot set the hour of \(day)") }
        return start
    }

    public static func isNewDay(at now: Date, lastClosedDay: Date?, calendar: Calendar) -> Bool {
        guard let lastClosedDay else { return true }
        return day(containing: now, calendar: calendar) > lastClosedDay
    }

    public static func previousActiveDay(before now: Date, selections: [Date], calendar: Calendar) -> Date? {
        let todayStart = start(ofDay: day(containing: now, calendar: calendar), calendar: calendar)
        return selections.filter { $0 < todayStart }.max().map { day(containing: $0, calendar: calendar) }
    }

    public static func rootsToFold<Identifier>(_ roots: [Candidate<Identifier>], selectedBefore cutoff: Date) -> [Identifier] {
        roots.filter { $0.qualifies(before: cutoff) }.map(\.identifier)
    }

    public static func label(forDay day: Date, now: Date, calendar: Calendar, locale: Locale) -> String {
        let today = self.day(containing: now, calendar: calendar)
        guard let age = calendar.dateComponents([.day], from: day, to: today).day else { preconditionFailure("Calendar gave no day count") }
        var style = Date.FormatStyle(locale: locale, calendar: calendar, timeZone: calendar.timeZone)
        style = age < 7 ? style.weekday(.wide) : style.month(.abbreviated).day()
        return day.formatted(style)
    }

    public static func groupTitle(label: String, tabCount: Int) -> String {
        "\(label) \u{00B7} \(tabCount == 1 ? "1 tab" : "\(tabCount) tabs")"
    }

    public static func foldMessage(label: String, tabCount: Int) -> String {
        "Folded \(tabCount == 1 ? "1 tab" : "\(tabCount) tabs") from \(label)"
    }

    public static func isExpired(foldedAt: Date, now: Date, window: TimeInterval) -> Bool {
        now.timeIntervalSince(foldedAt) >= window
    }
}
