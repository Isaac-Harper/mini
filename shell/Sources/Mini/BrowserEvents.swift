import AppKit
import CMiniCore
import MiniRules

extension ShellController {
    func liveTab(_ identifier: MiniTabId) -> Tab? {
        space(containing: identifier)?.store.tab(withIdentifier: identifier) ?? littleWindow(containing: identifier)?.tab
    }

    private func spaceIdentifier(ofTab identifier: MiniTabId) -> String? {
        space(containing: identifier)?.id ?? littleWindow(containing: identifier)?.space.id
    }

    func addressChanged(_ identifier: MiniTabId, url: String) {
        guard let tab = liveTab(identifier) else { return }
        if let spaceIdentifier = spaceIdentifier(ofTab: identifier) {
            history.recordVisit(url: url, title: tab.url == url ? tab.title : "", inSpace: spaceIdentifier)
        }
        if tab.url != url {
            loginFill.close(forTab: identifier)
            tab.awaitsReloadTiming = false
        }
        cancelDevServerWait(of: tab, unlessShowing: url)
        tab.url = url
        let host = SitePreferences.host(of: url)
        if host != tab.zoomedHost {
            tab.zoomedHost = host
            mini_browser_set_zoom_level(tab.id, host.map(sitePreferences.zoomLevel(host:)) ?? 0)
        }
        littleWindow(containing: identifier)?.updateAddress()
        refocusAfterCommitIfOrphaned(tab)
        focusIfAwaitingInitialFocus(tab)
        scheduleSessionSave()
    }

    func titleChanged(_ identifier: MiniTabId, title: String) {
        guard let tab = liveTab(identifier) else { return }
        let previousUnread = tab.unread
        tab.title = title
        if let unread = tab.unread, unread.showsBadge, !displayedTabs.contains(where: { $0 === tab }),
           (unread.count ?? 0) > (previousUnread?.count ?? 0) || previousUnread?.showsBadge != true {
            tab.unreadPulses += 1
        }
        if let spaceIdentifier = spaceIdentifier(ofTab: identifier) {
            history.updateTitle(title, url: tab.url, inSpace: spaceIdentifier)
        }
        littleWindow(containing: identifier)?.updateAddress()
        scheduleSessionSave()
    }

    func faviconChanged(_ identifier: MiniTabId, pngData: Data) {
        guard let tab = liveTab(identifier) else { return }
        guard let image = FaviconCache.image(fromPNG: pngData) else {
            tab.favicon = nil
            return
        }
        tab.faviconArrivedLive = true
        tab.favicon = image
        faviconCache.store(pngData, image: image, forPageAt: tab.url)
    }

    func loadingStateChanged(_ identifier: MiniTabId, isLoading: Bool, canGoBack: Bool, canGoForward: Bool) {
        guard let tab = liveTab(identifier) else { return }
        if isLoading, tab.certificateErrorPage != nil {
            tab.certificateErrorPage = nil
            crashOverlay.refresh()
        }
        if isLoading, tab.hasCrashed {
            tab.hasCrashed = false
            crashOverlay.refresh()
        }
        if isLoading, tab === store.selectedTab, let responder = window.firstResponder as? NSView, responder.isDescendant(of: tab.hostView) {
            tab.refocusesOnCommit = true
        }
        if isLoading, !tab.isLoading {
            tab.vitals = WebVitals()
            tab.linkPreviewTags = nil
        }
        tab.isLoading = isLoading
        if tab === store.selectedTab {
            windowController.webAreaView.showLoadingProgress(of: tab)
        }
        if !isLoading {
            playerDock.pageFinishedLoading(tab)
        }
        tab.canGoBack = canGoBack
        tab.canGoForward = canGoForward
        littleWindow(containing: identifier)?.updateAddress()
        focusIfAwaitingInitialFocus(tab)
    }

    func openTabRequested(_ opener: MiniTabId, url: String, foreground: Bool) {
        if let littleWindow = littleWindow(containing: opener) {
            let store = littleWindow.space.store
            let tab = store.newTab(url: url, parent: nil, after: store.selectedTab.map(store.rootAncestor))
            if foreground {
                switchToSpace(littleWindow.space)
                store.select(tab)
                showWindow()
            }
            return
        }
        guard let store = space(containing: opener)?.store else { return }
        let tab = store.newTab(url: url, parent: store.tab(withIdentifier: opener))
        if foreground {
            store.select(tab)
        }
    }

