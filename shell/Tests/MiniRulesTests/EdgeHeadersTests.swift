import Testing
import MiniRules

struct EdgeHeadersTests {
    @Test func vercelHomeFromALiveResponse() {
        let headers = EdgeHeaders.parse(lines: """
        age: 433
        server: Vercel
        x-nextjs-prerender: 1
        x-vercel-cache: HIT
        x-vercel-id: sfo1::5cpl5-1793317141628-271efc543b12
        """)
        #expect(EdgeHeaders.summary(of: headers) == EdgeSummary(platform: "Vercel", details: ["HIT", "sfo1", "age 7m"]))
    }

    @Test func nextjsDocsCarryTheFunctionRegion() {
        let headers = EdgeHeaders.parse(lines: "server: Vercel\nx-vercel-cache: HIT\nx-vercel-id: sfo1::sfo1::bmzqk-1793317142137-539e07792262\nage: 611\n")
        #expect(EdgeHeaders.summary(of: headers)?.text == "Vercel \u{00B7} HIT \u{00B7} sfo1 \u{2192} sfo1 \u{00B7} age 10m")
        #expect(EdgeHeaders.vercelRegions("sfo1::iad1::abc") == "sfo1 \u{2192} iad1")
    }

    @Test func vercelMissWithNextCache() {
        let headers = ["x-vercel-cache": "MISS", "x-vercel-id": "iad1::cle1::xyz12-1730000000000-ffffffffffff", "x-nextjs-cache": "hit", "server": "Vercel"]
        #expect(EdgeHeaders.summary(of: headers) == EdgeSummary(platform: "Vercel", details: ["MISS", "iad1 \u{2192} cle1", "Next.js HIT"]))
    }

    @Test func cloudflareFromALiveResponse() {
        let headers = EdgeHeaders.parse(lines: "cf-ray: a526046bc94c80fd-SJC\ncf-cache-status: HIT\nage: 8\nserver: cloudflare\n")
        #expect(EdgeHeaders.summary(of: headers) == EdgeSummary(platform: "Cloudflare", details: ["HIT", "SJC", "age 8s"]))
        #expect(EdgeHeaders.summary(of: ["server": "cloudflare", "cf-cache-status": "DYNAMIC"])?.text == "Cloudflare \u{00B7} DYNAMIC")
    }

    @Test func otherServersHaveNoBadge() {
        #expect(EdgeHeaders.summary(of: EdgeHeaders.parse(lines: "server: github.com\n")) == nil)
        #expect(EdgeHeaders.summary(of: [:]) == nil)
    }

    @Test func parsingKeepsOnlyKnownHeadersOnce() {
        let headers = EdgeHeaders.parse(lines: "Server: Vercel\nset-cookie: secret=1\nX-Vercel-Cache: STALE\nx-vercel-cache: HIT\nbroken line\nage:\n")
        #expect(headers == ["server": "Vercel", "x-vercel-cache": "STALE"])
    }

    @Test func malformedIdentifiersAndRaysAreIgnored() {
        #expect(EdgeHeaders.vercelRegions("abc") == nil)
        #expect(EdgeHeaders.vercelRegions("dev1::request") == "dev1")
        #expect(EdgeHeaders.vercelRegions("::") == nil)
        #expect(EdgeHeaders.cloudflareColo("8d2c1a2b3c4d5e6f") == nil)
        #expect(EdgeHeaders.cloudflareColo("8d2c-SJCX") == nil)
    }
}
