import AppKit
import CMiniCore

struct PageFullscreen {
    let tab: Tab
    let sidebarWasVisible: Bool
    let enteredNativeFullscreen: Bool
}

extension ShellController {
    func fullscreenModeChanged(_ identifier: MiniTabId, fullscreen: Bool) {
        if fullscreen {
            guard pageFullscreen == nil, let tab = store.tab(withIdentifier: identifier), tab === store.selectedTab else { return }
            beginPageFullscreen(for: tab)
        } else if pageFullscreen?.tab.id == identifier {
            restoreFromPageFullscreen()
        }
    }

    func endPageFullscreen() {
        guard let pageFullscreen else { return }
        if pageFullscreen.tab.hasBrowser {
            mini_browser_exit_fullscreen(pageFullscreen.tab.id)
        }
        restoreFromPageFullscreen()
    }

    func windowDidExitNativeFullscreen() {
        guard let pageFullscreen else { return }
        self.pageFullscreen = PageFullscreen(tab: pageFullscreen.tab, sidebarWasVisible: pageFullscreen.sidebarWasVisible, enteredNativeFullscreen: false)
        endPageFullscreen()
    }

    private func beginPageFullscreen(for tab: Tab) {
        let isNativeFullscreen = window.styleMask.contains(.fullScreen)
        pageFullscreen = PageFullscreen(tab: tab, sidebarWasVisible: windowController.isSidebarVisible, enteredNativeFullscreen: !isNativeFullscreen)
        commandBar.close(restoringWebFocus: false)
        findBar.close(restoringWebFocus: false)
        statusBubble.hide()
        windowController.setSidebarCollapsed(true)
        windowController.setToolbarVisible(false)
        refreshDisplayedTabs()
        if !isNativeFullscreen {
            window.toggleFullScreen(nil)
        }
        focusSelectedWebContent()
    }

    private func restoreFromPageFullscreen() {
        guard let pageFullscreen else { return }
        self.pageFullscreen = nil
        windowController.setToolbarVisible(true)
        if pageFullscreen.sidebarWasVisible {
            windowController.setSidebarCollapsed(false)
        }
        if pageFullscreen.enteredNativeFullscreen, window.styleMask.contains(.fullScreen) {
            window.toggleFullScreen(nil)
        }
        refreshDisplayedTabs()
    }
}
