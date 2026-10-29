import AppKit
import CMiniCore
import MiniRules
import Observation

@MainActor
@Observable
final class ShellController: NSObject {
    var spaces: [Space]
    var currentSpace: Space
    let downloads = DownloadsModel()
    let weather = WeatherService()
    let weatherPopover = WeatherPopoverPresenter()
    let sidebarDrag = SidebarDragModel()
    let sidebarKeyboard = SidebarKeyboardFocus()
    let airPlay = AirPlayVideo()
    let soundOutput = SoundOutput()
    private(set) var nowPlayingTab: Tab?
    private(set) var eveningTintDate = Date()
    var showsEveningTint = UserDefaults.standard.object(forKey: ShellController.showsEveningTintKey) as? Bool ?? true {
        didSet { UserDefaults.standard.set(showsEveningTint, forKey: Self.showsEveningTintKey) }
    }

    @ObservationIgnored let sitePreferences: SitePreferences
    @ObservationIgnored let archive: ArchiveStore
    @ObservationIgnored let faviconCache: FaviconCache
    @ObservationIgnored let history: HistoryLibrary
    @ObservationIgnored var historyWindow: HistoryWindowController?
    @ObservationIgnored private var archiveTimer: Timer?
    @ObservationIgnored private let sessionStore: SessionStore
    @ObservationIgnored private(set) var windowController: MainWindowController!
    @ObservationIgnored private(set) var commandBar: CommandBarController!
    @ObservationIgnored private(set) var findBar: FindBarController!
    @ObservationIgnored private(set) var sitePrompts: SitePromptController!
    @ObservationIgnored private(set) var loginFill: LoginFillController!
    @ObservationIgnored private(set) var crashOverlay: CrashOverlayController!
    @ObservationIgnored private(set) var toast: ToastController!
    @ObservationIgnored private(set) var statusBubble: StatusBubbleController!
    @ObservationIgnored private var swipeNavigation: SwipeNavigationController?
    @ObservationIgnored private var spaceSwipeController: SpaceSwipeController?
    @ObservationIgnored let spaceSwipe = SpaceSwipeModel()
    @ObservationIgnored var transferringTabs: Set<MiniTabId> = []
    @ObservationIgnored var tearOff: TabTearOffTracker!
    @ObservationIgnored var dockTracker: LittleWindowDockTracker!
    @ObservationIgnored private(set) var notifications: NotificationsController!
    @ObservationIgnored private(set) var isTerminating = false
    @ObservationIgnored var closingTabs: [MiniTabId: Tab] = [:]
    @ObservationIgnored private(set) var displayedTabs: [Tab] = []
    @ObservationIgnored private var splitFocusMonitor: Any?
    @ObservationIgnored private var sidebarTabKeyMonitor: Any?
    @ObservationIgnored var littleWindows: [MiniTabId: LittleWindowController] = [:]
    @ObservationIgnored let tabIdentifiers = TabIdentifierMint()
    @ObservationIgnored let rootCacheDirectory: URL
    @ObservationIgnored private let savedSession: SavedSession
    @ObservationIgnored var pendingSpaceDeletions: [String: Set<MiniTabId>] = [:]
    @ObservationIgnored var pageFullscreen: PageFullscreen?
    @ObservationIgnored var tabUndoReplacements: [MiniTabId: Tab] = [:]
    @ObservationIgnored let tabUndoManager = UndoManager()
    @ObservationIgnored var pageUndoKeyTimestamp: TimeInterval?

    private static let archiveInterval: TimeInterval = 10 * 60
    private static let showsEveningTintKey = "ShowsEveningTint"

