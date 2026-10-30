import CMiniCore
import Foundation
import MiniRules

enum URLInput {
    typealias Interpretation = AddressInput.Interpretation

    static func interpret(_ rawInput: String) -> Interpretation {
        AddressInput.interpret(rawInput)
    }

    static func host(of address: String) -> String? {
        guard let host = URL(string: address)?.host(), !host.isEmpty else { return nil }
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }

    static func registrableDomain(of host: String) -> String? {
        let length = host.withCString { mini_registrable_domain_length($0) }
        guard length > 0 else { return nil }
        return String(decoding: host.utf8.suffix(length), as: UTF8.self)
    }

    static func isInsecure(_ address: String) -> Bool {
        guard let url = URL(string: address), url.scheme?.lowercased() == "http", let host = url.host()?.lowercased() else { return false }
        return !(host == "localhost" || host.hasSuffix(".localhost") || host == "127.0.0.1" || host == "::1" || host == "[::1]")
    }
}
