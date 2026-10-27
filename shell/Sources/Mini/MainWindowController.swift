import AppKit
import SwiftUI

@MainActor
final class MainWindowController: NSWindowController, NSWindowDelegate {
    private let splitViewController = NSSplitViewController()
    private let sidebarItem: NSSplitViewItem
    private let webContentController = WebContentViewController()

    var rootView: NSView { webContentController.view }
    var webAreaView: NSView { webContentController.webAreaView }
    var isSidebarVisible: Bool { !sidebarItem.isCollapsed }

    init(shell: ShellController) {
        let sidebarController = NSViewController()
        let sidebarHostingView = SidebarHostingView(rootView: SidebarView(shell: shell))
        sidebarHostingView.frame = NSRect(x: 0, y: 0, width: 240, height: 820)
        sidebarController.view = sidebarHostingView

        sidebarItem = NSSplitViewItem(sidebarWithViewController: sidebarController)
        sidebarItem.minimumThickness = 200
        sidebarItem.maximumThickness = 400
        sidebarItem.canCollapse = true

        let contentItem = NSSplitViewItem(viewController: webContentController)
        contentItem.automaticallyAdjustsSafeAreaInsets = true

        splitViewController.addSplitViewItem(sidebarItem)
        splitViewController.addSplitViewItem(contentItem)
        splitViewController.splitView.autosaveName = "MainSplitView"

        let window = NSWindow(contentViewController: splitViewController)
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.minSize = NSSize(width: 640, height: 400)
        window.collectionBehavior.insert(.fullScreenPrimary)
        window.setContentSize(NSSize(width: 1280, height: 820))
        window.center()
        window.setFrameAutosaveName("MainWindow")
        super.init(window: window)
        window.delegate = self
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    func display(_ hostView: BrowserHostView) {
        webContentController.display(hostView)
    }

    func toggleSidebar() {
        splitViewController.toggleSidebar(nil)
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        sender.orderOut(nil)
        return false
    }
}

final class SidebarHostingView: NSHostingView<SidebarView> {
    override var acceptsFirstResponder: Bool { false }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

@MainActor
final class WebContentViewController: NSViewController {
    let webAreaView = WebAreaView()
    private let extensionView = NSBackgroundExtensionView()

    override func loadView() {
        let container = NSView()
        extensionView.translatesAutoresizingMaskIntoConstraints = false
        webAreaView.wantsLayer = true
        extensionView.contentView = webAreaView
        container.addSubview(extensionView)
        NSLayoutConstraint.activate([
            extensionView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            extensionView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            extensionView.topAnchor.constraint(equalTo: container.topAnchor),
            extensionView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])
        view = container
    }

    func display(_ hostView: BrowserHostView) {
        view.layoutSubtreeIfNeeded()
        if hostView.superview !== webAreaView {
            hostView.frame = webAreaView.bounds
            hostView.autoresizingMask = [.width, .height]
            webAreaView.addSubview(hostView)
        }
        hostView.isHidden = false
    }
}

final class WebAreaView: NSView {
    override var wantsUpdateLayer: Bool { true }

    override func updateLayer() {
        layer?.backgroundColor = NSColor.textBackgroundColor.cgColor
    }
}
