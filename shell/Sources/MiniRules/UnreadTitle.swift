import Foundation

public struct UnreadTitle: Equatable, Sendable {
    public let count: Int?
    public let title: String

    public init(count: Int?, title: String) {
        self.count = count
        self.title = title
    }

    public var showsBadge: Bool { count != 0 }

    public static func badgeLabel(count: Int) -> String {
        count > 99 ? "99+" : String(count)
    }

    public static func parse(_ title: String, allowsCountBeforeSeparator: Bool = false) -> UnreadTitle? {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if let match = trimmed.wholeMatch(of: #/\((\d{1,5})\)\s+(\S.*)/#) {
            return UnreadTitle(count: Int(match.1), title: String(match.2))
        }
        if let match = trimmed.wholeMatch(of: #/\[(\d{1,5})\]\s+(\S.*)/#) {
            return UnreadTitle(count: Int(match.1), title: String(match.2))
        }
        if let match = trimmed.wholeMatch(of: #/(\d{1,5}) unread(?: messages?| notifications?)?(?:\s*[-|:\u{00B7}\u{2022}\u{2013}\u{2014}]\s*|\s+|$)(.*)/#.ignoresCase()) {
            return UnreadTitle(count: Int(match.1), title: String(match.2))
        }
        if let match = trimmed.wholeMatch(of: #/(?:\u{2022}\s*|\*\s+)(\S.*)/#) {
            return UnreadTitle(count: nil, title: String(match.1))
        }
        if let match = trimmed.wholeMatch(of: #/(.*\S)\s+\((\d{1,5})\)/#), let count = Int(match.2), !looksLikeYear(match.2) {
            return UnreadTitle(count: count, title: String(match.1))
        }
        if allowsCountBeforeSeparator,
           let match = trimmed.wholeMatch(of: #/(.*?\S)\s+\((\d{1,5})\)(\s+[-|\u{00B7}\u{2013}\u{2014}]\s+.*)/#), let count = Int(match.2), !looksLikeYear(match.2) {
            return UnreadTitle(count: count, title: String(match.1) + String(match.3))
        }
        return nil
    }

    private static func looksLikeYear(_ digits: Substring) -> Bool {
        guard digits.count == 4, let value = Int(digits) else { return false }
        return (1900...2099).contains(value)
    }

    private static let messagingHosts = ["mail.google.com", "messages.google.com", "outlook.live.com", "outlook.office.com", "outlook.office365.com", "slack.com", "discord.com", "linear.app"]

    public static func isMessagingSite(host: String, path: String) -> Bool {
        let host = host.lowercased()
        if host == "github.com" { return path == "/notifications" || path.hasPrefix("/notifications/") }
        return messagingHosts.contains { host == $0 || host.hasSuffix("." + $0) }
    }
}

public struct UnreadBadgeTracker: Sendable {
    public private(set) var current: UnreadTitle?
    private var site: String?
    private var previousTitle: String?
    private var previousParse: UnreadTitle?
    private var hasSeenCountChange = false

    public init() {}

    public mutating func update(title: String, host: String?, path: String) -> UnreadTitle? {
        if host != site {
            site = host
            previousTitle = nil
            previousParse = nil
            hasSeenCountChange = false
        }
        let isMessagingSite = host.map { UnreadTitle.isMessagingSite(host: $0, path: path) } ?? false
        let parsed = UnreadTitle.parse(title, allowsCountBeforeSeparator: isMessagingSite)
        if let previousTitle, previousTitle != title, Self.isCountChange(from: previousTitle, previousParse, to: title, parsed) {
            hasSeenCountChange = true
        }
        previousTitle = title
        previousParse = parsed
        current = isMessagingSite || hasSeenCountChange ? parsed : nil
        return current
    }

    private static func isCountChange(from oldTitle: String, _ oldParse: UnreadTitle?, to newTitle: String, _ newParse: UnreadTitle?) -> Bool {
        switch (oldParse, newParse) {
        case let (old?, new?): old.title == new.title && old.count != new.count
        case let (old?, nil): old.title == newTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        case let (nil, new?): new.title == oldTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        case (nil, nil): false
        }
    }
}