    func popupRequested(_ opener: MiniTabId, url: String) -> (tab: MiniTabId, hostView: BrowserHostView?) {
        guard !isTerminating else { return (0, nil) }
        if let openerWindow = littleWindow(containing: opener) {
            let tab = openLittleWindow(url: url, in: openerWindow.space, createsBrowser: false).tab
            tab.browserState = .pendingPopup
            DispatchQueue.main.async { [weak tab] in
                MainActor.assumeIsolated {
                    guard let tab, tab.browserState == .pendingPopup else { return }
                    tab.browserState = .created
                }
            }
            return (tab.id, tab.hostView)
        }
        guard let store = space(containing: opener)?.store, let openerTab = store.tab(withIdentifier: opener) else { return (0, nil) }
        let tab = store.newTab(url: url, parent: openerTab)
        tab.browserState = .pendingPopup
        tab.needsInitialFocus = true
        store.select(tab)
        DispatchQueue.main.async { [weak self, weak tab] in
            MainActor.assumeIsolated {
                guard let self, let tab, tab.browserState == .pendingPopup else { return }
                tab.browserState = .created
                if tab === self.store.selectedTab {
                    self.focusSelectedWebContent()
                }
            }
        }
        return (tab.id, tab.hostView)
    }

    func focusRequested(_ identifier: MiniTabId) -> Bool {
        if let littleWindow = littleWindow(containing: identifier) {
            return littleWindow.window?.isKeyWindow ?? false
        }
        guard let tab = liveTab(identifier) else { return false }
        return tab === store.selectedTab && !isOverlayActive
    }

    func webGotFocus(_ identifier: MiniTabId) {
        if commandBar.isOpen {
            commandBar.close(restoringWebFocus: false)
        }
        loginFill.closeIfFieldsLostFocus()
    }

    func downloadUpdated(_ progress: DownloadProgress) {
        downloads.update(progress)
    }

    func permissionRequested(_ identifier: MiniTabId, request: UInt64, origin: String, permissions: UInt32) {
        sitePrompts.permissionRequested(tab: identifier, request: request, origin: origin, permissions: permissions)
    }

    func permissionDismissed(request: UInt64) {
        sitePrompts.permissionDismissed(request: request)
    }

    func authenticationRequested(_ identifier: MiniTabId, request: UInt64, host: String, realm: String, isProxy: Bool) {
        sitePrompts.authenticationRequested(tab: identifier, request: request, host: host, realm: realm, isProxy: isProxy)
    }

    func loginFieldFocused(_ identifier: MiniTabId, frameIdentifier: String, origin: String) {
        loginFill.loginFieldFocused(tab: identifier, frameIdentifier: frameIdentifier, origin: origin)
    }

    func renderProcessTerminated(_ identifier: MiniTabId, reason: Int32) {
        guard let tab = liveTab(identifier) else { return }
        tab.hasCrashed = true
        tab.isLoading = false
        crashOverlay.refresh()
    }

    func reloadCrashedTab() {
        guard let tab = store.selectedTab, tab.hasBrowser else { return }
        mini_browser_reload(tab.id)
    }

    func loginFormPresenceChanged(_ identifier: MiniTabId, hasLoginForm: Bool) {
        liveTab(identifier)?.hasLoginForm = hasLoginForm
    }

    func notificationShow(_ identifier: MiniTabId, frame: String, notification: UInt32, origin: String, title: String, body: String, tag: String, silent: Bool) {
        guard liveTab(identifier) != nil else { return }
        notifications.show(tab: identifier, frameIdentifier: frame, notification: notification, origin: origin, title: title, body: body, tag: tag, silent: silent)
    }

    func notificationClose(_ identifier: MiniTabId, frame: String, notification: UInt32) {
        notifications.close(tab: identifier, frameIdentifier: frame, notification: notification)
    }

