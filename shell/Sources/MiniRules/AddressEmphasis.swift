import Foundation

public struct AddressEmphasis: Equatable {
    public let leading: String
    public let domain: String
    public let trailing: String

    public init(leading: String, domain: String, trailing: String) {
        self.leading = leading
        self.domain = domain
        self.trailing = trailing
    }

    private static let secondLevelLabels: Set<String> = ["co", "com", "net", "org", "gov", "edu", "ac", "ne", "or", "go", "gob", "mil", "nic", "ltd", "plc", "sch"]

    public static func registrableDomain(of host: String) -> String {
        let labels = host.split(separator: ".", omittingEmptySubsequences: false).map(String.init)
        let isAddress = host.contains(":") || labels.allSatisfy { !$0.isEmpty && $0.allSatisfy(\.isNumber) }
        guard !isAddress, labels.count > 2 else { return host }
        let last = labels[labels.count - 1]
        let second = labels[labels.count - 2]
        let count = last.count == 2 && secondLevelLabels.contains(second) ? 3 : 2
        return labels.suffix(count).joined(separator: ".")
    }

    public static func of(host: String) -> AddressEmphasis {
        let domain = registrableDomain(of: host)
        return AddressEmphasis(leading: String(host.dropLast(domain.count)), domain: domain, trailing: "")
    }

    public static func of(url: String) -> AddressEmphasis {
        guard let components = URLComponents(string: url), let hostRange = components.rangeOfHost, let host = components.host, !host.isEmpty else {
            return AddressEmphasis(leading: url, domain: "", trailing: "")
        }
        let domain = registrableDomain(of: String(url[hostRange]))
        let domainStart = url.index(hostRange.upperBound, offsetBy: -domain.count)
        return AddressEmphasis(leading: String(url[..<domainStart]), domain: domain, trailing: String(url[hostRange.upperBound...]))
    }
}
