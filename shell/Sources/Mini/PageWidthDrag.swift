import AppKit
import MiniRules

@MainActor
final class PageWidthDrag {
    static let zoneWidth: CGFloat = 10
    static let labelVisibleDuration: TimeInterval = 1
    static let restoreDuration: TimeInterval = 0.3

    private unowned let shell: ShellController
    private let content: WebContentViewController
    private let zone = PageWidthEdgeView()
    private let labelGlass = NSGlassEffectView()
    private let label = NSTextField(labelWithString: "")
    private var tab: Tab?
    private var detent = DetentEntry<Double>()
    private var labelGeneration = 0
    private var restoreGeneration = 0

    init(shell: ShellController, windowController: MainWindowController) {
        self.shell = shell
        content = windowController.webContentController
        let rootView = windowController.rootView
        zone.translatesAutoresizingMaskIntoConstraints = false
        zone.isHidden = true
        rootView.addSubview(zone, positioned: .above, relativeTo: content.cardView)
        NSLayoutConstraint.activate([
            zone.centerXAnchor.constraint(equalTo: content.cardView.trailingAnchor),
            zone.widthAnchor.constraint(equalToConstant: Self.zoneWidth),
            zone.topAnchor.constraint(equalTo: content.cardView.topAnchor),
            zone.bottomAnchor.constraint(equalTo: content.cardView.bottomAnchor),
        ])
        label.textColor = .secondaryLabelColor
        label.alignment = .center
        let labelContent = PageWidthLabelView()
        labelContent.addSubview(label)
        labelGlass.contentView = labelContent
        labelGlass.isHidden = true
        rootView.addSubview(labelGlass, positioned: .above, relativeTo: zone)
        zone.onDragBegan = { [weak self] in self?.beginDrag() }
        zone.onDrag = { [weak self] locationInWindow, finished in self?.drag(to: locationInWindow, finished: finished) }
        zone.onRestore = { [weak self] in self?.restoreFullWidth() }
        labelContent.onRestore = { [weak self] in self?.restoreFullWidth() }
        zone.isNarrowed = { [weak self] in self?.tab?.pageWidth != nil }
    }

    func update(tab: Tab?) {
        if tab !== self.tab {
            hideLabel()
        }
        self.tab = tab
        zone.isHidden = tab == nil
        restoreGeneration += 1
        apply(tab?.pageWidth)
    }

    private var fullWidth: CGFloat { content.pageArea.frame.width }

    private func apply(_ width: CGFloat?) {
        let displayed = PageWidth.displayed(width.map(Double.init), fullWidth: Double(fullWidth))
        content.narrowWidthConstraint.constant = displayed.map { CGFloat($0) } ?? fullWidth
        content.narrowWidthConstraint.isActive = displayed != nil
        content.view.layoutSubtreeIfNeeded()
    }

    private func beginDrag() {
        detent = DetentEntry()
        _ = detent.update(PageWidth.detent(at: tab?.pageWidth.map(Double.init)))
    }

    private func drag(to locationInWindow: NSPoint, finished: Bool) {
        guard let tab, fullWidth > 0 else { return }
        restoreGeneration += 1
        let pointer = content.view.convert(locationInWindow, from: nil).x
        let dragged = PageWidth.dragged(to: Double(2 * (pointer - content.pageArea.frame.midX)), fullWidth: Double(fullWidth))
        if detent.update(PageWidth.detent(at: dragged)) {
            Haptics.pageWidthReachedDetent()
        }
        tab.pageWidth = dragged.map { CGFloat($0) }
        apply(tab.pageWidth)
        showLabel(width: tab.pageWidth ?? fullWidth, holds: !finished)
    }

