import AppKit

@MainActor
final class WindowControlsCluster {
    private unowned let commands: ShellController
    private unowned let window: NSWindow
    private let hoverZone = HoverZoneView()
    private let glassView = NSGlassEffectView()
    private let controlsView = NSView()
    private let backButton: HistoryButton
    private let forwardButton: HistoryButton
    private var isEnabled = false
    private var isRevealed = false
    private var isShownForPeek = false
    private var hideGeneration = 0

    private static let hideDelay: TimeInterval = 1
    private static let frame = NSRect(x: 8, y: 8, width: 244, height: 36)
    private static let hoverSize = NSSize(width: 268, height: 56)

    init(commands: ShellController, window: NSWindow, rootView: NSView) {
        self.commands = commands
        self.window = window
        backButton = Self.historyButton("Back", "chevron.left", #selector(ShellController.goBackInHistory(_:)), commands: commands, forward: false)
        forwardButton = Self.historyButton("Forward", "chevron.right", #selector(ShellController.goForwardInHistory(_:)), commands: commands, forward: true)
        let toggle = Self.button("Show Sidebar", "sidebar.left", #selector(ShellController.toggleTabSidebar(_:)), commands: commands)

        let content = controlsView
        for (button, centerX) in [(toggle, 108.0), (backButton, 173.0), (forwardButton, 218.0)] as [(NSButton, CGFloat)] {
            button.translatesAutoresizingMaskIntoConstraints = false
            content.addSubview(button)
            NSLayoutConstraint.activate([
                button.centerXAnchor.constraint(equalTo: content.leadingAnchor, constant: centerX - Self.frame.minX),
                button.centerYAnchor.constraint(equalTo: content.centerYAnchor),
            ])
        }
        glassView.cornerRadius = Self.frame.height / 2
        glassView.translatesAutoresizingMaskIntoConstraints = false
        glassView.isHidden = true
        controlsView.translatesAutoresizingMaskIntoConstraints = false
        controlsView.isHidden = true
        hoverZone.translatesAutoresizingMaskIntoConstraints = false
        hoverZone.onHoverChange = { [weak self] inside in
            if inside { self?.reveal() } else { self?.scheduleHide() }
        }
        rootView.addSubview(glassView)
        rootView.addSubview(controlsView)
        rootView.addSubview(hoverZone)
        NSLayoutConstraint.activate([
            controlsView.leadingAnchor.constraint(equalTo: glassView.leadingAnchor),
            controlsView.trailingAnchor.constraint(equalTo: glassView.trailingAnchor),
            controlsView.topAnchor.constraint(equalTo: glassView.topAnchor),
            controlsView.bottomAnchor.constraint(equalTo: glassView.bottomAnchor),
            glassView.leadingAnchor.constraint(equalTo: rootView.leadingAnchor, constant: Self.frame.minX),
            glassView.topAnchor.constraint(equalTo: rootView.topAnchor, constant: Self.frame.minY),
            glassView.widthAnchor.constraint(equalToConstant: Self.frame.width),
            glassView.heightAnchor.constraint(equalToConstant: Self.frame.height),
            hoverZone.leadingAnchor.constraint(equalTo: rootView.leadingAnchor),
            hoverZone.topAnchor.constraint(equalTo: rootView.topAnchor),
            hoverZone.widthAnchor.constraint(equalToConstant: Self.hoverSize.width),
            hoverZone.heightAnchor.constraint(equalToConstant: Self.hoverSize.height),
        ])
        hoverZone.isHidden = true
    }

    func setEnabled(_ enabled: Bool) {
        isEnabled = enabled
        hoverZone.isHidden = !enabled
        hideGeneration += 1
        isRevealed = false
        isShownForPeek = false
        glassView.isHidden = true
        glassView.alphaValue = 1
        controlsView.isHidden = true
        controlsView.alphaValue = 1
        setTrafficLightsHidden(enabled)
    }

    func reveal() {
        guard isEnabled, !isShownForPeek else { return }
        hideGeneration += 1
        updateHistoryButtons()
        guard !isRevealed else { return }
        isRevealed = true
        bringToFront()
        glassView.isHidden = false
        controlsView.isHidden = false
        setTrafficLightsHidden(false)
        OverlayAnimation.appear(glassView)
        OverlayAnimation.appear(controlsView)
    }

    func setShownForPeek(_ shown: Bool) {
        guard isEnabled, shown != isShownForPeek else { return }
        isShownForPeek = shown
        hideGeneration += 1
        isRevealed = false
        glassView.isHidden = true
        controlsView.alphaValue = 1
        controlsView.isHidden = !shown
        setTrafficLightsHidden(!shown)
        if shown {
            updateHistoryButtons()
            bringToFront()
        }
    }

    private func updateHistoryButtons() {
        backButton.isEnabled = commands.selectedTabCanGoBack
        forwardButton.isEnabled = commands.selectedTabCanGoForward
    }

    private func bringToFront() {
        guard let rootView = glassView.superview else { return }
        for view in [glassView, controlsView, hoverZone] {
            rootView.addSubview(view, positioned: .above, relativeTo: nil)
        }
    }

    private func scheduleHide() {
        hideGeneration += 1
        let generation = hideGeneration
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.hideDelay) { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.hideGeneration == generation, self.isRevealed else { return }
                self.isRevealed = false
                self.setTrafficLightsHidden(true)
                OverlayAnimation.disappear(self.controlsView) {}
                OverlayAnimation.disappear(self.glassView) { [weak self] in
                    guard let self, !self.isRevealed, !self.isShownForPeek else { return }
                    self.glassView.isHidden = true
                    self.controlsView.isHidden = true
                }
            }
        }
    }

    private func setTrafficLightsHidden(_ hidden: Bool) {
        for type in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
            window.standardWindowButton(type)?.isHidden = hidden
        }
    }

    private static func button(_ label: String, _ symbolName: String, _ action: Selector, commands: ShellController) -> HoverHighlightButton {
        guard let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: label) else {
            preconditionFailure("Missing SF Symbol \(symbolName)")
        }
        let button = HoverHighlightButton(image: image, target: commands, action: action)
        button.feedback = .toggle
        WindowToolbar.style(button, label, commands: commands)
        return button
    }

    private static func historyButton(_ label: String, _ symbolName: String, _ action: Selector, commands: ShellController, forward: Bool) -> HistoryButton {
        guard let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: label) else {
            preconditionFailure("Missing SF Symbol \(symbolName)")
        }
        let button = HistoryButton(image: image, target: commands, action: action)
        WindowToolbar.style(button, label, commands: commands)
        button.menuProvider = { [unowned commands] in commands.historyMenu(forward: forward) }
        return button
    }
}

final class HoverZoneView: NSView {
    var onHoverChange: ((Bool) -> Void)?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas { removeTrackingArea(area) }
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeInActiveApp, .inVisibleRect], owner: self))
    }

    override func mouseEntered(with event: NSEvent) { onHoverChange?(true) }

    override func mouseExited(with event: NSEvent) { onHoverChange?(false) }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}
