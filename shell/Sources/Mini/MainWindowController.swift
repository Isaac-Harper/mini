import AppKit
import SwiftUI

@MainActor
final class MainWindowController: NSWindowController, NSWindowDelegate {
    private let splitViewController = NSSplitViewController()
    private let sidebarItem: NSSplitViewItem
    private let webContentController = WebContentViewController()
    private let windowToolbar: WindowToolbar

    var rootView: NSView { webContentController.view }
    var webAreaView: NSView { webContentController.webAreaView }
    var isSidebarVisible: Bool { !sidebarItem.isCollapsed }

    init(shell: ShellController) {
        windowToolbar = WindowToolbar(commands: shell)
        let sidebarController = NSViewController()
        let sidebarHostingView = SidebarHostingView(rootView: SidebarView(shell: shell))
        sidebarHostingView.sizingOptions = []
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
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.titlebarSeparatorStyle = .none
        window.toolbar = windowToolbar.toolbar
        window.toolbarStyle = .unified
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
    private let extensionView = PassthroughBackgroundExtensionView()
    private var hasPinnedBelowTitlebar = false

    override func loadView() {
        let container = NSView()
        extensionView.translatesAutoresizingMaskIntoConstraints = false
        extensionView.automaticallyPlacesContentView = false
        webAreaView.wantsLayer = true
        webAreaView.translatesAutoresizingMaskIntoConstraints = false
        extensionView.contentView = webAreaView
        container.addSubview(extensionView)
        NSLayoutConstraint.activate([
            extensionView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            extensionView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            extensionView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            webAreaView.leadingAnchor.constraint(equalTo: container.safeAreaLayoutGuide.leadingAnchor),
            webAreaView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            webAreaView.topAnchor.constraint(equalTo: extensionView.topAnchor),
            webAreaView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])
        view = container
    }

    override func viewWillAppear() {
        super.viewWillAppear()
        guard !hasPinnedBelowTitlebar else { return }
        guard let window = view.window, let contentLayoutGuide = window.contentLayoutGuide as? NSLayoutGuide else {
            preconditionFailure("Web content appeared without a window content layout guide")
        }
        hasPinnedBelowTitlebar = true
        extensionView.topAnchor.constraint(equalTo: contentLayoutGuide.topAnchor).isActive = true
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

final class PassthroughBackgroundExtensionView: NSBackgroundExtensionView {
    override func hitTest(_ point: NSPoint) -> NSView? {
        guard let contentView, let contentSuperview = contentView.superview else { return nil }
        return contentView.hitTest(contentSuperview.convert(point, from: superview))
    }
}

final class WebAreaView: NSView {
    override func layout() {
        super.layout()
        for subview in subviews where subview.frame != bounds {
            subview.frame = bounds
        }
    }

    override var wantsUpdateLayer: Bool { true }

    override func updateLayer() {
        layer?.backgroundColor = NSColor.textBackgroundColor.cgColor
    }
}
