import Testing
import MiniRules

struct LoadErrorPageTests {
    @Test func netErrorsMapToKinds() {
        #expect(LoadErrorPage.kind(of: -106, isLocalAddress: false) == .offline)
        #expect(LoadErrorPage.kind(of: -105, isLocalAddress: false) == .hostNotFound)
        #expect(LoadErrorPage.kind(of: -102, isLocalAddress: false) == .refused)
        #expect(LoadErrorPage.kind(of: -101, isLocalAddress: false) == .reset)
        #expect(LoadErrorPage.kind(of: -118, isLocalAddress: false) == .timedOut)
        #expect(LoadErrorPage.kind(of: -202, isLocalAddress: false) == .certificate)
        #expect(LoadErrorPage.kind(of: -20, isLocalAddress: false) == .blocked)
    }

    @Test func abortsAndUnknownErrorsKeepChromiumsPage() {
        #expect(LoadErrorPage.kind(of: -3, isLocalAddress: false) == nil)
        #expect(LoadErrorPage.kind(of: -310, isLocalAddress: false) == nil)
    }

    @Test func refusedLocalServersAreLeftToTheDevServerWait() {
        #expect(LoadErrorPage.kind(of: -102, isLocalAddress: true) == nil)
        #expect(LoadErrorPage.kind(of: -105, isLocalAddress: true) == .hostNotFound)
    }

    @Test func certificateErrorsKeepGoingBackFirst() {
        let page = LoadErrorPage(errorCode: -202, host: "example.com", isLocalAddress: false)
        #expect(page?.actions(canGoBack: true) == [.back, .retry])
        #expect(page?.actions(canGoBack: false) == [.retry])
        #expect(LoadErrorPage(errorCode: -105, host: "example.com", isLocalAddress: false)?.actions(canGoBack: true) == [.retry, .back])
    }

    @Test func hostIsEscapedInTheMarkup() {
        let page = LoadErrorPage(errorCode: -105, host: "<b>&", isLocalAddress: false)!
        let colors = LoadErrorPage.Colors(background: "#000000", text: "#ffffff", secondaryText: "#888888", accent: "#ff9900")
        let html = page.html(symbolDataURL: "data:image/png;base64,", colors: colors, canGoBack: false)
        #expect(html.contains("Can\u{2019}t find &lt;b&gt;&amp;"))
        #expect(!html.contains("<b>&"))
        #expect(html.contains("data-mini-action=\"retry\""))
        #expect(!html.contains("data-mini-action=\"back\""))
    }
}
