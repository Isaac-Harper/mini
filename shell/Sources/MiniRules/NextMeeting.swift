import Foundation

public struct MeetingEvent: Equatable, Sendable {
    public let identifier: String
    public let title: String
    public let calendarIdentifier: String
    public let calendarTitle: String
    public let start: Date
    public let end: Date
    public let isAllDay: Bool
    public let isDeclined: Bool
    public let conferenceLink: URL?

    public init(identifier: String, title: String, calendarIdentifier: String, calendarTitle: String, start: Date, end: Date,
                isAllDay: Bool, isDeclined: Bool, conferenceLink: URL?) {
        self.identifier = identifier
        self.title = title
        self.calendarIdentifier = calendarIdentifier
        self.calendarTitle = calendarTitle
        self.start = start
        self.end = end
        self.isAllDay = isAllDay
        self.isDeclined = isDeclined
        self.conferenceLink = conferenceLink
    }

    public func isOngoing(at now: Date) -> Bool {
        start <= now && now < end
    }
}

public enum NextMeeting {
    public static let lookahead: TimeInterval = 60 * 60
    public static let emphasisLead: TimeInterval = 5 * 60
    public static let startingGrace: TimeInterval = 5 * 60

    public static func select(_ events: [MeetingEvent], now: Date) -> MeetingEvent? {
        events
            .filter { isCandidate($0) && $0.end > now && $0.start <= now.addingTimeInterval(lookahead) }
            .min { first, second in
                let firstOngoing = first.isOngoing(at: now)
                let secondOngoing = second.isOngoing(at: now)
                if firstOngoing != secondOngoing { return firstOngoing }
                if first.start != second.start { return first.start < second.start }
                return first.end < second.end
            }
    }

    public static func nextChange(_ events: [MeetingEvent], now: Date) -> Date? {
        events
            .filter(isCandidate)
            .flatMap { [$0.start.addingTimeInterval(-lookahead), $0.start, $0.end] }
            .filter { $0 > now }
            .min()
    }

    public static func timeText(for event: MeetingEvent, now: Date) -> String {
        if now < event.start {
            return "in \(duration(minutes: wholeMinutes(until: event.start, from: now)))"
        }
        if now.timeIntervalSince(event.start) < startingGrace {
            return "now"
        }
        return "ends in \(duration(minutes: wholeMinutes(until: event.end, from: now)))"
    }

    public static func isEmphasized(_ event: MeetingEvent, now: Date) -> Bool {
        now >= event.start.addingTimeInterval(-emphasisLead) && now < event.end
    }

    public static func duration(minutes: Int) -> String {
        if minutes < 60 { return "\(minutes) min" }
        let hours = minutes / 60
        let remainder = minutes % 60
        return remainder == 0 ? "\(hours) h" : "\(hours) h \(remainder) min"
    }

    public static func conferenceLink(url: String?, location: String?, notes: String?) -> URL? {
        for text in [url, location, notes] {
            guard let text, let link = firstConferenceLink(in: text) else { continue }
            return link
        }
        return nil
    }

    private static func isCandidate(_ event: MeetingEvent) -> Bool {
        !event.isAllDay && !event.isDeclined
    }

    private static func wholeMinutes(until date: Date, from now: Date) -> Int {
        max(1, Int((date.timeIntervalSince(now) / 60).rounded(.up)))
    }

    private static var linkPattern: Regex<Substring> { /(?i)(?:https?:\/\/)?(?:[a-z0-9-]+\.)+[a-z]{2,}(?::\d+)?\/[^\s<>"'\[\]{}|\\^`]*/ }
    private static let trailingPunctuation = CharacterSet(charactersIn: ".,;:!?)*")
    private static var meetCode: Regex<Substring> { /\/[a-z]{3}-[a-z]{4}-[a-z]{3}\/?/ }
    private static let redirectParameters: Set<String> = ["q", "url", "u", "target"]

    private static func firstConferenceLink(in text: String) -> URL? {
        for match in text.matches(of: linkPattern) {
            let token = String(match.output).trimmingCharacters(in: trailingPunctuation)
            if let link = conferenceURL(token) { return link }
        }
        return nil
    }

    private static func conferenceURL(_ token: String) -> URL? {
        let hasScheme = token.lowercased().hasPrefix("http://") || token.lowercased().hasPrefix("https://")
        guard let url = URL(string: hasScheme ? token : "https://\(token)"),
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        else { return nil }
        if isConference(components) { return url }
        for item in components.queryItems ?? [] where redirectParameters.contains(item.name.lowercased()) {
            if let value = item.value, let link = firstConferenceLink(in: value) { return link }
        }
        return nil
    }

    private static func isConference(_ components: URLComponents) -> Bool {
        guard let host = components.host?.lowercased() else { return false }
        let path = components.path
        let lowercasedPath = path.lowercased()
        func isHost(_ domain: String) -> Bool { host == domain || host.hasSuffix(".\(domain)") }
        if host == "meet.google.com" {
            return path.wholeMatch(of: meetCode) != nil || lowercasedPath.hasPrefix("/lookup/")
        }
        if isHost("zoom.us") || isHost("zoomgov.com") {
            return ["/j/", "/my/", "/w/", "/s/"].contains { lowercasedPath.hasPrefix($0) }
        }
        if host == "teams.microsoft.com" {
            return lowercasedPath.hasPrefix("/l/meetup-join/") || lowercasedPath.hasPrefix("/meet/")
        }
        if host == "teams.live.com" {
            return lowercasedPath.hasPrefix("/meet/")
        }
        if isHost("webex.com") {
            return lowercasedPath.count > 1
        }
        if isHost("around.co") {
            return lowercasedPath.count > 1
        }
        return false
    }
}
