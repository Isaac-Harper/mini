import Testing
import MiniRules

struct AddressInputTests {
    @Test func barDomainsOpenOverHTTPS() {
        #expect(AddressInput.interpret("example.com") == .address("https://example.com"))
        #expect(AddressInput.interpret("  github.com/apple  ") == .address("https://github.com/apple"))
        #expect(AddressInput.interpret("bbc.co.uk:8443/news") == .address("https://bbc.co.uk:8443/news"))
    }

    @Test func schemesAreKept() {
        #expect(AddressInput.interpret("http://example.com") == .address("http://example.com"))
        #expect(AddressInput.interpret("about:blank") == .address("about:blank"))
        #expect(AddressInput.interpret("mailto:a@b.c") == .address("mailto:a@b.c"))
    }

    @Test func localhostIPAddressesAndBracketedHostsOpenOverHTTP() {
        #expect(AddressInput.interpret("localhost") == .address("http://localhost"))
        #expect(AddressInput.interpret("localhost:3000/a") == .address("http://localhost:3000/a"))
        #expect(AddressInput.interpret("app.localhost:5173") == .address("http://app.localhost:5173"))
        #expect(AddressInput.interpret("192.168.1.1") == .address("http://192.168.1.1"))
        #expect(AddressInput.interpret("10.0.0.93:8080/x") == .address("http://10.0.0.93:8080/x"))
        #expect(AddressInput.interpret("[::1]:3000") == .address("http://[::1]:3000"))
    }

    @Test func numbersAndDecimalsSearch() {
        #expect(AddressInput.interpret("3000") == .search("3000"))
        #expect(AddressInput.interpret("3.14") == .search("3.14"))
        #expect(AddressInput.interpret("1.2.3") == .search("1.2.3"))
        #expect(AddressInput.interpret("999.1.1.1") == .search("999.1.1.1"))
    }

    @Test func wordsAndSpacesSearch() {
        #expect(AddressInput.interpret("swift") == .search("swift"))
        #expect(AddressInput.interpret("swift concurrency") == .search("swift concurrency"))
        #expect(AddressInput.interpret("example.com is down") == .search("example.com is down"))
        #expect(AddressInput.interpret("localhost tips") == .search("localhost tips"))
        #expect(AddressInput.interpret("a..b") == .search("a..b"))
    }

    @Test func searchURLsEncodeReservedCharacters() {
        #expect(AddressInput.Interpretation.search("a&b c").url == "https://www.google.com/search?q=a%26b%20c")
    }
}
