import Testing
import MiniRules

struct AddressEmphasisTests {
    private static let domains = ["docs.github.com": "github.com", "www.bbc.co.uk": "bbc.co.uk", "docs.foo.github.io": "foo.github.io", "github.com": "github.com"]

    private static func registrableDomain(_ host: String) -> String? { domains[host] }

    @Test func hostSplitsIntoSubdomainAndDomain() {
        #expect(AddressEmphasis.of(host: "docs.github.com", registrableDomain: Self.registrableDomain)
            == AddressEmphasis(leading: "docs.", domain: "github.com", trailing: ""))
        #expect(AddressEmphasis.of(host: "www.bbc.co.uk", registrableDomain: Self.registrableDomain)
            == AddressEmphasis(leading: "www.", domain: "bbc.co.uk", trailing: ""))
        #expect(AddressEmphasis.of(host: "github.com", registrableDomain: Self.registrableDomain)
            == AddressEmphasis(leading: "", domain: "github.com", trailing: ""))
    }

    @Test func hostWithoutRegistrableDomainIsAllDomain() {
        #expect(AddressEmphasis.of(host: "localhost", registrableDomain: Self.registrableDomain)
            == AddressEmphasis(leading: "", domain: "localhost", trailing: ""))
        #expect(AddressEmphasis.of(host: "127.0.0.1", registrableDomain: Self.registrableDomain)
            == AddressEmphasis(leading: "", domain: "127.0.0.1", trailing: ""))
    }

    @Test func urlSplitsAroundTheDomain() {
        #expect(AddressEmphasis.of(url: "https://docs.github.com/en/get-started?q=1", registrableDomain: Self.registrableDomain)
            == AddressEmphasis(leading: "https://docs.", domain: "github.com", trailing: "/en/get-started?q=1"))
        #expect(AddressEmphasis.of(url: "https://docs.foo.github.io:8443/page", registrableDomain: Self.registrableDomain)
            == AddressEmphasis(leading: "https://docs.", domain: "foo.github.io", trailing: ":8443/page"))
        #expect(AddressEmphasis.of(url: "http://127.0.0.1:8770/long.html", registrableDomain: Self.registrableDomain)
            == AddressEmphasis(leading: "http://", domain: "127.0.0.1", trailing: ":8770/long.html"))
    }

    @Test func urlWithoutHostIsAllLeading() {
        #expect(AddressEmphasis.of(url: "about:blank", registrableDomain: Self.registrableDomain)
            == AddressEmphasis(leading: "about:blank", domain: "", trailing: ""))
    }
}
