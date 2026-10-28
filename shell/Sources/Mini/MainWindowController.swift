import AppKit
import SwiftUI

@MainActor
final class MainWindowController: NSWindowController, NSWindowDelegate {
    private let splitViewController = NSSplitViewController()
    private let sidebarItem: NSSplitViewItem
    private let webContentController = WebContentViewController()
    private let windowToolbar: WindowToolbar

    var rootView: NSView { webContentController.view }
    var webAreaView: WebAreaView { webContentController.webAreaView }
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

    func display(_ hostViews: [BrowserHostView], split: WebAreaView.SplitArrangement?) {
        webContentController.display(hostViews, split: split)
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

    func display(_ hostViews: [BrowserHostView], split: WebAreaView.SplitArrangement?) {
        view.layoutSubtreeIfNeeded()
        for hostView in hostViews where hostView.superview !== webAreaView {
            hostView.frame = webAreaView.bounds
            webAreaView.addSubview(hostView, positioned: .below, relativeTo: nil)
        }
        webAreaView.splitArrangement = split
        webAreaView.layoutSubtreeIfNeeded()
        for hostView in hostViews {
            hostView.isHidden = false
        }
    }
}

final class PassthroughBackgroundExtensionView: NSBackgroundExtensionView {
    override func hitTest(_ point: NSPoint) -> NSView? {
        guard let contentView, let contentSuperview = contentView.superview else { return nil }
        return contentView.hitTest(contentSuperview.convert(point, from: superview))
    }
}

final class WebAreaView: NSView {
    struct SplitArrangement {
        let leading: NSView
        let trailing: NSView
        let fraction: Double
        let focused: NSView
    }

    static let minimumSplitSideWidth: CGFloat = 320
    static let dividerWidth: CGFloat = 6

    var splitArrangement: SplitArrangement? {
        didSet {
            divider.isHidden = splitArrangement == nil
            focusBorder.isHidden = splitArrangement == nil
            if splitArrangement != nil {
                addSubview(divider, positioned: .above, relativeTo: nil)
                addSubview(focusBorder, positioned: .above, relativeTo: nil)
            }
            needsLayout = true
        }
    }

    var onSplitFractionChanged: ((Double, Bool) -> Void)?

    private let divider = SplitDividerView()
    private let focusBorder = SplitFocusBorderView()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        divider.isHidden = true
        focusBorder.isHidden = true
        divider.onDrag = { [weak self] locationInWindow, finished in
            self?.dragDivider(to: locationInWindow, finished: finished)
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func layout() {
        super.layout()
        guard let splitArrangement else {
            for subview in subviews where subview !== divider && subview !== focusBorder && subview.frame != bounds {
                subview.frame = bounds
            }
            return
        }
        let leadingWidth = clampedLeadingWidth(fraction: splitArrangement.fraction)
        let leadingFrame = NSRect(x: 0, y: 0, width: leadingWidth, height: bounds.height)
        let trailingX = leadingWidth + Self.dividerWidth
        let trailingFrame = NSRect(x: trailingX, y: 0, width: max(0, bounds.width - trailingX), height: bounds.height)
        for subview in subviews where subview !== divider && subview !== focusBorder {
            let frame = subview === splitArrangement.leading ? leadingFrame : subview === splitArrangement.trailing ? trailingFrame : bounds
            if subview.frame != frame {
                subview.frame = frame
            }
        }
        divider.frame = NSRect(x: leadingWidth, y: 0, width: Self.dividerWidth, height: bounds.height)
        focusBorder.frame = splitArrangement.focused === splitArrangement.leading ? leadingFrame : trailingFrame
    }

    private var splitContentWidth: CGFloat { max(0, bounds.width - Self.dividerWidth) }

    private func clampedLeadingWidth(fraction: Double) -> CGFloat {
        let minimum = min(Self.minimumSplitSideWidth, splitContentWidth / 2)
        return (splitContentWidth * fraction).clamped(to: minimum...(splitContentWidth - minimum)).rounded()
    }

    private func dragDivider(to locationInWindow: NSPoint, finished: Bool) {
        guard let splitArrangement, splitContentWidth > 0 else { return }
        let x = convert(locationInWindow, from: nil).x - Self.dividerWidth / 2
        let fraction = Double(clampedLeadingWidth(fraction: Double(x / splitContentWidth)) / splitContentWidth)
        self.splitArrangement = SplitArrangement(
            leading: splitArrangement.leading,
            trailing: splitArrangement.trailing,
            fraction: fraction,
            focused: splitArrangement.focused
        )
        layoutSubtreeIfNeeded()
        onSplitFractionChanged?(fraction, finished)
    }

    override var wantsUpdateLayer: Bool { true }

    override func updateLayer() {
        layer?.backgroundColor = NSColor.textBackgroundColor.cgColor
    }
}

final class SplitDividerView: NSView {
    var onDrag: ((NSPoint, Bool) -> Void)?

    override var wantsUpdateLayer: Bool { true }

    override func updateLayer() {
        layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .resizeLeftRight)
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        guard let window else { return }
        window.trackEvents(matching: [.leftMouseDragged, .leftMouseUp], timeout: NSEvent.foreverDuration, mode: .eventTracking) { trackedEvent, stop in
            guard let trackedEvent else { return }
            let finished = trackedEvent.type == .leftMouseUp
            onDrag?(trackedEvent.locationInWindow, finished)
            if finished { stop.pointee = true }
        }
    }
}

final class SplitFocusBorderView: NSView {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override var wantsUpdateLayer: Bool { true }

    override func updateLayer() {
        layer?.borderWidth = 2
        layer?.borderColor = NSColor.controlAccentColor.withAlphaComponent(0.7).cgColor
    }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
