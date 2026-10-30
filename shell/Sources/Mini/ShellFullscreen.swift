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
        let animates = !isNativeFullscreen && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        windowController.setSidebarCollapsed(true, animated: animates)
        windowController.setToolbarVisible(false, animated: animates)
        refreshDisplayedTabs()
        focusSelectedWebContent()
        guard !isNativeFullscreen else { return }
        guard animates else {
            window.toggleFullScreen(nil)
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + WebContentViewController.fullscreenGrowDuration) { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.pageFullscreen?.tab === tab, !self.window.styleMask.contains(.fullScreen) else { return }
                self.window.toggleFullScreen(nil)
            }
        }
    }

    private func restoreFromPageFullscreen() {
        guard let pageFullscreen else { return }
        self.pageFullscreen = nil
        let animates = !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        windowController.setToolbarVisible(true, animated: animates)
        if pageFullscreen.sidebarWasVisible {
            windowController.setSidebarCollapsed(false, animated: animates)
        }
        if pageFullscreen.enteredNativeFullscreen, window.styleMask.contains(.fullScreen) {
            window.toggleFullScreen(nil)
        }
        refreshDisplayedTabs()
    }
}
