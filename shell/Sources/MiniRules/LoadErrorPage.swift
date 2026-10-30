public struct LoadErrorPage: Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
        case offline
        case hostNotFound
        case refused
        case reset
        case timedOut
        case certificate
        case blocked
    }

    public enum Action: String, Sendable {
        case retry
        case back
    }

    public struct Colors: Sendable {
        public let background: String
        public let text: String
        public let secondaryText: String
        public let accent: String

        public init(background: String, text: String, secondaryText: String, accent: String) {
            self.background = background
            self.text = text
            self.secondaryText = secondaryText
            self.accent = accent
        }
    }

    public let kind: Kind
    public let host: String

    public init?(errorCode: Int32, host: String, isLocalAddress: Bool) {
        guard let kind = Self.kind(of: errorCode, isLocalAddress: isLocalAddress) else { return nil }
        self.kind = kind
        self.host = host
    }

    public static func kind(of errorCode: Int32, isLocalAddress: Bool) -> Kind? {
        switch errorCode {
        case -106: .offline
        case -105, -137: .hostNotFound
        case -102: isLocalAddress ? nil : .refused
        case -101, -100, -324: .reset
        case -118, -7: .timedOut
        case -20: .blocked
        case -299 ... -200: .certificate
        default: nil
        }
    }

    public var symbolName: String {
        switch kind {
        case .offline: "wifi.slash"
        case .hostNotFound: "questionmark.app.dashed"
        case .refused, .reset: "bolt.horizontal.circle"
        case .timedOut: "clock.badge.exclamationmark"
        case .certificate: "lock.trianglebadge.exclamationmark"
        case .blocked: "hand.raised"
        }
    }

    public var title: String {
        switch kind {
        case .offline: "You\u{2019}re offline"
        case .hostNotFound: "Can\u{2019}t find \(host)"
        case .refused: "\(host) refused to connect"
        case .reset: "The connection to \(host) was reset"
        case .timedOut: "\(host) took too long to respond"
        case .certificate: "This connection isn\u{2019}t private"
        case .blocked: "Mini blocked this page"
        }
    }

    public var detail: String {
        switch kind {
        case .offline: "Mini reloads this page when the connection comes back."
        case .hostNotFound: "Check the address, or the site may no longer exist."
        case .refused, .reset: "The site may be down. Try again in a moment."
        case .timedOut: "The site may be busy, or the connection may be slow."
        case .certificate: "The certificate of \(host) can\u{2019}t be trusted, so Mini didn\u{2019}t load the page."
        case .blocked: "Content blocking stops this address. Turn off Block Ads on This Site to load it."
        }
    }

    public func actions(canGoBack: Bool) -> [Action] {
        switch kind {
        case .certificate: canGoBack ? [.back, .retry] : [.retry]
        default: canGoBack ? [.retry, .back] : [.retry]
        }
    }

    public func html(symbolDataURL: String, colors: Colors, canGoBack: Bool) -> String {
        let buttons = actions(canGoBack: canGoBack).enumerated().map { index, action in
            "<button class=\"\(index == 0 ? "primary" : "secondary")\" data-mini-action=\"\(action.rawValue)\">\(action == .retry ? "Try Again" : "Go Back")</button>"
        }.joined()
        return """
        <!doctype html><html><head><meta charset="utf-8"><title>\(Self.escaped(title))</title><style>
        html,body{margin:0;height:100%;background:\(colors.background);color:\(colors.text);font:13px -apple-system,system-ui,sans-serif;-webkit-user-select:none}
        body{display:flex;align-items:center;justify-content:center}
        main{max-width:440px;padding:24px;text-align:center}
        img{width:44px;height:44px;margin-bottom:16px}
        h1{font-size:17px;font-weight:600;margin:0 0 8px;overflow-wrap:anywhere}
        p{margin:0 0 20px;color:\(colors.secondaryText);line-height:1.4}
        button{font:inherit;font-weight:500;border-radius:8px;padding:6px 16px;margin:0 4px;cursor:default;border:1px solid \(colors.accent)}
        .primary{background:\(colors.accent);color:#fff}
        .secondary{background:transparent;color:\(colors.accent)}
        button:focus-visible{outline:2px solid \(colors.accent);outline-offset:3px}
        </style></head><body><main><img alt="" src="\(symbolDataURL)"><h1>\(Self.escaped(title))</h1><p>\(Self.escaped(detail))</p>\(buttons)</main></body></html>
        """
    }

    public static func escaped(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\"", with: "&quot;")
    }
}
