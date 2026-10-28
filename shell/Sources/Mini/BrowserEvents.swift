import AppKit
import CMiniCore

extension ShellController {
    private func liveTab(_ identifier: MiniTabId) -> Tab? {
        store.tab(withIdentifier: identifier)
    }

    func addressChanged(_ identifier: MiniTabId, url: String) {
        guard let tab = liveTab(identifier) else { return }
        if tab.url != url {
            loginFill.close(forTab: identifier)
        }
        tab.url = url
        let host = SitePreferences.host(of: url)
        if host != tab.zoomedHost {
            tab.zoomedHost = host
            mini_browser_set_zoom_level(tab.id, host.map(sitePreferences.zoomLevel(host:)) ?? 0)
        }
        focusIfAwaitingInitialFocus(tab)
        scheduleSessionSave()
    }

    func titleChanged(_ identifier: MiniTabId, title: String) {
        guard let tab = liveTab(identifier) else { return }
        tab.title = title
        scheduleSessionSave()
    }

    func faviconChanged(_ identifier: MiniTabId, pngData: Data) {
        guard let tab = liveTab(identifier) else { return }
        guard let image = FaviconCache.image(fromPNG: pngData) else {
            tab.favicon = nil
            return
        }
        tab.favicon = image
        faviconCache.store(pngData, image: image, forPageAt: tab.url)
    }

    func loadingStateChanged(_ identifier: MiniTabId, isLoading: Bool, canGoBack: Bool, canGoForward: Bool) {
        guard let tab = liveTab(identifier) else { return }
        if isLoading, tab.hasCrashed {
            tab.hasCrashed = false
            crashOverlay.refresh()
        }
        tab.isLoading = isLoading
        tab.canGoBack = canGoBack
        tab.canGoForward = canGoForward
        focusIfAwaitingInitialFocus(tab)
    }

    func openTabRequested(_ opener: MiniTabId, url: String, foreground: Bool) {
        let tab = store.newTab(url: url, parent: liveTab(opener))
        if foreground {
            store.select(tab)
        }
    }

    func popupRequested(_ opener: MiniTabId, url: String) -> (tab: MiniTabId, hostView: BrowserHostView?) {
        guard !isTerminating, let openerTab = liveTab(opener) else { return (0, nil) }
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

    func browserClosed(_ identifier: MiniTabId) {
        if let tab = closingTabs.removeValue(forKey: identifier) {
            tab.hostView.removeFromSuperview()
            return
        }
        guard !isTerminating, let tab = liveTab(identifier) else { return }
        tab.browserState = .none
        store.close(tab)
    }
}
