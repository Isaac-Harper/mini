import AppKit
import SwiftUI

@MainActor
final class GlassTooltip {
    static let shared = GlassTooltip()

    private let panel: NSPanel
    private let glassView = NSGlassEffectView()
    private let label = NSTextField(labelWithString: "")
    private var showTimer: Timer?
    private weak var anchor: NSView?
    private weak var suppressedAnchor: NSView?
    private var isVisible = false
    private var hiddenAt = -TimeInterval.infinity
    private var dismissMonitor: Any?
    private var leadingInset: NSLayoutConstraint!
    private var trailingInset: NSLayoutConstraint!

    private static let initialDelay: TimeInterval = 0.6
    private static let neighborInterval: TimeInterval = 0.5
    private static let gap: CGFloat = 4
    private static let edgeMargin: CGFloat = 8
    private static let maximumWidth: CGFloat = 420

    private init() {
        panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.isReleasedWhenClosed = false
        panel.animationBehavior = .none
        label.textColor = .labelColor
        label.lineBreakMode = .byTruncatingMiddle
        label.maximumNumberOfLines = 1
        label.translatesAutoresizingMaskIntoConstraints = false
        let content = NSView()
        content.addSubview(label)
        leadingInset = label.leadingAnchor.constraint(equalTo: content.leadingAnchor)
        trailingInset = label.trailingAnchor.constraint(equalTo: content.trailingAnchor)
        NSLayoutConstraint.activate([leadingInset, trailingInset, label.centerYAnchor.constraint(equalTo: content.centerYAnchor)])
        glassView.contentView = content
        panel.contentView = glassView
    }

    func hoverBegan(over view: NSView, text: String) {
        guard !text.isEmpty, view !== suppressedAnchor else { return }
        showTimer?.invalidate()
        anchor = view
        let isNeighbor = isVisible || ProcessInfo.processInfo.systemUptime - hiddenAt < Self.neighborInterval
        if isNeighbor {
            show(text, below: view)
            return
        }
        let timer = Timer(timeInterval: Self.initialDelay, repeats: false) { [weak self, weak view] _ in
            MainActor.assumeIsolated {
                guard let self, let view, self.anchor === view else { return }
                let current = (view as? TooltipText)?.tooltipText ?? text
                guard !current.isEmpty else { return }
                self.show(current, below: view)
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        showTimer = timer
    }

    func hoverEnded(over view: NSView) {
        if suppressedAnchor === view { suppressedAnchor = nil }
        guard anchor === view else { return }
        showTimer?.invalidate()
        showTimer = nil
        anchor = nil
        hide()
    }

    func textChanged(for view: NSView, to text: String) {
        guard anchor === view, isVisible else { return }
        if text.isEmpty {
            hide()
        } else {
            show(text, below: view)
        }
    }

    func show(_ text: String, below view: NSView) {
        guard let window = view.window else { return }
        anchor = view
        label.stringValue = text
        label.font = InterfaceFont.tooltip
        leadingInset.constant = OverlayMetrics.tooltipPadding
        trailingInset.constant = -OverlayMetrics.tooltipPadding
        glassView.cornerRadius = SidebarMetrics.rowCornerRadius
        let height = OverlayMetrics.tooltipHeight
        let width = min(Self.maximumWidth, ceil(label.intrinsicContentSize.width) + OverlayMetrics.tooltipPadding * 2)
        let anchorFrame = window.convertToScreen(view.convert(view.bounds, to: nil))
        var origin = NSPoint(x: anchorFrame.midX - width / 2, y: anchorFrame.minY - Self.gap - height)
        let bounds = window.frame.insetBy(dx: Self.edgeMargin, dy: 0)
        origin.x = min(max(origin.x, bounds.minX), bounds.maxX - width)
        if let screen = window.screen ?? NSScreen.main, origin.y < screen.visibleFrame.minY {
            origin.y = anchorFrame.maxY + Self.gap
        }
        panel.appearance = window.effectiveAppearance
        panel.setFrame(NSRect(origin: origin, size: NSSize(width: width, height: height)), display: true)
        if panel.parent !== window {
            panel.parent?.removeChildWindow(panel)
            window.addChildWindow(panel, ordered: .above)
        }
        if !isVisible {
            isVisible = true
            panel.alphaValue = 0
            panel.orderFront(nil)
            NSAnimationContext.runAnimationGroup { context in
                context.duration = HoverStyle.fadeIn
                panel.animator().alphaValue = 1
            }
        }
        startDismissMonitor()
    }

    func hide() {
        guard isVisible else { return }
        isVisible = false
        hiddenAt = ProcessInfo.processInfo.systemUptime
        stopDismissMonitor()
        panel.parent?.removeChildWindow(panel)
        panel.orderOut(nil)
    }

    var windowNumber: Int { panel.windowNumber }

    private func startDismissMonitor() {
        guard dismissMonitor == nil else { return }
        dismissMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown, .keyDown, .scrollWheel]) { [weak self] event in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.suppressedAnchor = self.anchor
                self.showTimer?.invalidate()
                self.hide()
                self.hiddenAt = -TimeInterval.infinity
            }
            return event
        }
    }

    private func stopDismissMonitor() {
        if let dismissMonitor { NSEvent.removeMonitor(dismissMonitor) }
        dismissMonitor = nil
    }
}

@MainActor
protocol TooltipText: AnyObject {
    var tooltipText: String { get }
}

final class TooltipAnchorView: NSView, TooltipText {
    var tooltipText = "" {
        didSet {
            guard tooltipText != oldValue else { return }
            setAccessibilityHelp(tooltipText.isEmpty ? nil : tooltipText)
            GlassTooltip.shared.textChanged(for: self, to: tooltipText)
        }
    }

    private var trackingArea: NSTrackingArea?

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea { removeTrackingArea(trackingArea) }
        let area = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeInActiveApp, .inVisibleRect], owner: self)
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        GlassTooltip.shared.hoverBegan(over: self, text: tooltipText)
    }

    override func mouseExited(with event: NSEvent) {
        GlassTooltip.shared.hoverEnded(over: self)
    }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        super.viewWillMove(toWindow: newWindow)
        if newWindow == nil { GlassTooltip.shared.hoverEnded(over: self) }
    }
}

private struct TooltipAnchor: NSViewRepresentable {
    let text: String

    func makeNSView(context: Context) -> TooltipAnchorView {
        let view = TooltipAnchorView()
        view.tooltipText = text
        return view
    }

    func updateNSView(_ view: TooltipAnchorView, context: Context) {
        view.tooltipText = text
    }
}

extension View {
    func glassTooltip(_ text: String) -> some View {
        background { TooltipAnchor(text: text) }
            .accessibilityHint(text)
    }
}
