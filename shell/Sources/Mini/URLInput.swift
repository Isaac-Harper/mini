import Foundation

enum URLInput {
    static let searchTemplate = "https://www.google.com/search?q=%@"

    enum Interpretation: Equatable {
        case address(String)
        case search(String)

        var url: String {
            switch self {
            case .address(let address):
                return address
            case .search(let query):
                let allowed = CharacterSet.urlQueryAllowed.subtracting(CharacterSet(charactersIn: "&+=?#"))
                guard let encoded = query.addingPercentEncoding(withAllowedCharacters: allowed) else {
                    preconditionFailure("Search query could not be percent-encoded")
                }
                return searchTemplate.replacingOccurrences(of: "%@", with: encoded)
            }
        }
    }

    static func interpret(_ rawInput: String) -> Interpretation {
        let input = rawInput.trimmingCharacters(in: .whitespacesAndNewlines)
        if hasScheme(input) {
            return .address(input)
        }
        if isLocalhost(input) {
            return .address("http://" + input)
        }
        if looksLikeHost(input) {
            return .address("https://" + input)
        }
        return .search(input)
    }

    static func host(of address: String) -> String? {
        guard let host = URL(string: address)?.host(), !host.isEmpty else { return nil }
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }

    private static func hasScheme(_ input: String) -> Bool {
        guard !input.contains(" "), let colonIndex = input.firstIndex(of: ":") else { return false }
        let scheme = input[..<colonIndex]
        guard let first = scheme.first, first.isLetter,
              scheme.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "+" || $0 == "-" || $0 == "." })
        else { return false }
        let remainder = input[input.index(after: colonIndex)...]
        if remainder.hasPrefix("//") { return true }
        let knownOpaqueSchemes: Set<String> = ["about", "data", "mailto", "javascript", "blob", "view-source"]
        return knownOpaqueSchemes.contains(scheme.lowercased())
    }

    private static func isLocalhost(_ input: String) -> Bool {
        let hostAndPort = input.split(separator: "/", maxSplits: 1).first.map(String.init) ?? ""
        let host = hostAndPort.split(separator: ":", maxSplits: 1).first.map(String.init) ?? ""
        return host.lowercased() == "localhost"
    }

    private static func looksLikeHost(_ input: String) -> Bool {
        guard !input.isEmpty, !input.contains(where: \.isWhitespace) else { return false }
        let hostAndPort = input.split(separator: "/", maxSplits: 1).first.map(String.init) ?? ""
        if hostAndPort.hasPrefix("[") { return true }
        let host = hostAndPort.split(separator: ":", maxSplits: 1).first.map(String.init) ?? ""
        let labels = host.split(separator: ".", omittingEmptySubsequences: false)
        guard labels.count >= 2, labels.allSatisfy({ !$0.isEmpty }) else { return false }
        return labels.allSatisfy { label in
            label.allSatisfy { $0.isLetter || $0.isNumber || $0 == "-" }
        }
    }
}
