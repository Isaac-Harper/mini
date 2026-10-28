import AppKit
import SwiftUI

@MainActor
final class PeekSidebarController {
    private unowned let shell: ShellController
    private let cluster: WindowControlsCluster
    private let edgeZone = HoverZoneView()
    private let panel = PeekPanelView()
    private let glassView = NSGlassEffectView()
    private var leadingConstraint: NSLayoutConstraint?
    private var widthConstraint: NSLayoutConstraint?
    private var isEnabled = false
    private(set) var isPeeking = false
    private var hideGeneration = 0

    private static let edgeWidth: CGFloat = 6
    private static let inset: CGFloat = 8
    private static let hideDelay: TimeInterval = 0.3
    private static let slideDuration: TimeInterval = 0.2

    init(shell: ShellController, cluster: WindowControlsCluster, rootView: NSView) {
        self.shell = shell
        self.cluster = cluster
        let hostingView = SidebarHostingView(rootView: SidebarView(shell: shell))
        hostingView.sizingOptions = []
        hostingView.translatesAutoresizingMaskIntoConstraints = false
        let content = NSView()
        content.addSubview(hostingView)
        glassView.contentView = content
        glassView.cornerRadius = 18
        glassView.translatesAutoresizingMaskIntoConstraints = false
        panel.translatesAutoresizingMaskIntoConstraints = false
        panel.addSubview(glassView)
        panel.isHidden = true
        panel.onHoverChange = { [weak self] inside in
            if inside { self?.cancelHide() } else { self?.scheduleHide() }
        }
        edgeZone.translatesAutoresizingMaskIntoConstraints = false
        edgeZone.isHidden = true
        edgeZone.onHoverChange = { [weak self] inside in
            if inside { self?.peek() } else { self?.scheduleHide() }
        }
        rootView.addSubview(panel)
        rootView.addSubview(edgeZone)
        let leading = panel.leadingAnchor.constraint(equalTo: rootView.leadingAnchor, constant: Self.inset)
        let width = panel.widthAnchor.constraint(equalToConstant: 240)
        leadingConstraint = leading
        widthConstraint = width
        NSLayoutConstraint.activate([
            leading, width,
            panel.topAnchor.constraint(equalTo: rootView.topAnchor, constant: Self.inset),
            panel.bottomAnchor.constraint(equalTo: rootView.bottomAnchor, constant: -Self.inset),
            glassView.leadingAnchor.constraint(equalTo: panel.leadingAnchor),
            glassView.trailingAnchor.constraint(equalTo: panel.trailingAnchor),
            glassView.topAnchor.constraint(equalTo: panel.topAnchor),
            glassView.bottomAnchor.constraint(equalTo: panel.bottomAnchor),
            hostingView.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            hostingView.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            hostingView.topAnchor.constraint(equalTo: content.topAnchor),
            hostingView.bottomAnchor.constraint(equalTo: content.bottomAnchor),
            edgeZone.leadingAnchor.constraint(equalTo: rootView.leadingAnchor),
            edgeZone.topAnchor.constraint(equalTo: rootView.topAnchor),
            edgeZone.bottomAnchor.constraint(equalTo: rootView.bottomAnchor),
            edgeZone.widthAnchor.constraint(equalToConstant: Self.edgeWidth),
        ])
    }

    func setEnabled(_ enabled: Bool, sidebarWidth: CGFloat) {
        isEnabled = enabled
        edgeZone.isHidden = !enabled
        widthConstraint?.constant = sidebarWidth
        if !enabled {
            hideGeneration += 1
            isPeeking = false
            panel.isHidden = true
        }
    }

    func peek() {
        guard isEnabled, !isPeeking else {
            cancelHide()
            return
        }
        guard NSEvent.pressedMouseButtons == 0, shell.sidebarDrag.draggedTab == nil else { return }
        isPeeking = true
        hideGeneration += 1
        guard let rootView = panel.superview, let leadingConstraint else { return }
        rootView.addSubview(panel, positioned: .above, relativeTo: nil)
        rootView.addSubview(edgeZone, positioned: .above, relativeTo: nil)
        cluster.setShownForPeek(true)
        panel.isHidden = false
        panel.alphaValue = 1
        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            leadingConstraint.constant = Self.inset
            OverlayAnimation.appear(panel)
            return
        }
        leadingConstraint.constant = -(widthConstraint?.constant ?? 240)
        rootView.layoutSubtreeIfNeeded()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = Self.slideDuration
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            context.allowsImplicitAnimation = true
            leadingConstraint.animator().constant = Self.inset
            rootView.layoutSubtreeIfNeeded()
        }
    }

    private func cancelHide() {
        hideGeneration += 1
    }

    private func scheduleHide() {
        guard isPeeking else { return }
        hideGeneration += 1
        let generation = hideGeneration
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.hideDelay) { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.hideGeneration == generation, self.isPeeking else { return }
                if NSEvent.pressedMouseButtons != 0 || self.shell.sidebarDrag.draggedTab != nil {
                    self.scheduleHide()
                    return
                }
                self.hide()
            }
        }
    }

    private func hide() {
        isPeeking = false
        cluster.setShownForPeek(false)
        guard let rootView = panel.superview, let leadingConstraint else { return }
        let finish: @MainActor () -> Void = { [weak self] in
            guard let self, !self.isPeeking else { return }
            self.panel.isHidden = true
        }
        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            OverlayAnimation.disappear(panel, then: finish)
            return
        }
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = Self.slideDuration
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            context.allowsImplicitAnimation = true
            leadingConstraint.animator().constant = -(widthConstraint?.constant ?? 240)
            rootView.layoutSubtreeIfNeeded()
        }, completionHandler: {
            MainActor.assumeIsolated { finish() }
        })
    }
}

final class PeekPanelView: NSView {
    var onHoverChange: ((Bool) -> Void)?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas { removeTrackingArea(area) }
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeInActiveApp, .inVisibleRect], owner: self))
    }

    override func mouseEntered(with event: NSEvent) { onHoverChange?(true) }

    override func mouseExited(with event: NSEvent) { onHoverChange?(false) }
}
