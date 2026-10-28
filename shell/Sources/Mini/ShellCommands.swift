import AppKit
import CMiniCore

extension ShellController: NSToolbarItemValidation {
    func validateToolbarItem(_ item: NSToolbarItem) -> Bool {
        switch item.action {
        case #selector(goBackInHistory(_:)):
            return selectedBrowserTab?.canGoBack ?? false
        case #selector(goForwardInHistory(_:)):
            return selectedBrowserTab?.canGoForward ?? false
        case #selector(toggleTabSidebar(_:)):
            item.toolTip = windowController.isSidebarVisible ? "Hide Sidebar" : "Show Sidebar"
            return true
        default:
            return true
        }
    }
}

extension ShellController: NSMenuItemValidation {
    func open(_ url: String, from mode: CommandBarMode) {
        let selected = store.selectedTab
        switch mode {
        case .editCurrent:
            if let selected {
                navigate(selected, to: url)
                return
            }
            store.select(store.newTab(url: url, parent: nil))
        case .newTab:
            store.select(store.newTab(url: url, parent: nil, after: selected.map(store.rootAncestor)))
        case .newChildTab:
            store.select(store.newTab(url: url, parent: selected))
        }
    }

    func openInBackground(_ url: String) {
        store.newTab(url: url, parent: nil, after: store.selectedTab.map(store.rootAncestor))
    }

    fileprivate var selectedBrowserTab: Tab? {
        guard let tab = store.selectedTab, tab.hasBrowser else { return nil }
        return tab
    }

    func goBack() {
        if let tab = selectedBrowserTab { mini_browser_go_back(tab.id) }
    }

    func goForward() {
        if let tab = selectedBrowserTab { mini_browser_go_forward(tab.id) }
    }

    func reloadSelected() {
        if let tab = selectedBrowserTab { mini_browser_reload(tab.id) }
    }

    @objc func newTab(_ sender: Any?) {
        commandBar.open(mode: .newTab)
    }

    @objc func newChildTab(_ sender: Any?) {
        commandBar.open(mode: .newChildTab)
    }

    @objc func reopenClosedTab(_ sender: Any?) {
        store.reopenClosedTab()
    }

    @objc func openLocation(_ sender: Any?) {
        commandBar.open(mode: .editCurrent)
    }

    @objc func closeTab(_ sender: Any?) {
        if commandBar.isOpen {
            commandBar.close(restoringWebFocus: true)
        } else if let tab = store.selectedTab {
            store.close(tab)
        }
    }

    @objc func showFindBar(_ sender: Any?) {
        findBar.open()
    }

    @objc func findNextMatch(_ sender: Any?) {
        findBar.findAgain(forward: true)
    }

    @objc func findPreviousMatch(_ sender: Any?) {
        findBar.findAgain(forward: false)
    }

    @objc func toggleTabSidebar(_ sender: Any?) {
        windowController.toggleSidebar()
    }

    @objc func reloadPage(_ sender: Any?) {
        reloadSelected()
    }

    @objc func stopLoading(_ sender: Any?) {
        if let tab = selectedBrowserTab { mini_browser_stop(tab.id) }
    }

    @objc func zoomInPage(_ sender: Any?) {
        zoomSelected(direction: 1)
    }

    @objc func zoomOutPage(_ sender: Any?) {
        zoomSelected(direction: -1)
    }

    @objc func actualSizePage(_ sender: Any?) {
        zoomSelected(direction: 0)
    }

    private func zoomSelected(direction: Int32) {
        guard let tab = selectedBrowserTab else { return }
        let level = mini_browser_zoom(tab.id, direction)
        if let host = SitePreferences.host(of: tab.url) {
            sitePreferences.setZoomLevel(direction == 0 ? nil : level, host: host)
            for other in store.allTabs where other !== tab && other.hasBrowser && SitePreferences.host(of: other.url) == host {
                mini_browser_set_zoom_level(other.id, level)
            }
        }
        toast.show("\(Int((pow(1.2, level) * 100).rounded()))%")
    }

    @objc func showDeveloperTools(_ sender: Any?) {
        if let tab = selectedBrowserTab { mini_browser_show_dev_tools(tab.id) }
    }

    @objc func goBackInHistory(_ sender: Any?) {
        goBack()
    }

    @objc func goForwardInHistory(_ sender: Any?) {
        goForward()
    }

    @objc func selectNextTab(_ sender: Any?) {
        store.selectNext()
    }

    @objc func selectPreviousTab(_ sender: Any?) {
        store.selectPrevious()
    }

    @objc func indentTab(_ sender: Any?) {
        if let tab = store.selectedTab { store.indent(tab) }
    }

    @objc func outdentTab(_ sender: Any?) {
        if let tab = store.selectedTab { store.outdent(tab) }
    }

    @objc func toggleTabGroup(_ sender: Any?) {
        guard let tab = store.selectedTab, let group = collapsibleGroup(for: tab) else { return }
        store.toggleCollapse(group)
    }