    private func restoreFullWidth() {
        guard let tab, tab.pageWidth != nil else { return }
        tab.pageWidth = nil
        hideLabel()
        guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else {
            apply(nil)
            return
        }
        restoreGeneration += 1
        let generation = restoreGeneration
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = Self.restoreDuration
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            context.allowsImplicitAnimation = true
            content.narrowWidthConstraint.animator().constant = fullWidth
            content.view.layoutSubtreeIfNeeded()
        }, completionHandler: {
            MainActor.assumeIsolated {
                guard self.restoreGeneration == generation else { return }
                self.apply(nil)
            }
        })
    }

    private func showLabel(width: CGFloat, holds: Bool) {
        labelGeneration += 1
        let generation = labelGeneration
        label.font = .monospacedDigitSystemFont(ofSize: InterfaceScale.scaled(11), weight: .medium)
        label.stringValue = String(Int(width.rounded()))
        label.sizeToFit()
        let height = OverlayMetrics.tooltipHeight
        let size = NSSize(width: max(height * 1.6, label.frame.width + 2 * OverlayMetrics.tooltipPadding), height: height)
        let card = content.cardView.frame
        let gap = OverlayMetrics.tooltipPadding
        let outsideX = card.maxX + gap
        let x = outsideX + size.width <= content.pageArea.frame.maxX + WebContentViewController.cardInset ? outsideX : card.maxX - gap - size.width
        labelGlass.frame = NSRect(x: x, y: card.midY - size.height / 2, width: size.width, height: size.height).integral
        labelGlass.cornerRadius = size.height / 2
        label.frame = NSRect(x: 0, y: (size.height - label.frame.height) / 2, width: size.width, height: label.frame.height)
        labelGlass.alphaValue = 1
        labelGlass.isHidden = false
        guard !holds else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.labelVisibleDuration) { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.labelGeneration == generation else { return }
                NSAnimationContext.runAnimationGroup({ context in
                    context.duration = 0.2
                    self.labelGlass.animator().alphaValue = 0
                }, completionHandler: {
                    MainActor.assumeIsolated {
                        guard self.labelGeneration == generation else { return }
                        self.labelGlass.isHidden = true
                    }
                })
            }
        }
    }

    private func hideLabel() {
        labelGeneration += 1
        labelGlass.isHidden = true
    }
}

final class PageWidthEdgeView: NSView {
    var onDragBegan: (() -> Void)?
    var onDrag: ((NSPoint, Bool) -> Void)?
    var onRestore: (() -> Void)?
    var isNarrowed: (() -> Bool)?
    private var isPointerInside = false
    private var flagsMonitor: Any?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas { removeTrackingArea(area) }
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .mouseMoved, .cursorUpdate, .activeInKeyWindow, .inVisibleRect], owner: self))
    }

    private var isOptionHeld: Bool {
        NSApp.currentEvent?.modifierFlags.contains(.option) ?? NSEvent.modifierFlags.contains(.option)
    }

    private func responds(at localPoint: NSPoint) -> Bool {
        isOptionHeld || (isNarrowed?() == true && localPoint.x >= bounds.midX)
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard !isHidden, let superview else { return nil }
        let local = convert(point, from: superview)
        return bounds.contains(local) && responds(at: local) ? self : nil
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    private func refreshCursor(_ event: NSEvent) {
        if isPointerInside, responds(at: convert(event.locationInWindow, from: nil)) {
            NSCursor.resizeLeftRight.set()
        }
    }

    override func cursorUpdate(with event: NSEvent) {
        refreshCursor(event)
    }

    override func mouseMoved(with event: NSEvent) {
        refreshCursor(event)
    }

    override func mouseEntered(with event: NSEvent) {
        isPointerInside = true
        refreshCursor(event)
        flagsMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            MainActor.assumeIsolated {
                guard let self else { return }
                if self.responds(at: self.convert(event.locationInWindow, from: nil)) {
                    NSCursor.resizeLeftRight.set()
                } else {
                    NSCursor.arrow.set()
                }
            }
            return event
        }
    }

    override func mouseExited(with event: NSEvent) {
        isPointerInside = false
        if let flagsMonitor {
            NSEvent.removeMonitor(flagsMonitor)
            self.flagsMonitor = nil
        }
    }

    override func mouseDown(with event: NSEvent) {
        guard event.clickCount < 2 else {
            onRestore?()
            return
        }
        guard let window else { return }
        onDragBegan?()
        var moved = false
        window.trackEvents(matching: [.leftMouseDragged, .leftMouseUp], timeout: NSEvent.foreverDuration, mode: .eventTracking) { trackedEvent, stop in
            guard let trackedEvent else { return }
            let finished = trackedEvent.type == .leftMouseUp
            moved = moved || !finished
            if moved { onDrag?(trackedEvent.locationInWindow, finished) }
            if finished { stop.pointee = true }
        }
    }
}

final class PageWidthLabelView: NSView {
    var onRestore: (() -> Void)?

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        if event.clickCount == 2 { onRestore?() }
    }
}
