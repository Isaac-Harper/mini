import Testing
import MiniRules

struct PageHealthTests {
    @Test func collectsOnlyForLocalDevelopmentAndPreviewDeployments() {
        #expect(PageHealth.isCollected(for: "http://localhost:5173/"))
        #expect(PageHealth.isCollected(for: "http://127.0.0.1:3000/app"))
        #expect(PageHealth.isCollected(for: "http://app.localhost:8080/"))
        #expect(PageHealth.isCollected(for: "https://mini-git-feature-x-isaac.vercel.app/"))
        #expect(PageHealth.isCollected(for: "https://deploy-preview-12--mini.netlify.app/"))
        #expect(!PageHealth.isCollected(for: "https://vercel.com/"))
        #expect(!PageHealth.isCollected(for: "https://example.com/"))
        #expect(!PageHealth.isCollected(for: "file:///Users/me/page.html"))
        #expect(!PageHealth.isCollected(for: ""))
    }

    @Test func countsErrorsAndKeepsTheFirstMessage() {
        var health = PageHealth()
        #expect(!health.hasProblems)
        health.recordErrors(2, firstMessage: "TypeError: cannot read 'map'")
        health.recordErrors(1, firstMessage: "ReferenceError: x is not defined")
        health.recordErrors(0, firstMessage: "ignored")
        #expect(health.errorCount == 3)
        #expect(health.firstError == "TypeError: cannot read 'map'")
        #expect(health.errorLine == "3 errors \u{00B7} TypeError: cannot read 'map'")
        #expect(health.hasProblems)
    }

    @Test func oneErrorIsSingularAndAnEmptyMessageShowsTheCountOnly() {
        var health = PageHealth()
        health.recordErrors(1, firstMessage: "  \n ")
        #expect(health.errorLine == "1 error")
    }

    @Test func countsFailedRequestsAndNamesTheFirst() {
        var health = PageHealth()
        health.recordFailedRequest(FailedRequest(status: 404, url: "http://localhost:5173/api/user?id=1"))
        #expect(health.failedRequestLine(onPage: "http://localhost:5173/") == "1 failed request \u{00B7} 404 /api/user")
        health.recordFailedRequest(FailedRequest(status: -102, url: "http://localhost:9999/socket"))
        #expect(health.failedRequestCount == 2)
        #expect(health.failedRequestLine(onPage: "http://localhost:5173/") == "2 failed requests \u{00B7} 404 /api/user")
        #expect(health.errorLine == nil)
    }

    @Test func requestsElsewhereShowTheirHostAndNetErrorsAWord() {
        #expect(PageHealth.requestPlace("https://cdn.example.com/lib.js", onPage: "http://localhost:5173/") == "cdn.example.com/lib.js")
        #expect(PageHealth.requestPlace("http://localhost:9999/socket", onPage: "http://localhost:5173/") == "localhost:9999/socket")
        #expect(PageHealth.requestPlace("http://localhost:5173", onPage: "http://localhost:5173/") == "/")
        #expect(PageHealth.statusText(500) == "500")
        #expect(PageHealth.statusText(-102) == "refused")
        #expect(PageHealth.statusText(-105) == "no host")
        #expect(PageHealth.statusText(-118) == "timed out")
        #expect(PageHealth.statusText(-999) == "failed")
    }

    @Test func messagesBecomeOneTailTruncatedLine() {
        #expect(PageHealth.singleLine("TypeError:   bad\n    at foo (app.js:1)") == "TypeError: bad")
        #expect(PageHealth.tailTruncated("abcdef", limit: 6) == "abcdef")
        #expect(PageHealth.tailTruncated("abcdefg", limit: 6) == "abcde\u{2026}")
        var health = PageHealth()
        health.recordErrors(1, firstMessage: String(repeating: "x", count: 200))
        #expect(health.errorLine == "1 error \u{00B7} " + String(repeating: "x", count: 79) + "\u{2026}")
    }

    @Test func pathsAreMiddleTruncated() {
        #expect(PageHealth.middleTruncated("/short", limit: 10) == "/short")
        #expect(PageHealth.middleTruncated("/abcdefghijkl", limit: 9) == "/abc\u{2026}ijkl")
        #expect(PageHealth.middleTruncated(String(repeating: "a", count: 100), limit: 48).count == 48)
    }

    @Test func warningTooltipNamesWhatIsWrong() {
        var health = PageHealth()
        #expect(PageHealth.warningTooltip(health: health, slowVitals: false) == nil)
        #expect(PageHealth.warningTooltip(health: health, slowVitals: true) == "Slow paint or layout shift on this page")
        health.recordErrors(2, firstMessage: "x")
        #expect(PageHealth.warningTooltip(health: health, slowVitals: false) == "2 errors on this page")
        health.recordFailedRequest(FailedRequest(status: 404, url: "http://localhost/x"))
        #expect(PageHealth.warningTooltip(health: health, slowVitals: false) == "2 errors and 1 failed request on this page")
        #expect(PageHealth.warningTooltip(health: health, slowVitals: true) == "2 errors and 1 failed request on this page, plus slow paint or layout shift")
    }
}
