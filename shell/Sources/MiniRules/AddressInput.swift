import Foundation

public enum AddressInput {
    public static let searchTemplate = "https://www.google.com/search?q=%@"

    public enum Interpretation: Equatable, Sendable {
        case address(String)
        case search(String)

        public var url: String {
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

    public static func interpret(_ rawInput: String) -> Interpretation {
        let input = rawInput.trimmingCharacters(in: .whitespacesAndNewlines)
        if hasScheme(input) {
            return .address(input)
        }
        guard !input.isEmpty, !input.contains(where: \.isWhitespace) else { return .search(input) }
        let host = host(of: input)
        if host.lowercased() == "localhost" || host.lowercased().hasSuffix(".localhost") || isIPv4(host) || host.hasPrefix("[") {
            return .address("http://" + input)
        }
        if looksLikeDomain(host) {
            return .address("https://" + input)
        }
        return .search(input)
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

    private static func host(of input: String) -> String {
        let hostAndPort = input.split(separator: "/", maxSplits: 1, omittingEmptySubsequences: false).first.map(String.init) ?? ""
        if hostAndPort.hasPrefix("[") {
            return hostAndPort
        }
        return hostAndPort.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false).first.map(String.init) ?? ""
    }

    private static func isIPv4(_ host: String) -> Bool {
        let octets = host.split(separator: ".", omittingEmptySubsequences: false)
        return octets.count == 4 && octets.allSatisfy { octet in
            !octet.isEmpty && octet.count <= 3 && octet.allSatisfy(\.isASCII) && octet.allSatisfy(\.isNumber) && (Int(octet) ?? 256) <= 255
        }
    }

    private static func looksLikeDomain(_ host: String) -> Bool {
        let labels = host.split(separator: ".", omittingEmptySubsequences: false)
        guard labels.count >= 2, labels.allSatisfy({ !$0.isEmpty }) else { return false }
        guard labels.allSatisfy({ label in label.allSatisfy { $0.isLetter || $0.isNumber || $0 == "-" } }) else { return false }
        return labels.last?.contains(where: \.isLetter) == true
    }
}
