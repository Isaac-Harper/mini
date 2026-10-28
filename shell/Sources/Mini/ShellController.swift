import AppKit
import CMiniCore
import Observation

@MainActor
@Observable
final class ShellController: NSObject {
    let store = TabStore()
    let downloads = DownloadsModel()
    let weather = WeatherService()
    private(set) var nowPlayingTab: Tab?

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
    @ObservationIgnored private var displayedTabs: [Tab] = []
    @ObservationIgnored private var splitFocusMonitor: Any?

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
        windowController.webAreaView.onSplitFractionChanged = { [weak self] fraction, finished in
            guard let self, let selected = self.store.selectedTab, let split = self.store.split(containing: selected) else { return }
            split.fraction = fraction
            if finished { self.scheduleSessionSave() }
        }
        splitFocusMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]) { [weak self] event in
            MainActor.assumeIsolated { self?.focusSplitSide(under: event) }
            return event
        }
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
        let splitPartner = selected.flatMap { store.split(containing: $0)?.partner(of: $0) }
        func candidate(_ tab: Tab) -> ArchivePolicy.Candidate {
            ArchivePolicy.Candidate(
                identifier: tab.id,
                lastSelectedAt: tab.lastSelectedAt,
                isSelected: tab === selected || tab === splitPartner || tab.isPlayingAudio,
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

    func setMuted(_ muted: Bool, for tab: Tab) {
        guard tab.hasBrowser else { return }
        tab.isAudioMuted = muted
        mini_browser_set_muted(tab.id, muted)
    }

    func togglePlayback(of tab: Tab) {
        guard tab.hasBrowser else { return }
        let play = !tab.isPlayingAudio
        tab.isPausedFromNowPlaying = !play
        mini_browser_control_media(tab.id, play)
    }

    func audioStateChanged(_ tab: Tab, isPlaying: Bool, mediaTitle: String) {
        tab.isPlayingAudio = isPlaying
        if !mediaTitle.isEmpty { tab.mediaTitle = mediaTitle }
        if isPlaying {
            tab.isPausedFromNowPlaying = false
            nowPlayingTab = tab
        } else if nowPlayingTab === tab, !tab.isPausedFromNowPlaying {
            nowPlayingTab = store.allTabs.first { $0.isPlayingAudio }
        }
    }

    func forgetNowPlaying(_ tabs: [Tab]) {
        guard let current = nowPlayingTab, tabs.contains(where: { $0 === current }) else { return }
        nowPlayingTab = store.allTabs.first { $0.isPlayingAudio }
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

    func toggleSplitView() {
        guard let selected = store.selectedTab else { return }
        if let split = store.split(containing: selected) {
            store.unsplit(split)
        } else if let candidate = store.splitCandidate(for: selected) {
            store.makeSplit(leading: selected, trailing: candidate)
        }
    }

    func openInSplitView(_ tab: Tab) {
        guard let selected = store.selectedTab, selected !== tab, !selected.isPinned, !tab.isPinned else { return }
        store.makeSplit(leading: selected, trailing: tab)
    }

    private func focusSplitSide(under event: NSEvent) {
        guard event.window === windowController.window,
              let selected = store.selectedTab,
              let partner = store.split(containing: selected)?.partner(of: selected),
              let contentView = window.contentView,
              let hitView = contentView.hitTest(contentView.convert(event.locationInWindow, from: nil)),
              hitView.isDescendant(of: partner.hostView)
        else { return }
        store.select(partner)
    }

    private func refreshDisplayedTabs() {
        let selected = store.selectedTab
        let split = selected.flatMap(store.split(containing:))
        let shownTabs = split.map { [$0.leading, $0.trailing] } ?? selected.map { [$0] } ?? []
        for tab in displayedTabs where !shownTabs.contains(where: { $0 === tab }) {
            tab.hostView.isHidden = true
            if tab.hasBrowser, store.tab(withIdentifier: tab.id) === tab {
                mini_browser_set_focus(tab.id, false)
                mini_browser_set_hidden(tab.id, true)
            }
        }
        let arrangement = split.flatMap { split in
            selected.map { focused in
                WebAreaView.SplitArrangement(leading: split.leading.hostView, trailing: split.trailing.hostView, fraction: split.fraction, focused: focused.hostView)
            }
        }
        windowController.display(shownTabs.map(\.hostView), split: arrangement)
        for tab in shownTabs where !displayedTabs.contains(where: { $0 === tab }) {
            if tab.hasBrowser {
                mini_browser_set_hidden(tab.id, false)
                if tab.hasCrashed {
                    mini_browser_reload(tab.id)
                }
            } else {
                createBrowser(for: tab)
            }
        }
        displayedTabs = shownTabs
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
        }
        if let previous, previous.hasBrowser, store.tab(withIdentifier: previous.id) === previous {
            mini_browser_set_focus(previous.id, false)
        }
        refreshDisplayedTabs()
        sitePrompts.refresh()
        crashOverlay.refresh()
        if tab != nil {
            focusSelectedWebContent()
        } else if commandBar.isOpen == false {
            window.makeFirstResponder(nil)
        }
    }

    func tabStore(_ store: TabStore, didRemove tabs: [Tab]) {
        displayedTabs.removeAll { displayed in tabs.contains { $0 === displayed } }
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
        forgetNowPlaying(tabs)
        for tab in tabs {
            loginFill.close(forTab: tab.id)
        }
    }

    func tabStoreDidChangeSplits(_ store: TabStore) {
        refreshDisplayedTabs()
    }

    func tabStoreDidChangeStructure(_ store: TabStore) {
        applyCachedFavicons()
        scheduleSessionSave()
    }
}
