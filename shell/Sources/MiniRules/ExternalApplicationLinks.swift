import Foundation

public enum ExternalLinkDisposition: Sendable, Equatable {
    case ignore
    case noApplication
    case open
    case prompt
}

public enum ExternalApplicationLinks {
    private static let browserSchemes: Set<String> = [
        "about", "blob", "chrome", "chrome-extension", "chrome-untrusted", "data", "devtools", "file",
        "filesystem", "http", "https", "javascript", "view-source", "ws", "wss",
    ]

    public static func scheme(of address: String) -> String? {
        guard let colon = address.firstIndex(of: ":") else { return nil }
        let scheme = address[..<colon].lowercased()
        guard let first = scheme.unicodeScalars.first, ("a"..."z").contains(first),
              scheme.unicodeScalars.allSatisfy({ ("a"..."z").contains($0) || ("0"..."9").contains($0) || "+-.".unicodeScalars.contains($0) }),
              !browserSchemes.contains(scheme)
        else { return nil }
        return scheme
    }

    public static func rememberableOrigin(_ origin: String) -> String? {
        guard let components = URLComponents(string: origin),
              let scheme = components.scheme?.lowercased(), scheme == "https" || scheme == "http",
              let host = components.host?.lowercased(), !host.isEmpty
        else { return nil }
        let port = components.port.map { ":\($0)" } ?? ""
        return "\(scheme)://\(host)\(port)"
    }

    public static func disposition(isTabDisplayed: Bool, hasPendingPrompt: Bool, hasApplication: Bool, isAlwaysAllowed: Bool) -> ExternalLinkDisposition {
        guard isTabDisplayed, !hasPendingPrompt else { return .ignore }
        guard hasApplication else { return .noApplication }
        return isAlwaysAllowed ? .open : .prompt
    }

    public static func applicationName(fromBundleFileName fileName: String) -> String {
        fileName.hasSuffix(".app") ? String(fileName.dropLast(4)) : fileName
    }
}