    func audioStateChanged(_ identifier: MiniTabId, isPlaying: Bool, mediaTitle: String, mediaVideoURL: String) {
        if let littleWindow = littleWindow(containing: identifier) {
            littleWindow.tab.isPlayingAudio = isPlaying
            return
        }
        guard let tab = liveTab(identifier) else { return }
        audioStateChanged(tab, isPlaying: isPlaying, mediaTitle: mediaTitle, mediaVideoURL: mediaVideoURL)
    }

    func videoHandedOff(_ identifier: MiniTabId, url: String, position: Double) {
        guard let tab = liveTab(identifier) else { return }
        airPlay.videoHandedOff(tab, url: url, position: position)
    }

    func mediaArtworkChanged(_ identifier: MiniTabId, pngData: Data) {
        guard let tab = liveTab(identifier) else { return }
        tab.mediaArtwork = FaviconCache.image(fromPNG: pngData)
    }

    func loadingProgressChanged(_ identifier: MiniTabId, progress: Double) {
        guard let tab = liveTab(identifier) else { return }
        tab.loadingProgress = progress
        if tab === store.selectedTab {
            windowController.webAreaView.showLoadingProgress(of: tab)
        }
    }

    func pageBackgroundChanged(_ identifier: MiniTabId, rgba: UInt32) {
        guard let tab = liveTab(identifier) else { return }
        siteBackgrounds.record(rgba, forPageAt: tab.url)
    }

    func themeColorChanged(_ identifier: MiniTabId, rgba: UInt32) {
        guard let tab = liveTab(identifier) else { return }
        let alpha = CGFloat(rgba & 0xff) / 255
        let color = alpha > 0 ? NSColor(srgbRed: CGFloat(rgba >> 24) / 255, green: CGFloat((rgba >> 16) & 0xff) / 255, blue: CGFloat((rgba >> 8) & 0xff) / 255, alpha: alpha) : nil
        if tab.themeColor != color { tab.themeColor = color }
    }

    func horizontalScrollReported(_ identifier: MiniTabId, room: HorizontalScrollRoom) {
        liveTab(identifier)?.horizontalScrollRoom = room
    }

    func statusMessageChanged(_ identifier: MiniTabId, text: String) {
        guard let tab = liveTab(identifier) else { return }
        statusBubble.statusChanged(for: tab, text: text)
        if tab === store.selectedTab {
            hoverPreloader.hoverChanged(tab, url: text)
        }
    }

    func appRelaunched(arguments: [String]) {
        let urls = arguments.compactMap(URL.init(string:)).filter { ["http", "https"].contains($0.scheme?.lowercased()) }
        guard !urls.isEmpty else {
            showWindow()
            NSApp.activate()
            return
        }
        urls.forEach(openExternalURL)
    }

    func pageVitalsChanged(_ identifier: MiniTabId, vitals: WebVitals, loadDuration: Double?) {
        guard let tab = liveTab(identifier) else { return }
        if let loadDuration, tab.awaitsReloadTiming {
            tab.awaitsReloadTiming = false
            showReloadDuration(loadDuration, of: tab)
        }
        if tab.vitals != vitals { tab.vitals = vitals }
    }

    func mainFrameHeadersReceived(_ identifier: MiniTabId, edge: EdgeSummary?) {
        guard let tab = liveTab(identifier), tab.edge != edge else { return }
        tab.edge = edge
    }

    func linkPreviewReported(_ identifier: MiniTabId, tags: LinkPreviewTags) {
        liveTab(identifier)?.linkPreviewTags = tags
    }

    func sourceReceived(_ identifier: MiniTabId, request: UInt64, source: String) {
        SourceWindowController.sourceReceived(request: request, source: source)
    }

    func browserClosed(_ identifier: MiniTabId) {
        if let tab = closingTabs.removeValue(forKey: identifier) {
            tab.hostView.removeFromSuperview()
            browserFinishedClosing(identifier)
            return
        }
        guard !isTerminating else { return }
        if let littleWindow = littleWindow(containing: identifier) {
            littleWindow.tab.browserState = .none
            littleWindow.close()
            return
        }
        guard let tabStore = space(containing: identifier)?.store, let tab = tabStore.tab(withIdentifier: identifier) else { return }
        tab.browserState = .none
        tabStore.close(tab)
    }
}
