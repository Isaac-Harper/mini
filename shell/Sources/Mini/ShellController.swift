import AppKit
import CMiniCore
import Observation

struct DownloadNotice: Identifiable, Equatable {
    let id = UUID()
    let path: String
    var fileName: String { (path as NSString).lastPathComponent }
}

@MainActor
@Observable
final class ShellController: NSObject {
    let store = TabStore()
    var downloadNotice: DownloadNotice?

    @ObservationIgnored let sitePreferences: SitePreferences
    @ObservationIgnored private let sessionStore: SessionStore
    @ObservationIgnored private(set) var windowController: MainWindowController!
    @ObservationIgnored private(set) var commandBar: CommandBarController!
    @ObservationIgnored private(set) var findBar: FindBarController!
    @ObservationIgnored private(set) var sitePrompts: SitePromptController!
    @ObservationIgnored private(set) var loginFill: LoginFillController!
    @ObservationIgnored private(set) var isTerminating = false
    @ObservationIgnored var closingTabs: [MiniTabId: Tab] = [:]

    init(sessionStore: SessionStore, sitePreferences: SitePreferences) {
        self.sessionStore = sessionStore
        self.sitePreferences = sitePreferences
        super.init()
    }

    var window: NSWindow {
        guard let window = windowController.window else { preconditionFailure("Main window controller has no window") }
        return window
    }

    func launch(openingURLs externalURLs: [URL]) {
        sitePreferences.pushAdBlockExemptions()
        windowController = MainWindowController(shell: self)
        commandBar = CommandBarController(shell: self)
        findBar = FindBarController(shell: self)
        sitePrompts = SitePromptController(shell: self, preferences: sitePreferences, windowController: windowController)
        loginFill = LoginFillController(shell: self)
        store.observer = self
        showWindow()
        if let session = sessionStore.load(), !session.isEmpty {
            sessionStore.restore(session, into: store)
        } else if externalURLs.isEmpty {
            store.select(store.newTab(url: "", parent: nil))
            commandBar.open(mode: .editCurrent)
        }
        for url in externalURLs {
            openExternalURL(url)
        }
    }

    func showWindow() {
        windowController.showWindow(nil)
        window.makeKeyAndOrderFront(nil)
    }

    func openExternalURL(_ url: URL) {
        commandBar.close(restoringWebFocus: false)
        let selectedRoot = store.selectedTab.map(store.rootAncestor)
        store.select(store.newTab(url: url.absoluteString, parent: nil, after: selectedRoot))
        showWindow()
        NSApp.activate()
    }

    func prepareForTermination() {
        isTerminating = true
        sessionStore.save(store)
    }

    var isOverlayActive: Bool {
        commandBar.isOpen || findBar.hasKeyboardFocus || sitePrompts.hasTextFocus || loginFill.isOpen
    }

    func focusSelectedWebContent() {
        guard let tab = store.selectedTab, !isOverlayActive else { return }
        if let webView = tab.hostView.webView {
            window.makeFirstResponder(webView)
            tab.needsInitialFocus = false
        }
        if tab.hasBrowser {
            mini_browser_set_focus(tab.id, true)
        }
    }

    func navigate(_ tab: Tab, to url: String) {
        tab.url = url
        if tab.hasBrowser {
            url.withCString { mini_browser_load_url(tab.id, $0) }
        } else if tab === store.selectedTab {
            createBrowser(for: tab)
        }
        scheduleSessionSave()
    }

    func scheduleSessionSave() {
        guard !isTerminating else { return }
        sessionStore.scheduleSave(of: store)
    }

    private func createBrowser(for tab: Tab) {
        guard tab.browserState == .none, !tab.url.isEmpty else { return }
        tab.browserState = .created
        tab.needsInitialFocus = true
        let hostViewPointer = Unmanaged.passUnretained(tab.hostView).toOpaque()
        tab.url.withCString { mini_browser_create(tab.id, hostViewPointer, $0) }
    }

    func focusIfAwaitingInitialFocus(_ tab: Tab) {
        guard tab.needsInitialFocus, tab === store.selectedTab, tab.hostView.webView != nil else { return }
        focusSelectedWebContent()
    }
}

extension ShellController: TabStoreObserver {
    func tabStore(_ store: TabStore, didSelect tab: Tab?, previous: Tab?) {
        findBar.close(restoringWebFocus: false)
        loginFill.closeIfOpen()
        commandBar.close(restoringWebFocus: false)
        if let tab {
            tab.hostView.onWebViewAttached = { [weak self, weak tab] in
                guard let self, let tab else { return }
                self.focusIfAwaitingInitialFocus(tab)
            }
            windowController.display(tab.hostView)
            if tab.hasBrowser {
                mini_browser_set_hidden(tab.id, false)
            } else {
                createBrowser(for: tab)
            }
        }
        if let previous {
            previous.hostView.isHidden = true
            if previous.hasBrowser {
                mini_browser_set_focus(previous.id, false)
                mini_browser_set_hidden(previous.id, true)
            }
        }
        sitePrompts.refresh()
        if tab != nil {
            focusSelectedWebContent()
        } else if commandBar.isOpen == false {
            window.makeFirstResponder(nil)
        }
    }

    func tabStore(_ store: TabStore, didRemove tabs: [Tab]) {
        for tab in tabs {
            tab.hostView.isHidden = true
            tab.hostView.onWebViewAttached = nil
            if tab.hasBrowser {
                closingTabs[tab.id] = tab
                mini_browser_close(tab.id)
            } else {
                tab.hostView.removeFromSuperview()
            }
        }
        sitePrompts.discardPrompts(for: tabs)
        for tab in tabs {
            loginFill.close(forTab: tab.id)
        }
    }

    func tabStoreDidChangeStructure(_ store: TabStore) {
        scheduleSessionSave()
    }
}
