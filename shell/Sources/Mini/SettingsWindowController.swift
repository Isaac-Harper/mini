import AppKit
import SwiftUI

enum SettingsPane: String, CaseIterable {
    case general
    case appearance
    case browsing
    case sites

    var title: String {
        switch self {
        case .general: "General"
        case .appearance: "Appearance"
        case .browsing: "Browsing"
        case .sites: "Sites"
        }
    }

    var symbol: String {
        switch self {
        case .general: "gearshape"
        case .appearance: "paintbrush"
        case .browsing: "globe"
        case .sites: "hand.raised"
        }
    }
}

enum SettingsMetrics {
    static let width: CGFloat = 520
    static let sitesHeight: CGFloat = 480
}

extension ShellController {
    @objc func showSettings(_ sender: Any?) {
        let controller = settingsWindow ?? SettingsWindowController(shell: self)
        settingsWindow = controller
        controller.showWindow(nil)
        controller.window?.makeKeyAndOrderFront(nil)
    }

    var isSettingsWindowKey: Bool {
        guard let settingsWindow = settingsWindow?.window else { return false }
        return NSApp.keyWindow === settingsWindow
    }
}

@MainActor
final class SettingsWindowController: NSWindowController, NSWindowDelegate {
    private static let selectedPaneKey = "SettingsSelectedPane"

    init(shell: ShellController) {
        let tabs = SettingsTabViewController()
        tabs.tabStyle = .toolbar
        for pane in SettingsPane.allCases {
            let hosting = NSHostingController(rootView: SettingsPaneView(pane: pane, shell: shell))
            hosting.sizingOptions = [.preferredContentSize]
            let item = NSTabViewItem(viewController: hosting)
            item.label = pane.title
            item.identifier = pane.rawValue
            item.image = NSImage(systemSymbolName: pane.symbol, accessibilityDescription: pane.title)
            tabs.addTabViewItem(item)
        }
        let stored = UserDefaults.standard.string(forKey: Self.selectedPaneKey).flatMap(SettingsPane.init(rawValue:)) ?? .general
        guard let storedIndex = SettingsPane.allCases.firstIndex(of: stored) else { preconditionFailure("Every settings pane has a tab") }
        tabs.selectedTabViewItemIndex = storedIndex
        let window = SettingsWindow(contentViewController: tabs)
        window.styleMask = [.titled, .closable]
        window.toolbarStyle = .preference
        window.isReleasedWhenClosed = false
        super.init(window: window)
        window.delegate = self
        tabs.selectionChanged = { pane in
            UserDefaults.standard.set(pane.rawValue, forKey: Self.selectedPaneKey)
        }
        tabs.fitWindow(animated: false)
        window.center()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }
}

final class SettingsWindow: NSWindow {
    override func cancelOperation(_ sender: Any?) {
        close()
    }
}

@MainActor
final class SettingsTabViewController: NSTabViewController {
    var selectionChanged: ((SettingsPane) -> Void)?

    override func tabView(_ tabView: NSTabView, didSelect tabViewItem: NSTabViewItem?) {
        super.tabView(tabView, didSelect: tabViewItem)
        guard let identifier = tabViewItem?.identifier as? String, let pane = SettingsPane(rawValue: identifier) else { return }
        title = pane.title
        selectionChanged?(pane)
        fitWindow(animated: view.window?.isVisible == true)
    }

    override func preferredContentSizeDidChange(for viewController: NSViewController) {
        super.preferredContentSizeDidChange(for: viewController)
        guard viewController === tabViewItems[selectedTabViewItemIndex].viewController else { return }
        fitWindow(animated: view.window?.isVisible == true)
    }

    func fitWindow(animated: Bool) {
        guard let window = view.window, let selected = tabViewItems[selectedTabViewItemIndex].viewController else { return }
        let height = selected.preferredContentSize.height
        guard height > 0 else { return }
        let content = window.contentRect(forFrameRect: window.frame)
        let target = NSRect(x: content.minX, y: content.maxY - height, width: SettingsMetrics.width, height: height)
        let animates = animated && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        window.setFrame(window.frameRect(forContentRect: target), display: true, animate: animates)
    }
}

private struct SettingsPaneView: View {
    let pane: SettingsPane
    let shell: ShellController

    var body: some View {
        Group {
            switch pane {
            case .general: GeneralSettingsPane(shell: shell)
            case .appearance: AppearanceSettingsPane(shell: shell)
            case .browsing: BrowsingSettingsPane(hoverPreloader: shell.hoverPreloader)
            case .sites: SitesSettingsPane(shell: shell)
            }
        }
        .frame(width: SettingsMetrics.width)
    }
}
