import AppKit
import CMiniCore
import MiniRules
import SwiftUI

@MainActor
final class MainWindowController: NSWindowController, NSWindowDelegate {
    private let splitViewController = NSSplitViewController()
    private let sidebarItem: NSSplitViewItem
    let sidebarHostingView: SidebarHostingView
    let webContentController = WebContentViewController()
    private let windowToolbar: WindowToolbar
    private var controlsCluster: WindowControlsCluster?
    private var peekSidebar: PeekSidebarController?
    private var expandedSidebarWidth = SidebarMetrics.defaultWidth
    private var sidebarCollapseDetent = DetentChange<Bool>()
    private var sidebarEdgeDetent = DetentEntry<SidebarWidthEdge>()
    private weak var sidebarSnapEvent: NSEvent?
    private var showsCollapsedControls = false
    private var isToolbarVisible = true

    var rootView: NSView { webContentController.view }
    var webAreaView: WebAreaView { webContentController.webAreaView }
    var isSidebarVisible: Bool { !sidebarItem.isCollapsed }
    var onSidebarLayoutChanged: (() -> Void)?

    var sidebarPresence: PlayerSlot.Sidebar {
        if isSidebarVisible { return .expanded }
        return peekSidebar?.isPeeking == true ? .peeking : .hidden
    }

    var webAreaScreenFrame: NSRect? {
        guard let window = webAreaView.window else { return nil }
        return window.convertToScreen(webAreaView.convert(webAreaView.bounds, to: nil))
    }

    func sidebarHostingView(for kind: PlayerDock.SidebarKind) -> NSView? {
        switch kind {
        case .main: sidebarHostingView
        case .peek: peekSidebar?.hostingView
        }
    }
    var onDidExitFullScreen: (() -> Void)?

