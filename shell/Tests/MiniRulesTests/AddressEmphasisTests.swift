import Testing
import MiniRules

struct AddressEmphasisTests {
    @Test func registrableDomainDropsSubdomains() {
        #expect(AddressEmphasis.registrableDomain(of: "docs.github.com") == "github.com")
        #expect(AddressEmphasis.registrableDomain(of: "a.b.example.org") == "example.org")
        #expect(AddressEmphasis.registrableDomain(of: "example.com") == "example.com")
    }

    @Test func countryCodeSecondLevelDomainsKeepThreeLabels() {
        #expect(AddressEmphasis.registrableDomain(of: "www.bbc.co.uk") == "bbc.co.uk")
        #expect(AddressEmphasis.registrableDomain(of: "news.abc.net.au") == "abc.net.au")
        #expect(AddressEmphasis.registrableDomain(of: "shop.example.de") == "example.de")
    }

    @Test func addressesAndSingleLabelsStayWhole() {
        #expect(AddressEmphasis.registrableDomain(of: "127.0.0.1") == "127.0.0.1")
        #expect(AddressEmphasis.registrableDomain(of: "localhost") == "localhost")
        #expect(AddressEmphasis.registrableDomain(of: "::1") == "::1")
    }

    @Test func hostSplitsIntoSubdomainAndDomain() {
        #expect(AddressEmphasis.of(host: "docs.github.com") == AddressEmphasis(leading: "docs.", domain: "github.com", trailing: ""))
    }

    @Test func urlSplitsAroundTheDomain() {
        #expect(AddressEmphasis.of(url: "https://docs.github.com/en/get-started?q=1")
            == AddressEmphasis(leading: "https://docs.", domain: "github.com", trailing: "/en/get-started?q=1"))
        #expect(AddressEmphasis.of(url: "http://127.0.0.1:8770/long.html")
            == AddressEmphasis(leading: "http://", domain: "127.0.0.1", trailing: ":8770/long.html"))
    }

    @Test func urlWithoutHostIsAllLeading() {
        #expect(AddressEmphasis.of(url: "about:blank") == AddressEmphasis(leading: "about:blank", domain: "", trailing: ""))
    }
}