    init(sessionStore: SessionStore, sitePreferences: SitePreferences, archive: ArchiveStore, faviconCache: FaviconCache, history: HistoryLibrary, rootCacheDirectory: URL) {
        self.faviconCache = faviconCache
        self.history = history
        self.sessionStore = sessionStore
        self.sitePreferences = sitePreferences
        self.archive = archive
        self.rootCacheDirectory = rootCacheDirectory
        let session = sessionStore.load()
        savedSession = session
        let identifiers = tabIdentifiers
        var colors: [SpaceColor] = session.spaces.compactMap(\.color)
        let spaces = session.spaces.map { saved in
            let color = saved.color ?? SpaceColor.nextUnused(after: colors)
            if saved.color == nil { colors.append(color) }
            return Space(id: saved.id, name: saved.name, symbol: saved.symbol, color: color, usesDefaultProfile: saved.usesDefaultProfile, identifiers: identifiers)
        }
        self.spaces = spaces
        guard let current = spaces.first(where: { $0.id == session.currentSpace }) ?? spaces.first else {
            preconditionFailure("A session always holds at least one space")
        }
        currentSpace = current
        super.init()
    }

    var store: TabStore { currentSpace.store }

    var allSpaceTabs: [Tab] { spaces.flatMap(\.store.allTabs) }

    func space(containing identifier: MiniTabId) -> Space? {
        spaces.first { $0.store.tab(withIdentifier: identifier) != nil }
    }

