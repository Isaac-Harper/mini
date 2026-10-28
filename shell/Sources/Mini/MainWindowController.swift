import AppKit
import SwiftUI

@MainActor
final class MainWindowController: NSWindowController, NSWindowDelegate {
    private let splitViewController = NSSplitViewController()
    private let sidebarItem: NSSplitViewItem
    private let webContentController = WebContentViewController()
    private let windowToolbar: WindowToolbar
    private var controlsCluster: WindowControlsCluster?
    private var showsCollapsedControls = false
    private var isToolbarVisible = true

    var rootView: NSView { webContentController.view }
    var webAreaView: WebAreaView { webContentController.webAreaView }
    var isSidebarVisible: Bool { !sidebarItem.isCollapsed }
    var onDidExitFullScreen: (() -> Void)?

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
        controlsCluster = WindowControlsCluster(commands: shell, window: window, rootView: rootView)
        NotificationCenter.default.addObserver(forName: NSSplitView.didResizeSubviewsNotification, object: splitViewController.splitView, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.updateCollapsedControls() }
        }
        updateCollapsedControls()
    }

    private func updateCollapsedControls() {
        let shows = sidebarItem.isCollapsed && isToolbarVisible
        guard shows != showsCollapsedControls else { return }
        showsCollapsedControls = shows
        windowToolbar.setItemsHidden(shows)
        controlsCluster?.setEnabled(shows)
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

    func setSidebarCollapsed(_ collapsed: Bool) {
        sidebarItem.isCollapsed = collapsed
    }

    func setToolbarVisible(_ visible: Bool) {
        window?.toolbar?.isVisible = visible
        webContentController.setPageFillsWindow(!visible)
        isToolbarVisible = visible
        updateCollapsedControls()
    }

    func windowDidExitFullScreen(_ notification: Notification) {
        onDidExitFullScreen?()
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
    static let cardInset: CGFloat = 8
    static let cardCornerRadius: CGFloat = 10

    let webAreaView = WebAreaView()
    private let cardView = PageCardView()
    private var insetConstraints: [NSLayoutConstraint] = []

    override func loadView() {
        let container = NSView()
        cardView.translatesAutoresizingMaskIntoConstraints = false
        webAreaView.wantsLayer = true
        webAreaView.translatesAutoresizingMaskIntoConstraints = false
        webAreaView.layer?.cornerRadius = Self.cardCornerRadius
        webAreaView.layer?.cornerCurve = .continuous
        webAreaView.layer?.masksToBounds = true
        cardView.addSubview(webAreaView)
        container.addSubview(cardView)
        insetConstraints = [
            cardView.leadingAnchor.constraint(equalTo: container.safeAreaLayoutGuide.leadingAnchor, constant: Self.cardInset),
            container.trailingAnchor.constraint(equalTo: cardView.trailingAnchor, constant: Self.cardInset),
            cardView.topAnchor.constraint(equalTo: container.topAnchor, constant: Self.cardInset),
            container.bottomAnchor.constraint(equalTo: cardView.bottomAnchor, constant: Self.cardInset),
        ]
        NSLayoutConstraint.activate(insetConstraints + [
            webAreaView.leadingAnchor.constraint(equalTo: cardView.leadingAnchor),
            webAreaView.trailingAnchor.constraint(equalTo: cardView.trailingAnchor),
            webAreaView.topAnchor.constraint(equalTo: cardView.topAnchor),
            webAreaView.bottomAnchor.constraint(equalTo: cardView.bottomAnchor),
        ])
        view = container
    }

    func setPageFillsWindow(_ fills: Bool) {
        for constraint in insetConstraints {
            constraint.constant = fills ? 0 : Self.cardInset
        }
        webAreaView.layer?.cornerRadius = fills ? 0 : Self.cardCornerRadius
        cardView.showsShadow = !fills
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

final class PageCardView: NSView {
    var showsShadow = true {
        didSet { needsDisplay = true }
    }

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
        guard let layer else { return }
        layer.shadowColor = NSColor.black.cgColor
        layer.shadowOpacity = showsShadow ? (effectiveAppearance.isDark ? 0.45 : 0.14) : 0
        layer.shadowRadius = 6
        layer.shadowOffset = CGSize(width: 0, height: -1)
        layer.shadowPath = CGPath(roundedRect: bounds, cornerWidth: WebContentViewController.cardCornerRadius,
                                  cornerHeight: WebContentViewController.cardCornerRadius, transform: nil)
    }

    override func layout() {
        super.layout()
        needsDisplay = true
    }
}

extension NSAppearance {
    var isDark: Bool { bestMatch(from: [.darkAqua, .aqua]) == .darkAqua }
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
