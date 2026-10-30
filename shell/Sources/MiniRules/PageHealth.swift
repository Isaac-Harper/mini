import Foundation

public struct FailedRequest: Equatable, Sendable {
    public let status: Int
    public let url: String

    public init(status: Int, url: String) {
        self.status = status
        self.url = url
    }
}

public struct PageHealth: Equatable, Sendable {
    public static let messageLimit = 80
    public static let pathLimit = 48

    public private(set) var errorCount = 0
    public private(set) var firstError: String?
    public private(set) var failedRequestCount = 0
    public private(set) var firstFailedRequest: FailedRequest?

    public init() {}

    public static func isCollected(for url: String) -> Bool {
        if LocalDevelopment.port(ofLocalAddress: url) != nil { return true }
        guard let components = URLComponents(string: url), let scheme = components.scheme?.lowercased(), ["http", "https"].contains(scheme),
              let host = components.host else { return false }
        return PreviewDeployment.of(host: host) != nil
    }

    public var hasProblems: Bool {
        errorCount > 0 || failedRequestCount > 0
    }

    public mutating func recordErrors(_ count: Int, firstMessage: String) {
        guard count > 0 else { return }
        errorCount += count
        if firstError == nil { firstError = firstMessage }
    }

    public mutating func recordFailedRequest(_ request: FailedRequest) {
        failedRequestCount += 1
        if firstFailedRequest == nil { firstFailedRequest = request }
    }

    public var errorTitle: String? {
        errorCount > 0 ? Self.counted(errorCount, "error", "errors") : nil
    }

    public var errorDetail: String? {
        guard errorCount > 0, let firstError else { return nil }
        let line = Self.singleLine(firstError)
        return line.isEmpty ? nil : Self.tailTruncated(line, limit: Self.messageLimit)
    }

    public var failedRequestTitle: String? {
        failedRequestCount > 0 ? Self.counted(failedRequestCount, "failed request", "failed requests") : nil
    }

    public func failedRequestDetail(onPage pageURL: String) -> String? {
        guard failedRequestCount > 0, let firstFailedRequest else { return nil }
        let place = Self.middleTruncated(Self.requestPlace(firstFailedRequest.url, onPage: pageURL), limit: Self.pathLimit)
        return "\(Self.statusText(firstFailedRequest.status)) \(place)"
    }

    public var summary: String? {
        var parts: [String] = []
        if errorCount > 0 { parts.append(Self.counted(errorCount, "error", "errors")) }
        if failedRequestCount > 0 { parts.append(Self.counted(failedRequestCount, "failed request", "failed requests")) }
        return parts.isEmpty ? nil : parts.joined(separator: " and ")
    }

    public static func warningTooltip(health: PageHealth, slowVitals: Bool) -> String? {
        switch (health.summary, slowVitals) {
        case let (summary?, true): "\(summary) on this page, plus slow paint or layout shift"
        case let (summary?, false): "\(summary) on this page"
        case (nil, true): "Slow paint or layout shift on this page"
        case (nil, false): nil
        }
    }

    public static func statusText(_ status: Int) -> String {
        if status > 0 { return String(status) }
        switch status {
        case -102: return "refused"
        case -105, -137: return "no host"
        case -106: return "offline"
        case -7, -118: return "timed out"
        case -100, -101: return "reset"
        default: return "failed"
        }
    }

    public static func requestPlace(_ url: String, onPage pageURL: String) -> String {
        guard let request = URLComponents(string: url), let host = request.host else { return url }
        let path = request.percentEncodedPath.isEmpty ? "/" : request.percentEncodedPath
        let page = URLComponents(string: pageURL)
        let sameOrigin = page?.host?.lowercased() == host.lowercased() && page?.port == request.port && page?.scheme?.lowercased() == request.scheme?.lowercased()
        return sameOrigin ? path : host + (request.port.map { ":\($0)" } ?? "") + path
    }

    public static func singleLine(_ text: String) -> String {
        let line = text.split(whereSeparator: \.isNewline).first.map(String.init) ?? ""
        return line.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    public static func tailTruncated(_ text: String, limit: Int) -> String {
        guard text.count > limit else { return text }
        return String(text.prefix(limit - 1)) + "\u{2026}"
    }

    public static func middleTruncated(_ text: String, limit: Int) -> String {
        guard text.count > limit else { return text }
        let kept = limit - 1
        let head = (kept + 1) / 2
        return String(text.prefix(head)) + "\u{2026}" + String(text.suffix(kept - head))
    }

    private static func counted(_ count: Int, _ singular: String, _ plural: String) -> String {
        "\(count) \(count == 1 ? singular : plural)"
    }
}