    func space(of store: TabStore) -> Space {
        guard let space = spaces.first(where: { $0.store === store }) else { preconditionFailure("Tab store without a space") }
        return space
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
        tabUndoManager.levelsOfUndo = 100
        tabUndoManager.groupsByEvent = false
        commandBar = CommandBarController(shell: self)
        findBar = FindBarController(shell: self)
        sitePrompts = SitePromptController(shell: self, preferences: sitePreferences, windowController: windowController)
        loginFill = LoginFillController(shell: self)
        crashOverlay = CrashOverlayController(shell: self, windowController: windowController)
        toast = ToastController(windowController: windowController)
        statusBubble = StatusBubbleController(shell: self, windowController: windowController)
        swipeNavigation = SwipeNavigationController(shell: self, windowController: windowController)
        spaceSwipeController = SpaceSwipeController(shell: self, sidebarView: windowController.sidebarHostingView)
        tearOff = TabTearOffTracker(shell: self)
        dockTracker = LittleWindowDockTracker(shell: self)
        sidebarDrag.onPointerMoved = { [weak self] tab, point, isReleased in
            guard let self else { return }
            if isReleased {
                self.tearOff.release(tab, at: point)
            } else {
                self.tearOff.update(tab, at: point)
            }
        }
        sidebarDrag.onEnd = { [weak self] in self?.tearOff.reset() }
        sidebarDrag.isSavedRow = { [weak self] identifier in self?.store.tab(withIdentifier: identifier)?.isSaved ?? false }
        registerSpacesWithEngine()
        applySpaceAccent()
        for space in spaces {
            space.store.observer = self
        }
        windowController.onDidExitFullScreen = { [weak self] in self?.windowDidExitNativeFullscreen() }
        windowController.webAreaView.onSplitFractionChanged = { [weak self] fraction, finished in
            guard let self, let selected = self.store.selectedTab, let split = self.store.split(containing: selected) else { return }
            split.fraction = fraction
            if finished { self.scheduleSessionSave() }
        }
        splitFocusMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]) { [weak self] event in
            MainActor.assumeIsolated { self?.focusSplitSide(under: event) }
            return event
        }
        sidebarTabKeyMonitor = installSidebarTabKeyMonitor()
        showWindow()
        for saved in savedSession.spaces {
            guard let space = spaces.first(where: { $0.id == saved.id }) else { preconditionFailure("Saved space was not created") }
            sessionStore.restore(saved.contents, into: space.store)
        }
        refreshDisplayedTabs()
        if store.allTabs.isEmpty, externalURLs.isEmpty {
            store.select(store.newTab(url: "", parent: nil))
            commandBar.open(mode: .editCurrent)
        }
        sessionStore.save(spaces, current: currentSpace)
        for url in externalURLs {
            openExternalURL(url)
        }
        history.onChange = { [weak self] in
            guard let historyWindow = self?.historyWindow, historyWindow.window?.isVisible == true else { return }
            historyWindow.reload()
        }
        archiveIdleTabs()
        weather.start()
        applyCachedFavicons()
        faviconCache.prune(keepingPagesAt: allSpaceTabs.flatMap { [$0.url, $0.pinnedURL ?? ""] } + archive.entries.map(\.url))
        archiveTimer = Timer.scheduledTimer(withTimeInterval: Self.archiveInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.archiveIdleTabs()
                self?.updateEveningTint()
            }
        }
    }

    var eveningTintStrength: Double {
        guard showsEveningTint, let reading = weather.reading else { return 0 }
        return EveningTint.strength(at: eveningTintDate, sunrises: reading.sunrises, sunsets: reading.sunsets)
    }

    func updateEveningTint() {
        eveningTintDate = Date()
    }

    func archiveIdleTabs(now: Date = Date()) {
        for space in spaces {
            archiveIdleTabs(in: space, now: now)
        }
    }

    private func archiveIdleTabs(in space: Space, now: Date) {
        let store = space.store
        let selected = store.selectedTab
        let splitPartner = selected.flatMap { store.split(containing: $0)?.partner(of: $0) }
        func candidate(_ tab: Tab) -> ArchivePolicy.Candidate {
            ArchivePolicy.Candidate(
                identifier: tab.id,
                lastSelectedAt: tab.lastSelectedAt,
                isSelected: tab === selected || tab === splitPartner || tab.isPlayingAudio,
                isSaved: tab.isSaved,
                children: tab.children.map(candidate)
            )
        }
        let identifiers = ArchivePolicy.tabsToArchive(in: store.treeRoots.map(candidate), now: now)
        var archived: [ArchivedTab] = []
        for identifier in identifiers {
            guard let tab = store.tab(withIdentifier: identifier) else { continue }
            if !tab.url.isEmpty {
                archived.append(ArchivedTab(url: tab.url, title: tab.displayTitle, archivedAt: now, spaceIdentifier: space.id))
            }
            store.close(tab)
        }
        archive.add(archived)
        for tab in store.allTabs {
            let isActive = tab === selected || tab === splitPartner || tab.isPlayingAudio
            let fade = isActive || tab.isSaved || tab.isPinned ? 1 : ArchivePolicy.idleOpacity(idleFor: now.timeIntervalSince(tab.lastSelectedAt))
            if tab.idleFade != fade { tab.idleFade = fade }
        }
    }

    func applyCachedFavicons() {
        for tab in allSpaceTabs where tab.favicon == nil {
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
        if airPlay.tab === tab {
            airPlay.togglePlayback()
            return
        }
        let play = !tab.isPlayingAudio
        tab.isPausedFromNowPlaying = !play
        mini_browser_control_media(tab.id, play)
    }

    func audioStateChanged(_ tab: Tab, isPlaying: Bool, mediaTitle: String, mediaVideoURL: String) {
        tab.isPlayingAudio = isPlaying
        tab.mediaTitle = mediaTitle
        if airPlay.tab === tab, isPlaying || mediaVideoURL != tab.mediaVideoURL {
            airPlay.end(takingBack: false)
        }
        tab.mediaVideoURL = mediaVideoURL
        if isPlaying {
            tab.isPausedFromNowPlaying = false
            nowPlayingTab = tab
        } else if nowPlayingTab === tab, !tab.isPausedFromNowPlaying {
            nowPlayingTab = allSpaceTabs.first { $0.isPlayingAudio }
        }
    }

    func forgetNowPlaying(_ tabs: [Tab]) {
        if let handedOff = airPlay.tab, tabs.contains(where: { $0 === handedOff }) {
            airPlay.end(takingBack: false)
        }
        guard let current = nowPlayingTab, tabs.contains(where: { $0 === current }) else { return }
        nowPlayingTab = allSpaceTabs.first { $0.isPlayingAudio }
    }

    func reveal(_ tab: Tab) {
        guard let space = space(containing: tab.id), space.store.tab(withIdentifier: tab.id) === tab else { return }
        switchToSpace(space)
        space.store.select(tab)
    }

    func openWeatherSearch() {
        open(URLInput.Interpretation.search("weather").url, from: .newTab)
    }

    func reopenArchived(_ entry: ArchivedTab) {
        archive.remove(entry)
        if let space = spaces.first(where: { $0.id == entry.spaceIdentifier }) {
            switchToSpace(space)
        }
        let selectedRoot = store.selectedTab.map(store.rootAncestor)
        store.select(store.newTab(url: entry.url, title: entry.title, parent: nil, after: selectedRoot))
    }

    func showWindow() {
        windowController.showWindow(nil)
        window.makeKeyAndOrderFront(nil)
    }

    func openExternalURL(_ url: URL) {
        openLittleWindow(url: url.absoluteString)
        NSApp.activate()
    }

    @discardableResult
    func openLittleWindow(url: String, in space: Space? = nil, createsBrowser: Bool = true) -> LittleWindowController {
        let space = space ?? currentSpace
        let tab = space.store.makeDetachedTab(url: url)
        let littleWindow = LittleWindowController(tab: tab, space: space, shell: self, cascadeIndex: littleWindows.count)
        littleWindows[tab.id] = littleWindow
        tab.hostView.onWebViewAttached = { [weak littleWindow] in
            guard let littleWindow, littleWindow.window?.isKeyWindow == true else { return }
            littleWindow.focusWebContent()
        }
        littleWindow.showWindow(nil)
        littleWindow.window?.makeKeyAndOrderFront(nil)
        if createsBrowser, !url.isEmpty {
            tab.browserState = .created
            let hostViewPointer = Unmanaged.passUnretained(tab.hostView).toOpaque()
            url.withCString { url in space.id.withCString { mini_browser_create(tab.id, hostViewPointer, url, $0) } }
        }
        return littleWindow
    }

    var keyLittleWindow: LittleWindowController? {
        guard let keyWindow = NSApp.keyWindow else { return nil }
        return littleWindows.values.first { $0.window === keyWindow }
    }

    func littleWindow(containing identifier: MiniTabId) -> LittleWindowController? {
        littleWindows[identifier]
    }

    func navigateLittleWindow(_ littleWindow: LittleWindowController, to url: String) {
        let tab = littleWindow.tab
        tab.url = url
        littleWindow.updateAddress()
        if tab.hasBrowser {
            url.withCString { mini_browser_load_url(tab.id, $0) }
        }
    }

    func promoteLittleWindow(_ littleWindow: LittleWindowController) {
        let tab = littleWindow.tab
        guard littleWindows[tab.id] === littleWindow else { return }
        moveIntoMainWindow(littleWindow)
        store.select(tab)
        showWindow()
        NSApp.activate()
    }

    func littleWindowWillClose(_ littleWindow: LittleWindowController, promoting: Bool) {
        guard !promoting else { return }
        let tab = littleWindow.tab
        guard littleWindows[tab.id] === littleWindow else { return }
        littleWindows[tab.id] = nil
        tab.hostView.onWebViewAttached = nil
        if tab.hasBrowser {
            closingTabs[tab.id] = tab
            mini_browser_close(tab.id)
        }
        sitePrompts.discardPrompts(for: [tab])
        loginFill.close(forTab: tab.id)
    }

    func prepareForTermination() {
        isTerminating = true
        for littleWindow in littleWindows.values {
            littleWindow.window?.orderOut(nil)
        }
        sessionStore.save(spaces, current: currentSpace)
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
        sessionStore.scheduleSave { [unowned self] in (self.spaces, self.currentSpace) }
    }

    private func createBrowser(for tab: Tab) {
        guard tab.browserState == .none, !tab.url.isEmpty else { return }
        tab.browserState = .created
        tab.needsInitialFocus = true
        let hostViewPointer = Unmanaged.passUnretained(tab.hostView).toOpaque()
        let spaceIdentifier = space(containingTab: tab).id
        tab.url.withCString { url in spaceIdentifier.withCString { mini_browser_create(tab.id, hostViewPointer, url, $0) } }
    }

    private func space(containingTab tab: Tab) -> Space {
        guard let space = spaces.first(where: { $0.store.tab(withIdentifier: tab.id) === tab }) else {
            preconditionFailure("Tab \(tab.id) belongs to no space")
        }
        return space
    }

    func toggleSplitView() {
        guard let selected = store.selectedTab else { return }
        if let split = store.split(containing: selected) {
            performUndoable("Separate Tabs") { store.unsplit(split) }
        } else if let candidate = store.splitCandidate(for: selected) {
            performUndoable("Split View") { store.makeSplit(leading: selected, trailing: candidate) }
        }
    }

    func duplicate(_ tab: Tab) {
        guard !tab.url.isEmpty else { return }
        performUndoable("Duplicate Tab") {
            let copy = store.newTab(url: tab.url, title: tab.title, parent: tab.isPinned ? nil : tab.parent, after: tab)
            copy.favicon = tab.favicon
            store.select(copy)
        }
    }

    func openLinks(_ links: [PastedLink], inBackground: Bool, nested: Bool) {
        precondition(links.count >= 2, "Opening pasted links needs at least two")
        performUndoable("Open Links") { openLinksUndoably(links, inBackground: inBackground, nested: nested) }
    }

    private func openLinksUndoably(_ links: [PastedLink], inBackground: Bool, nested: Bool) {
        let anchor = store.selectedTab
        let parent = anchor?.isPinned == false ? anchor?.parent : nil
        var opened: [Tab] = []
        for link in links {
            let tab: Tab
            if nested, let group = opened.first {
                tab = store.newTab(url: link.url, title: link.title ?? "", parent: group, after: opened.count > 1 ? opened.last : nil)
            } else {
                tab = store.newTab(url: link.url, title: link.title ?? "", parent: parent, after: opened.last ?? anchor)
            }
            opened.append(tab)
        }
        if !inBackground {
            store.select(opened[0])
        }
    }

        func openInSplitView(_ tab: Tab) {
        guard let selected = store.selectedTab, selected !== tab, !selected.isPinned, !tab.isPinned else { return }
        performUndoable("Split View") { store.makeSplit(leading: selected, trailing: tab) }
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

    func refreshDisplayedTabs() {
        let selected = store.selectedTab
        let split = pageFullscreen == nil ? selected.flatMap(store.split(containing:)) : nil
        let shownTabs = pageFullscreen.map { [$0.tab] } ?? split.map { [$0.leading, $0.trailing] } ?? selected.map { [$0] } ?? []
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
        windowController.webAreaView.showLoadingProgress(of: pageFullscreen == nil ? selected : nil)
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
        guard store === self.store else { return }
        findBar.close(restoringWebFocus: false)
        statusBubble.hide()
        if let pageFullscreen, pageFullscreen.tab !== tab {
            endPageFullscreen()
        }
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
        if let pageFullscreen, tabs.contains(where: { $0 === pageFullscreen.tab }) {
            endPageFullscreen()
        }
        displayedTabs.removeAll { displayed in tabs.contains { $0 === displayed } }
        for tab in tabs where !transferringTabs.contains(tab.id) {
            tab.hostView.isHidden = true
            tab.hostView.onWebViewAttached = nil
            if tab.hasBrowser {
                closingTabs[tab.id] = tab
                mini_browser_close(tab.id)
            } else {
                tab.hostView.removeFromSuperview()
            }
        }
        if store === self.store, displayedTabs.isEmpty {
            refreshDisplayedTabs()
        }
        sitePrompts.discardPrompts(for: tabs)
        forgetNowPlaying(tabs)
        for tab in tabs {
            loginFill.close(forTab: tab.id)
        }
    }

    func tabStoreDidChangeSplits(_ store: TabStore) {
        guard store === self.store else { return }
        refreshDisplayedTabs()
    }

    func tabStoreDidChangeStructure(_ store: TabStore) {
        store.rowSelection.retain(store.visibleTabs.map(\.id))
        applyCachedFavicons()
        scheduleSessionSave()
    }
}
