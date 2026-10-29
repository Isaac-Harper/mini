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

    public static func of(host: String, registrableDomain: (String) -> String?) -> AddressEmphasis {
        let domain = emphasizedDomain(of: host, registrableDomain: registrableDomain)
        return AddressEmphasis(leading: String(host.dropLast(domain.count)), domain: domain, trailing: "")
    }

    public static func of(url: String, registrableDomain: (String) -> String?) -> AddressEmphasis {
        guard let components = URLComponents(string: url), let hostRange = components.rangeOfHost, let host = components.host, !host.isEmpty else {
            return AddressEmphasis(leading: url, domain: "", trailing: "")
        }
        let domain = emphasizedDomain(of: String(url[hostRange]), registrableDomain: registrableDomain)
        let domainStart = url.index(hostRange.upperBound, offsetBy: -domain.count)
        return AddressEmphasis(leading: String(url[..<domainStart]), domain: domain, trailing: String(url[hostRange.upperBound...]))
    }

    private static func emphasizedDomain(of host: String, registrableDomain: (String) -> String?) -> String {
        guard let domain = registrableDomain(host) else { return host }
        precondition(host.hasSuffix(domain), "registrable domain \(domain) is not a suffix of \(host)")
        return domain
    }
}
