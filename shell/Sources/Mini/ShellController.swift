import AppKit
import CMiniCore
import Observation

@MainActor
@Observable
final class ShellController: NSObject {
    let store = TabStore()
    let downloads = DownloadsModel()
    let weather = WeatherService()

    @ObservationIgnored let sitePreferences: SitePreferences
    @ObservationIgnored let archive: ArchiveStore
    @ObservationIgnored let faviconCache: FaviconCache
    @ObservationIgnored private var archiveTimer: Timer?
    @ObservationIgnored private let sessionStore: SessionStore
    @ObservationIgnored private(set) var windowController: MainWindowController!
    @ObservationIgnored private(set) var commandBar: CommandBarController!
    @ObservationIgnored private(set) var findBar: FindBarController!
    @ObservationIgnored private(set) var sitePrompts: SitePromptController!
    @ObservationIgnored private(set) var loginFill: LoginFillController!
    @ObservationIgnored private(set) var crashOverlay: CrashOverlayController!
    @ObservationIgnored private(set) var toast: ToastController!
    @ObservationIgnored private(set) var notifications: NotificationsController!
    @ObservationIgnored private(set) var isTerminating = false
    @ObservationIgnored var closingTabs: [MiniTabId: Tab] = [:]

    private static let archiveInterval: TimeInterval = 10 * 60

    init(sessionStore: SessionStore, sitePreferences: SitePreferences, archive: ArchiveStore, faviconCache: FaviconCache) {
        self.faviconCache = faviconCache
        self.sessionStore = sessionStore
        self.sitePreferences = sitePreferences
        self.archive = archive
        super.init()
    }

    var window: NSWindow {
        guard let window = windowController.window else { preconditionFailure("Main window controller has no window") }
        return window
    }

    func launch(openingURLs externalURLs: [URL]) {
        sitePreferences.pushAdBlockExemptions()
        sitePreferences.pushNotificationPermissions()
        notifications = NotificationsController(shell: self)
        sitePreferences.onNotificationsGranted = { [weak self] in self?.notifications.requestAuthorizationIfNeeded() }
        windowController = MainWindowController(shell: self)
        commandBar = CommandBarController(shell: self)
        findBar = FindBarController(shell: self)
        sitePrompts = SitePromptController(shell: self, preferences: sitePreferences, windowController: windowController)
        loginFill = LoginFillController(shell: self)
        crashOverlay = CrashOverlayController(shell: self, windowController: windowController)
        toast = ToastController(windowController: windowController)
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
        archiveIdleTabs()
        weather.start()
        applyCachedFavicons()
        faviconCache.prune(keepingPagesAt: store.allTabs.flatMap { [$0.url, $0.pinnedURL ?? ""] } + archive.entries.map(\.url))
        archiveTimer = Timer.scheduledTimer(withTimeInterval: Self.archiveInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.archiveIdleTabs() }
        }
    }

    func archiveIdleTabs(now: Date = Date()) {
        let selected = store.selectedTab
        func candidate(_ tab: Tab) -> ArchivePolicy.Candidate {
            ArchivePolicy.Candidate(
                identifier: tab.id,
                lastSelectedAt: tab.lastSelectedAt,
                isSelected: tab === selected,
                children: tab.children.map(candidate)
            )
        }
        let identifiers = ArchivePolicy.tabsToArchive(in: store.rootTabs.map(candidate), now: now)
        var archived: [ArchivedTab] = []
        for identifier in identifiers {
            guard let tab = store.tab(withIdentifier: identifier) else { continue }
            if !tab.url.isEmpty {
                archived.append(ArchivedTab(url: tab.url, title: tab.displayTitle, archivedAt: now))
            }
            store.close(tab)
        }
        archive.add(archived)
    }

    func applyCachedFavicons() {
        for tab in store.allTabs where tab.favicon == nil {
            tab.favicon = faviconCache.image(forPageAt: tab.pinnedURL ?? tab.url)
        }
    }

    func openWeatherSearch() {
        open(URLInput.Interpretation.search("weather").url, from: .newTab)
    }

    func reopenArchived(_ entry: ArchivedTab) {
        archive.remove(entry)
        let selectedRoot = store.selectedTab.map(store.rootAncestor)
        store.select(store.newTab(url: entry.url, title: entry.title, parent: nil, after: selectedRoot))
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
                if tab.hasCrashed {
                    mini_browser_reload(tab.id)
                }
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
        crashOverlay.refresh()
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
        applyCachedFavicons()
        scheduleSessionSave()
    }
}
