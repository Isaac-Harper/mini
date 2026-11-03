import Testing
import MiniRules

struct ExternalApplicationLinksTests {
    @Test func schemesAreLowercasedAndValidated() {
        #expect(ExternalApplicationLinks.scheme(of: "zoommtg://zoom.us/join?confno=1&pwd=secret") == "zoommtg")
        #expect(ExternalApplicationLinks.scheme(of: "MAILTO:someone@example.com") == "mailto")
        #expect(ExternalApplicationLinks.scheme(of: "ms-teams:/l/meetup-join") == "ms-teams")
        #expect(ExternalApplicationLinks.scheme(of: "x-apple.systempreferences:com.apple") == "x-apple.systempreferences")
        #expect(ExternalApplicationLinks.scheme(of: "web+mini:thing") == "web+mini")
        #expect(ExternalApplicationLinks.scheme(of: "no scheme here") == nil)
        #expect(ExternalApplicationLinks.scheme(of: ":empty") == nil)
        #expect(ExternalApplicationLinks.scheme(of: "1password://open") == nil)
        #expect(ExternalApplicationLinks.scheme(of: "bad scheme://x") == nil)
        #expect(ExternalApplicationLinks.scheme(of: "zoömtg://x") == nil)
    }

    @Test func browserSchemesNeverGoToAnotherApp() {
        for address in ["https://example.com", "http://example.com", "file:///etc/hosts", "javascript:alert(1)", "data:text/html,x", "about:blank", "chrome://version", "blob:https://a/b"] {
            #expect(ExternalApplicationLinks.scheme(of: address) == nil)
        }
    }

    @Test func onlyWebOriginsCanBeRemembered() {
        #expect(ExternalApplicationLinks.rememberableOrigin("https://Zoom.US") == "https://zoom.us")
        #expect(ExternalApplicationLinks.rememberableOrigin("http://localhost:3000") == "http://localhost:3000")
        #expect(ExternalApplicationLinks.rememberableOrigin("") == nil)
        #expect(ExternalApplicationLinks.rememberableOrigin("file:///Users/me/page.html") == nil)
        #expect(ExternalApplicationLinks.rememberableOrigin("chrome-extension://abc") == nil)
    }

    @Test func hiddenTabsAndDuplicatesAreIgnoredBeforeAnythingElse() {
        #expect(ExternalApplicationLinks.disposition(isTabDisplayed: false, hasPendingPrompt: false, hasApplication: true, isAlwaysAllowed: true) == .ignore)
        #expect(ExternalApplicationLinks.disposition(isTabDisplayed: true, hasPendingPrompt: true, hasApplication: true, isAlwaysAllowed: true) == .ignore)
        #expect(ExternalApplicationLinks.disposition(isTabDisplayed: false, hasPendingPrompt: false, hasApplication: false, isAlwaysAllowed: false) == .ignore)
    }

    @Test func displayedTabsPromptOpenOrReportNoApplication() {
        #expect(ExternalApplicationLinks.disposition(isTabDisplayed: true, hasPendingPrompt: false, hasApplication: false, isAlwaysAllowed: true) == .noApplication)
        #expect(ExternalApplicationLinks.disposition(isTabDisplayed: true, hasPendingPrompt: false, hasApplication: true, isAlwaysAllowed: false) == .prompt)
        #expect(ExternalApplicationLinks.disposition(isTabDisplayed: true, hasPendingPrompt: false, hasApplication: true, isAlwaysAllowed: true) == .open)
    }

    @Test func applicationNamesDropTheBundleExtension() {
        #expect(ExternalApplicationLinks.applicationName(fromBundleFileName: "zoom.us.app") == "zoom.us")
        #expect(ExternalApplicationLinks.applicationName(fromBundleFileName: "Mail") == "Mail")
    }
}
