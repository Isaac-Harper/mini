import AppKit

@MainActor
final class WindowControlsCluster {
    private unowned let commands: ShellController
    private unowned let window: NSWindow
    private let hoverZone = HoverZoneView()
    private let glassView = NSGlassEffectView()
    private let backButton: HistoryButton
    private let forwardButton: HistoryButton
    private var isEnabled = false
    private var isRevealed = false
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

        let content = NSView()
        for (button, centerX) in [(toggle, 108.0), (backButton, 173.0), (forwardButton, 218.0)] as [(NSButton, CGFloat)] {
            button.translatesAutoresizingMaskIntoConstraints = false
            content.addSubview(button)
            NSLayoutConstraint.activate([
                button.centerXAnchor.constraint(equalTo: content.leadingAnchor, constant: centerX - Self.frame.minX),
                button.centerYAnchor.constraint(equalTo: content.centerYAnchor),
                button.widthAnchor.constraint(equalToConstant: 32),
                button.heightAnchor.constraint(equalToConstant: 28),
            ])
        }
        glassView.contentView = content
        glassView.cornerRadius = Self.frame.height / 2
        glassView.translatesAutoresizingMaskIntoConstraints = false
        glassView.isHidden = true
        hoverZone.translatesAutoresizingMaskIntoConstraints = false
        hoverZone.onHoverChange = { [weak self] inside in
            if inside { self?.reveal() } else { self?.scheduleHide() }
        }
        rootView.addSubview(glassView)
        rootView.addSubview(hoverZone)
        NSLayoutConstraint.activate([
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
        glassView.isHidden = true
        glassView.alphaValue = 1
        setTrafficLightsHidden(enabled)
    }

    func reveal() {
        guard isEnabled else { return }
        hideGeneration += 1
        backButton.isEnabled = commands.selectedTabCanGoBack
        forwardButton.isEnabled = commands.selectedTabCanGoForward
        guard !isRevealed else { return }
        isRevealed = true
        glassView.superview?.addSubview(glassView, positioned: .above, relativeTo: nil)
        hoverZone.superview?.addSubview(hoverZone, positioned: .above, relativeTo: nil)
        glassView.isHidden = false
        setTrafficLightsHidden(false)
        OverlayAnimation.appear(glassView)
    }

    private func scheduleHide() {
        hideGeneration += 1
        let generation = hideGeneration
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.hideDelay) { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.hideGeneration == generation, self.isRevealed else { return }
                self.isRevealed = false
                self.setTrafficLightsHidden(true)
                OverlayAnimation.disappear(self.glassView) { [weak self] in
                    guard let self, !self.isRevealed else { return }
                    self.glassView.isHidden = true
                }
            }
        }
    }

    private func setTrafficLightsHidden(_ hidden: Bool) {
        for type in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
            window.standardWindowButton(type)?.isHidden = hidden
        }
    }

    private static func button(_ label: String, _ symbolName: String, _ action: Selector, commands: ShellController) -> NSButton {
        guard let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: label) else {
            preconditionFailure("Missing SF Symbol \(symbolName)")
        }
        let button = NSButton(image: image, target: commands, action: action)
        button.isBordered = false
        button.toolTip = label
        button.contentTintColor = .secondaryLabelColor
        button.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 15, weight: .regular)
        return button
    }

    private static func historyButton(_ label: String, _ symbolName: String, _ action: Selector, commands: ShellController, forward: Bool) -> HistoryButton {
        guard let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: label) else {
            preconditionFailure("Missing SF Symbol \(symbolName)")
        }
        let button = HistoryButton(image: image, target: commands, action: action)
        button.isBordered = false
        button.toolTip = label
        button.contentTintColor = .secondaryLabelColor
        button.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 15, weight: .regular)
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