    @objc func togglePinnedTab(_ sender: Any?) {
        guard let tab = store.selectedTab else { return }
        if tab.isPinned {
            store.unpin(tab)
        } else {
            store.pin(tab)
        }
    }

    @objc func copyTabAddress(_ sender: Any?) {
        guard let url = store.selectedTab?.url, !url.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(url, forType: .string)
        toast.show("Copied")
    }

    @objc func fillPassword(_ sender: Any?) {
        if let tab = selectedBrowserTab { loginFill.requestFill(for: tab) }
    }

    @objc func setAsDefaultBrowser(_ sender: Any?) {
        DefaultBrowser.makeDefault()
    }

    private var selectedHost: String? {
        store.selectedTab.flatMap { SitePreferences.host(of: $0.url) }
    }

    @objc func toggleAdBlockForSite(_ sender: Any?) {
        guard let host = selectedHost else { return }
        sitePreferences.setAdBlockExempt(host: host, exempt: !sitePreferences.isAdBlockExempt(host: host))
        reloadSelected()
    }

    @objc func toggleNotificationsForSite(_ sender: Any?) {
        guard let tab = store.selectedTab, SitePreferences.origin(of: tab.url) != nil else { return }
        let allowed = sitePreferences.notificationPermission(forSiteAt: tab.url) == MINI_NOTIFICATION_GRANTED
        sitePreferences.remember(origin: tab.url, permissions: MINI_PERMISSION_NOTIFICATIONS.rawValue, allowed: !allowed)
    }

    @objc func resetPermissionsForSite(_ sender: Any?) {
        guard let tab = store.selectedTab else { return }
        sitePreferences.resetPermissions(forSiteAt: tab.url)
    }

    @objc func selectTabAtIndex(_ sender: NSMenuItem) {
        store.select(index: sender.tag)
    }

    private func collapsibleGroup(for tab: Tab) -> Tab? {
        tab.children.isEmpty ? tab.parent : tab
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        let selected = store.selectedTab
        switch menuItem.action {
        case #selector(reopenClosedTab(_:)):
            return store.canReopenClosedTab
        case #selector(closeTab(_:)):
            return commandBar.isOpen || selected != nil
        case #selector(newChildTab(_:)):
            return selected != nil
        case #selector(fillPassword(_:)), #selector(showFindBar(_:)), #selector(findNextMatch(_:)), #selector(findPreviousMatch(_:)),
             #selector(reloadPage(_:)), #selector(zoomInPage(_:)), #selector(zoomOutPage(_:)),
             #selector(actualSizePage(_:)), #selector(showDeveloperTools(_:)):
            return selectedBrowserTab != nil
        case #selector(stopLoading(_:)):
            return selectedBrowserTab?.isLoading ?? false
        case #selector(goBackInHistory(_:)):
            return selectedBrowserTab?.canGoBack ?? false
        case #selector(goForwardInHistory(_:)):
            return selectedBrowserTab?.canGoForward ?? false
        case #selector(selectNextTab(_:)), #selector(selectPreviousTab(_:)):
            return store.selectableTabs.count > 1
        case #selector(indentTab(_:)):
            return selected.map(store.canIndent) ?? false
        case #selector(outdentTab(_:)):
            return selected?.parent != nil
        case #selector(toggleTabGroup(_:)):
            guard let selected, let group = collapsibleGroup(for: selected) else { return false }
            menuItem.title = group.isCollapsed ? "Expand Group" : "Collapse Group"
            return true
        case #selector(selectTabAtIndex(_:)):
            return !store.selectableTabs.isEmpty
        case #selector(copyTabAddress(_:)):
            return !(selected?.url.isEmpty ?? true)
        case #selector(togglePinnedTab(_:)):
            menuItem.title = selected?.isPinned == true ? "Unpin Tab" : "Pin Tab"
            return selected.map { $0.isPinned || !$0.url.isEmpty } ?? false
        case #selector(setAsDefaultBrowser(_:)):
            menuItem.isHidden = DefaultBrowser.isDefault
            return true
        case #selector(toggleAdBlockForSite(_:)):
            guard let host = selectedHost else {
                menuItem.state = .off
                return false
            }
            menuItem.state = sitePreferences.isAdBlockExempt(host: host) ? .off : .on
            return true
        case #selector(toggleNotificationsForSite(_:)):
            guard let selected, SitePreferences.origin(of: selected.url) != nil else {
                menuItem.state = .off
                return false
            }
            menuItem.state = sitePreferences.notificationPermission(forSiteAt: selected.url) == MINI_NOTIFICATION_GRANTED ? .on : .off
            return true
        case #selector(resetPermissionsForSite(_:)):
            return selected.map { sitePreferences.hasPermissionDecisions(forSiteAt: $0.url) } ?? false
        case #selector(toggleTabSidebar(_:)):
            menuItem.title = windowController.isSidebarVisible ? "Hide Sidebar" : "Show Sidebar"
            return true
        default:
            return true
        }
    }
}