    init(shell: ShellController) {
        windowToolbar = WindowToolbar(commands: shell)
        let sidebarController = NSViewController()
        sidebarHostingView = SidebarHostingView(rootView: SidebarView(shell: shell, reportsRowFrames: true))
        sidebarHostingView.onKeyDown = { [weak shell] event in shell?.sidebarKeyDown(event) ?? false }
        sidebarHostingView.onResignKeyboardFocus = { [weak shell] in shell?.sidebarResignedKeyboardFocus() }
        sidebarHostingView.sizingOptions = []
        sidebarHostingView.frame = NSRect(x: 0, y: 0, width: SidebarMetrics.defaultWidth, height: 820)
        sidebarController.view = sidebarHostingView

        sidebarItem = NSSplitViewItem(sidebarWithViewController: sidebarController)
        sidebarItem.minimumThickness = SidebarMetrics.minimumWidth
        sidebarItem.maximumThickness = SidebarMetrics.maximumWidth
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
        let cluster = WindowControlsCluster(commands: shell, window: window, rootView: rootView)
        controlsCluster = cluster
        peekSidebar = PeekSidebarController(shell: shell, cluster: cluster, rootView: rootView)
        NotificationCenter.default.addObserver(forName: NSSplitView.didResizeSubviewsNotification, object: splitViewController.splitView, queue: .main) { [weak self] notification in
            let isDividerDrag = notification.userInfo?["NSSplitViewDividerIndex"] != nil
            MainActor.assumeIsolated {
                self?.updateCollapsedControls()
                self?.noteSidebarResize(isDividerDrag: isDividerDrag)
                self?.onSidebarLayoutChanged?()
            }
        }
        NotificationCenter.default.addObserver(forName: NSWindow.didResizeNotification, object: window, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.onSidebarLayoutChanged?() }
        }
        updateCollapsedControls()
    }

    private func noteSidebarResize(isDividerDrag: Bool) {
        let isCollapsed = sidebarItem.isCollapsed
        guard let pane = splitViewController.splitView.arrangedSubviews.first else { preconditionFailure("Split view without a sidebar pane") }
        pane.layoutSubtreeIfNeeded()
        let width = sidebarItem.viewController.view.frame.width
        let edge = isCollapsed ? nil : SidebarWidthEdge.of(width: width, minimum: sidebarItem.minimumThickness, maximum: sidebarItem.maximumThickness)
        let event = NSApp.currentEvent
        let isDirect = isDividerDrag && [.leftMouseDragged, .leftMouseUp].contains(event?.type)
        let snapped = sidebarCollapseDetent.update(isCollapsed)
        let reachedEdge = sidebarEdgeDetent.update(edge)
        if snapped {
            sidebarSnapEvent = event
        }
        guard isDirect else { return }
        if snapped {
            Haptics.sidebarSnappedCollapsed()
        } else if reachedEdge, event !== sidebarSnapEvent {
            Haptics.sidebarReachedWidthLimit()
        }
    }

    private func updateCollapsedControls() {
        let sidebarWidth = sidebarItem.viewController.view.frame.width
        if !sidebarItem.isCollapsed, sidebarWidth >= sidebarItem.minimumThickness {
            expandedSidebarWidth = sidebarWidth
        }
        let shows = sidebarItem.isCollapsed && isToolbarVisible
        guard shows != showsCollapsedControls else { return }
        showsCollapsedControls = shows
        windowToolbar.setItemsHidden(shows)
        controlsCluster?.setEnabled(shows)
        peekSidebar?.setEnabled(shows, sidebarWidth: expandedSidebarWidth)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    func display(_ hostViews: [BrowserHostView], split: WebAreaView.SplitArrangement?, awaitsHostView: Bool = false) {
        webContentController.display(hostViews, split: split, awaitsHostView: awaitsHostView)
    }

    func focusSidebar() -> Bool {
        sidebarHostingView.allowsKeyboardFocus = true
        return window?.makeFirstResponder(sidebarHostingView) ?? false
    }

    func toggleSidebar() {
        splitViewController.toggleSidebar(nil)
    }

    func applyInterfaceScale(from oldScale: Double, to newScale: Double) {
        let current = sidebarItem.isCollapsed ? expandedSidebarWidth : sidebarHostingView.frame.width
        let width = CGFloat(InterfaceSize.sidebarWidth(Double(current), from: oldScale, to: newScale,
                                                       minimum: Double(SidebarMetrics.minimumWidth), maximum: Double(SidebarMetrics.maximumWidth)))
        sidebarItem.minimumThickness = min(sidebarItem.minimumThickness, SidebarMetrics.minimumWidth)
        sidebarItem.maximumThickness = max(sidebarItem.maximumThickness, SidebarMetrics.maximumWidth)
        if sidebarItem.isCollapsed {
            expandedSidebarWidth = width
        } else {
            guard let pane = splitViewController.splitView.arrangedSubviews.first else { preconditionFailure("Split view without a sidebar pane") }
            splitViewController.splitView.setPosition(width + pane.frame.width - sidebarHostingView.frame.width, ofDividerAt: 0)
        }
        sidebarItem.minimumThickness = SidebarMetrics.minimumWidth
        sidebarItem.maximumThickness = SidebarMetrics.maximumWidth
        updateCollapsedControls()
        if showsCollapsedControls {
            peekSidebar?.setEnabled(true, sidebarWidth: expandedSidebarWidth)
        }
    }

    func setSidebarCollapsed(_ collapsed: Bool, animated: Bool = false) {
        if animated {
            sidebarItem.animator().isCollapsed = collapsed
        } else {
            sidebarItem.isCollapsed = collapsed
        }
    }

    func hidePageCardUntilRevealed() {
        webContentController.cardView.alphaValue = 0
    }

    func revealPageCard(duration: TimeInterval) {
        NSAnimationContext.runAnimationGroup { context in
            context.duration = duration
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            webContentController.cardView.animator().alphaValue = 1
        }
    }

    func setToolbarVisible(_ visible: Bool, animated: Bool = false) {
        window?.toolbar?.isVisible = visible
        webContentController.setPageFillsWindow(!visible, animated: animated)
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
    var allowsKeyboardFocus = false
    var onKeyDown: ((NSEvent) -> Bool)?
    var onResignKeyboardFocus: (() -> Void)?

    override var acceptsFirstResponder: Bool { allowsKeyboardFocus }

    override func resignFirstResponder() -> Bool {
        allowsKeyboardFocus = false
        onResignKeyboardFocus?()
        return super.resignFirstResponder()
    }

    override func keyDown(with event: NSEvent) {
        guard allowsKeyboardFocus, onKeyDown?(event) == true else {
            super.keyDown(with: event)
            return
        }
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

@MainActor
final class WebContentViewController: NSViewController {
    static let cardInset: CGFloat = 8
    static let cardCornerRadius = CornerMetrics.concentric(outer: CornerMetrics.window, inset: cardInset)

    let webAreaView = WebAreaView()
    let cardView = PageCardView()
    let pageArea = NSLayoutGuide()
    private(set) var narrowWidthConstraint: NSLayoutConstraint!
    private let emptyStateView = EmptyPageView()
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
        emptyStateView.translatesAutoresizingMaskIntoConstraints = false
        emptyStateView.wantsLayer = true
        cardView.addSubview(emptyStateView)
        container.addSubview(cardView)
        container.addLayoutGuide(pageArea)
        insetConstraints = [
            pageArea.leadingAnchor.constraint(equalTo: container.safeAreaLayoutGuide.leadingAnchor, constant: Self.cardInset),
            container.trailingAnchor.constraint(equalTo: pageArea.trailingAnchor, constant: Self.cardInset),
            pageArea.topAnchor.constraint(equalTo: container.topAnchor, constant: Self.cardInset),
            container.bottomAnchor.constraint(equalTo: pageArea.bottomAnchor, constant: Self.cardInset),
        ]
        let fullWidth = cardView.widthAnchor.constraint(equalTo: pageArea.widthAnchor)
        fullWidth.priority = .defaultLow
        narrowWidthConstraint = cardView.widthAnchor.constraint(equalToConstant: 0)
        narrowWidthConstraint.priority = .init(999)
        NSLayoutConstraint.activate(insetConstraints + [
            cardView.centerXAnchor.constraint(equalTo: pageArea.centerXAnchor),
            cardView.widthAnchor.constraint(lessThanOrEqualTo: pageArea.widthAnchor),
            fullWidth,
            cardView.topAnchor.constraint(equalTo: pageArea.topAnchor),
            cardView.bottomAnchor.constraint(equalTo: pageArea.bottomAnchor),
            webAreaView.leadingAnchor.constraint(equalTo: cardView.leadingAnchor),
            webAreaView.trailingAnchor.constraint(equalTo: cardView.trailingAnchor),
            webAreaView.topAnchor.constraint(equalTo: cardView.topAnchor),
            webAreaView.bottomAnchor.constraint(equalTo: cardView.bottomAnchor),
            emptyStateView.centerXAnchor.constraint(equalTo: cardView.centerXAnchor),
            emptyStateView.centerYAnchor.constraint(equalTo: cardView.centerYAnchor),
        ])
        view = container
    }

    func setPageFillsWindow(_ fills: Bool, animated: Bool = false) {
        guard animated else {
            for constraint in insetConstraints {
                constraint.constant = fills ? 0 : Self.cardInset
            }
            webAreaView.layer?.cornerRadius = fills ? 0 : Self.cardCornerRadius
            cardView.showsShadow = !fills
            return
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = Self.fullscreenGrowDuration
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            context.allowsImplicitAnimation = true
            for constraint in insetConstraints {
                constraint.animator().constant = fills ? 0 : Self.cardInset
            }
            webAreaView.layer?.cornerRadius = fills ? 0 : Self.cardCornerRadius
            cardView.showsShadow = !fills
            view.layoutSubtreeIfNeeded()
        }
    }

    static let fullscreenGrowDuration: TimeInterval = 0.25

    func display(_ hostViews: [BrowserHostView], split: WebAreaView.SplitArrangement?, awaitsHostView: Bool) {
        view.layoutSubtreeIfNeeded()
        for hostView in hostViews where hostView.superview !== webAreaView {
            hostView.frame = webAreaView.bounds
            webAreaView.addSubview(hostView, positioned: .below, relativeTo: nil)
        }
        webAreaView.splitArrangement = split
        webAreaView.layoutSubtreeIfNeeded()
        emptyStateView.isHidden = !hostViews.isEmpty || awaitsHostView
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

final class EmptyPageView: NSStackView {
    init() {
        let title = NSTextField(labelWithString: "Mini")
        title.font = .systemFont(ofSize: 28, weight: .semibold)
        title.textColor = .secondaryLabelColor
        let hint = NSTextField(labelWithString: "\u{2318}T to open a page")
        hint.font = .systemFont(ofSize: 13)
        hint.textColor = .tertiaryLabelColor
        super.init(frame: .zero)
        orientation = .vertical
        alignment = .centerX
        spacing = 6
        addArrangedSubview(title)
        addArrangedSubview(hint)
        isHidden = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }
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

    var spaceAccent: NSColor = .controlAccentColor {
        didSet {
            progressLine.accent = spaceAccent
            focusBorder.accent = spaceAccent
        }
    }

    private let divider = SplitDividerView()
    private let focusBorder = SplitFocusBorderView()
    private let progressLine = LoadingProgressLineView()
    private var splitDividerDetent = DetentEntry<SplitDividerDetent>()
    private var progressTabIdentifier: MiniTabId?
    private var progressFraction: CGFloat = 0

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        divider.isHidden = true
        focusBorder.isHidden = true
        progressLine.isHidden = true
        addSubview(progressLine)
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
            for subview in subviews where !isChrome(subview) && subview.frame != bounds {
                subview.frame = bounds
            }
            progressLine.frame = progressFrame(fraction: progressFraction)
            return
        }
        let leadingWidth = clampedLeadingWidth(fraction: splitArrangement.fraction)
        let leadingFrame = NSRect(x: 0, y: 0, width: leadingWidth, height: bounds.height)
        let trailingX = leadingWidth + Self.dividerWidth
        let trailingFrame = NSRect(x: trailingX, y: 0, width: max(0, bounds.width - trailingX), height: bounds.height)
        for subview in subviews where !isChrome(subview) {
            let frame = subview === splitArrangement.leading ? leadingFrame : subview === splitArrangement.trailing ? trailingFrame : bounds
            if subview.frame != frame {
                subview.frame = frame
            }
        }
        divider.frame = NSRect(x: leadingWidth, y: 0, width: Self.dividerWidth, height: bounds.height)
        focusBorder.frame = splitArrangement.focused === splitArrangement.leading ? leadingFrame : trailingFrame
        progressLine.frame = progressFrame(fraction: progressFraction)
    }

    private func isChrome(_ subview: NSView) -> Bool {
        subview === divider || subview === focusBorder || subview === progressLine
    }

    private func progressFrame(fraction: CGFloat) -> NSRect {
        let height = LoadingProgressLineView.thickness
        return NSRect(x: 0, y: isFlipped ? 0 : bounds.height - height, width: (bounds.width * fraction).rounded(), height: height)
    }

    func showLoadingProgress(of tab: Tab?) {
        let isSameTab = tab?.id == progressTabIdentifier
        progressTabIdentifier = tab?.id
        addSubview(progressLine, positioned: .above, relativeTo: nil)
        guard let tab, tab.isLoading, tab.loadingProgress < 1 else {
            finishLoadingProgress(animated: isSameTab && !progressLine.isHidden)
            return
        }
        let fraction = CGFloat(tab.loadingProgress)
        guard isSameTab, !progressLine.isHidden, fraction > progressFraction else {
            progressFraction = fraction
            progressLine.setGlowing(false)
            progressLine.alphaValue = 1
            progressLine.isHidden = false
            progressLine.frame = progressFrame(fraction: fraction)
            return
        }
        progressFraction = fraction
        progressLine.setGlowing(false)
        progressLine.alphaValue = 1
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.2
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            progressLine.animator().frame = progressFrame(fraction: fraction)
        }
    }

    private func finishLoadingProgress(animated: Bool) {
        guard animated else {
            progressFraction = 0
            progressLine.setGlowing(false)
            progressLine.isHidden = true
            return
        }
        progressFraction = 1
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.2
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            progressLine.animator().frame = progressFrame(fraction: 1)
        }, completionHandler: {
            MainActor.assumeIsolated {
                guard self.progressFraction == 1 else { return }
                self.progressLine.setGlowing(true)
                DispatchQueue.main.asyncAfter(deadline: .now() + LoadingProgressLineView.glowHold) {
                    MainActor.assumeIsolated {
                        guard self.progressFraction == 1 else { return }
                        self.progressLine.setGlowing(false)
                        NSAnimationContext.runAnimationGroup({ context in
                            context.duration = 0.25
                            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
                            self.progressLine.animator().alphaValue = 0
                        }, completionHandler: {
                            MainActor.assumeIsolated {
                                guard self.progressFraction == 1, self.progressLine.alphaValue == 0 else { return }
                                self.progressFraction = 0
                                self.progressLine.isHidden = true
                            }
                        })
                    }
                }
            }
        })
    }

    private var splitContentWidth: CGFloat { max(0, bounds.width - Self.dividerWidth) }

    private func clampedLeadingWidth(fraction: Double) -> CGFloat {
        let minimum = min(Self.minimumSplitSideWidth, splitContentWidth / 2)
        return (splitContentWidth * fraction).clamped(to: minimum...(splitContentWidth - minimum)).rounded()
    }

    private func dragDivider(to locationInWindow: NSPoint, finished: Bool) {
        guard let splitArrangement, splitContentWidth > 0 else { return }
        let rawWidth = convert(locationInWindow, from: nil).x - Self.dividerWidth / 2
        let x = SplitDividerDetent.snappedLeadingWidth(rawWidth, contentWidth: splitContentWidth)
        let detent = SplitDividerDetent.of(leadingWidth: x, contentWidth: splitContentWidth, minimum: min(Self.minimumSplitSideWidth, splitContentWidth / 2))
        if splitDividerDetent.update(detent) {
            detent == .center ? Haptics.splitSnappedToCenter() : Haptics.splitReachedMinimum()
        }
        if finished {
            splitDividerDetent = DetentEntry()
        }
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

final class LoadingProgressLineView: NSView {
    static let thickness: CGFloat = 2
    static let glowHold: TimeInterval = 0.15

    private var isGlowing = false

    func setGlowing(_ glowing: Bool) {
        guard glowing != isGlowing, let layer else { return }
        isGlowing = glowing
        layer.masksToBounds = false
        layer.shadowColor = accent.cgColor
        layer.shadowRadius = 3
        layer.shadowOffset = .zero
        let opacity: Float = glowing ? 0.9 : 0
        let animation = CABasicAnimation(keyPath: "shadowOpacity")
        animation.fromValue = layer.presentation()?.shadowOpacity ?? layer.shadowOpacity
        animation.duration = glowing ? 0.08 : 0.25
        layer.shadowOpacity = opacity
        layer.add(animation, forKey: "glow")
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

    var accent: NSColor = .controlAccentColor {
        didSet { needsDisplay = true }
    }

    override func updateLayer() {
        layer?.backgroundColor = accent.cgColor
    }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }
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

    var accent: NSColor = .controlAccentColor {
        didSet { needsDisplay = true }
    }

    override func updateLayer() {
        layer?.borderWidth = 2
        layer?.borderColor = accent.withAlphaComponent(0.7).cgColor
    }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
