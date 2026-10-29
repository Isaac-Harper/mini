import AppKit
import CMiniCore
import MiniRules

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

    fileprivate var commandBrowserTab: Tab? {
        guard let littleWindow = keyLittleWindow else { return selectedBrowserTab }
        return littleWindow.tab.hasBrowser ? littleWindow.tab : nil
    }

    fileprivate var mainWindowBrowserTab: Tab? {
        keyLittleWindow == nil ? selectedBrowserTab : nil
    }

    var selectedTabCanGoBack: Bool { selectedBrowserTab?.canGoBack ?? false }

    var selectedTabCanGoForward: Bool { selectedBrowserTab?.canGoForward ?? false }

    func historyMenu(forward: Bool) -> NSMenu {
        guard let tab = selectedBrowserTab else { return NSMenu() }
        return NavigationHistory.menu(for: tab, forward: forward, faviconCache: faviconCache, target: self, action: #selector(jumpInHistory(_:)))
    }

    @objc func jumpInHistory(_ sender: NSMenuItem) {
        guard let jump = sender.representedObject as? HistoryJump, let tab = jump.tab, tab.hasBrowser else { return }
        mini_browser_go_to_history_offset(tab.id, jump.offset)
    }

    func goBack() {
        if let tab = commandBrowserTab { mini_browser_go_back(tab.id) }
    }

    func goForward() {
        if let tab = commandBrowserTab { mini_browser_go_forward(tab.id) }
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
        if let littleWindow = keyLittleWindow {
            littleWindow.editAddress()
            return
        }
        commandBar.open(mode: .editCurrent)
    }

    @objc func openLittleWindowInMini(_ sender: Any?) {
        if let littleWindow = keyLittleWindow { promoteLittleWindow(littleWindow) }
    }

    @objc func closeTab(_ sender: Any?) {
        if let littleWindow = keyLittleWindow {
            littleWindow.close()
        } else if isHistoryWindowKey {
            historyWindow?.close()
        } else if commandBar.isOpen {
            commandBar.close(restoringWebFocus: true)
        } else if store.rowSelection.isMultiple {
            closeTabs(selectedRowTabs)
        } else if let tab = store.selectedTab {
            performUndoable("Close Tab") { store.close(tab) }
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

    @objc func toggleEveningTint(_ sender: Any?) {
        showsEveningTint.toggle()
    }

    @objc func toggleSplitViewCommand(_ sender: Any?) {
        toggleSplitView()
    }

    @objc func reloadPage(_ sender: Any?) {
        if let tab = commandBrowserTab { mini_browser_reload(tab.id) }
    }

    @objc func stopLoading(_ sender: Any?) {
        if let tab = commandBrowserTab { mini_browser_stop(tab.id) }
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
        guard let tab = commandBrowserTab else { return }
        let level = mini_browser_zoom(tab.id, direction)
        if let host = SitePreferences.host(of: tab.url) {
            sitePreferences.setZoomLevel(direction == 0 ? nil : level, host: host)
            for other in allSpaceTabs + littleWindows.values.map(\.tab) where other !== tab && other.hasBrowser && SitePreferences.host(of: other.url) == host {
                mini_browser_set_zoom_level(other.id, level)
            }
        }
        toast.show("\(Int((pow(1.2, level) * 100).rounded()))%")
    }

    @objc func showDeveloperTools(_ sender: Any?) {
        if let tab = commandBrowserTab { mini_browser_show_dev_tools(tab.id) }
    }

    @objc func printPage(_ sender: Any?) {
        if let tab = commandBrowserTab { mini_browser_print(tab.id) }
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
        if let tab = store.selectedTab { performUndoable("Indent Tab") { store.indent(tab) } }
    }

    @objc func outdentTab(_ sender: Any?) {
        if let tab = store.selectedTab { performUndoable("Outdent Tab") { store.outdent(tab) } }
    }

    @objc func toggleTabGroup(_ sender: Any?) {
        guard let tab = store.selectedTab, let group = collapsibleGroup(for: tab) else { return }
        store.toggleCollapse(group)
    }

    @objc func duplicateSelectedTab(_ sender: Any?) {
        if let tab = store.selectedTab { duplicate(tab) }
    }

    @objc func moveTabUp(_ sender: Any?) {
        if let tab = store.selectedTab { performUndoable("Move Tab") { store.move(tab, by: -1) } }
    }

    @objc func moveTabDown(_ sender: Any?) {
        if let tab = store.selectedTab { performUndoable("Move Tab") { store.move(tab, by: 1) } }
    }

    @objc func togglePinnedTab(_ sender: Any?) {
        guard let tab = store.selectedTab else { return }
        if tab.isPinned {
            performUndoable("Unpin Tab") { store.unpin(tab) }
        } else {
            performUndoable("Pin Tab") { store.pin(tab) }
        }
    }

    @objc func toggleSavedTab(_ sender: Any?) {
        guard let tab = store.selectedTab else { return }
        if tab.isSaved {
            performUndoable("Unsave Tab") { store.unsave(tab) }
        } else {
            performUndoable("Save Tab") { store.save(tab) }
        }
    }

    private static let pictureInPictureScript = "javascript:void((function(){if(document.pictureInPictureElement){document.exitPictureInPicture().catch(function(){});return;}var documents=[document];Array.prototype.forEach.call(document.querySelectorAll('iframe'),function(frame){try{if(frame.contentDocument)documents.push(frame.contentDocument);}catch(error){}});var videos=[];documents.forEach(function(candidate){videos=videos.concat(Array.prototype.slice.call(candidate.querySelectorAll('video')));});var playing=videos.filter(function(video){return !video.paused&&!video.ended&&video.readyState>2;});var pool=playing.length?playing:videos;var largest=pool.sort(function(first,second){return second.clientWidth*second.clientHeight-first.clientWidth*first.clientHeight;})[0];if(largest)largest.requestPictureInPicture().catch(function(){});})())"

    @objc func togglePictureInPicture(_ sender: Any?) {
        guard let tab = commandBrowserTab else { return }
        Self.pictureInPictureScript.withCString { mini_browser_load_url(tab.id, $0) }
    }

    @objc func copyTabAddress(_ sender: Any?) {
        guard let url = keyLittleWindow?.tab.url ?? store.selectedTab?.url, !url.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(url, forType: .string)
        toast.show("Copied")
    }

    @objc func fillPassword(_ sender: Any?) {
        if let tab = mainWindowBrowserTab { loginFill.requestFill(for: tab) }
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

    private var selectedWebOrigin: String? {
        guard let tab = selectedBrowserTab, tab.url.hasPrefix("http://") || tab.url.hasPrefix("https://") else { return nil }
        return SitePreferences.origin(of: tab.url)
    }

    @objc func clearDataForSite(_ sender: Any?) {
        guard let tab = selectedBrowserTab, let origin = selectedWebOrigin else { return }
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Clear data for \(URLInput.host(of: tab.url) ?? origin)?"
        alert.informativeText = "Cookies and stored data for this site in \u{201C}\(currentSpace.name)\u{201D} are deleted, which signs you out of it. The page then reloads."
        alert.addButton(withTitle: "Clear Data").hasDestructiveAction = true
        alert.addButton(withTitle: "Cancel")
        alert.beginSheetModal(for: window) { [weak tab] response in
            MainActor.assumeIsolated {
                guard response == .alertFirstButtonReturn, let tab, tab.hasBrowser, SitePreferences.origin(of: tab.url) == origin else { return }
                origin.withCString { mini_browser_clear_site_data(tab.id, $0) }
            }
        }
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
        case #selector(undoTabAction(_:)):
            return tabUndoManager.canUndo
        case #selector(redoTabAction(_:)):
            return tabUndoManager.canRedo
        case #selector(closeTab(_:)):
            let count = keyLittleWindow == nil && !commandBar.isOpen && store.rowSelection.isMultiple ? store.rowSelection.identifiers.count : 1
            menuItem.title = count > 1 ? "Close \(count) Tabs" : "Close Tab"
            return keyLittleWindow != nil || commandBar.isOpen || selected != nil
        case #selector(openLittleWindowInMini(_:)):
            return keyLittleWindow != nil
        case #selector(newChildTab(_:)):
            return selected != nil
        case #selector(fillPassword(_:)), #selector(showFindBar(_:)), #selector(findNextMatch(_:)), #selector(findPreviousMatch(_:)):
            return mainWindowBrowserTab != nil
        case #selector(reloadPage(_:)), #selector(zoomInPage(_:)), #selector(zoomOutPage(_:)),
             #selector(actualSizePage(_:)), #selector(showDeveloperTools(_:)), #selector(printPage(_:)):
            return commandBrowserTab != nil
        case #selector(stopLoading(_:)):
            return commandBrowserTab?.isLoading ?? false
        case #selector(goBackInHistory(_:)):
            return commandBrowserTab?.canGoBack ?? false
        case #selector(goForwardInHistory(_:)):
            return commandBrowserTab?.canGoForward ?? false
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
        case #selector(togglePictureInPicture(_:)):
            return commandBrowserTab != nil
        case #selector(copyTabAddress(_:)):
            return !((keyLittleWindow?.tab ?? selected)?.url.isEmpty ?? true)
        case #selector(moveTabUp(_:)), #selector(moveTabDown(_:)):
            return selected != nil
        case #selector(duplicateSelectedTab(_:)):
            return !(selected?.url.isEmpty ?? true)
        case #selector(toggleSavedTab(_:)):
            menuItem.title = selected?.isSaved == true ? "Unsave Tab" : "Save Tab"
            return selected.map { $0.isSaved || store.canSave($0) } ?? false
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
        case #selector(clearDataForSite(_:)):
            return keyLittleWindow == nil && selectedWebOrigin != nil
        case #selector(resetPermissionsForSite(_:)):
            return selected.map { sitePreferences.hasPermissionDecisions(forSiteAt: $0.url) } ?? false
        case #selector(switchPreviewAndProduction(_:)):
            let isPreview = selected.flatMap { URLInput.host(of: $0.url) }.flatMap(PreviewDeployment.of(host:)) != nil
            menuItem.title = isPreview ? "Switch to Production" : "Switch to Preview"
            return keyLittleWindow == nil && selected.flatMap(previewCounterpartURL(of:)) != nil
        case #selector(toggleEveningTint(_:)):
            menuItem.state = showsEveningTint ? .on : .off
            return true
        case #selector(toggleTabSidebar(_:)):
            menuItem.title = windowController.isSidebarVisible ? "Hide Sidebar" : "Show Sidebar"
            return true
        case #selector(setCurrentSpaceColor(_:)):
            menuItem.state = menuItem.representedObject as? String == currentSpace.color.rawValue ? .on : .off
            return true
        case #selector(deleteCurrentSpace(_:)):
            return canDelete(currentSpace)
        case #selector(selectSpaceAtIndex(_:)):
            let index = menuItem.tag - 1
            menuItem.isHidden = !spaces.indices.contains(index)
            guard spaces.indices.contains(index) else { return false }
            menuItem.title = spaces[index].name
            menuItem.state = spaces[index] === currentSpace ? .on : .off
            return true
        case #selector(toggleSplitViewCommand(_:)):
            guard let selected else { return false }
            let isSplit = store.split(containing: selected) != nil
            menuItem.title = isSplit ? "Close Split View" : "Split View"
            return isSplit || store.splitCandidate(for: selected) != nil
        default:
            return true
        }
    }
}
