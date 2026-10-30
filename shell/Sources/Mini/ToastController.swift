import AppKit

@MainActor
final class ToastController {
    private let glassView = NSGlassEffectView()
    private let messageContent = NSView()
    private let label = NSTextField(labelWithString: "")
    private var generation = 0
    private var leadingInset: NSLayoutConstraint!
    private var trailingInset: NSLayoutConstraint!
    private var height: NSLayoutConstraint!
    private var contentEdges: [NSLayoutConstraint] = []

    private static let visibleDuration: TimeInterval = 1.2

    init(windowController: MainWindowController) {
        label.translatesAutoresizingMaskIntoConstraints = false
        messageContent.translatesAutoresizingMaskIntoConstraints = false
        messageContent.addSubview(label)
        glassView.translatesAutoresizingMaskIntoConstraints = false
        glassView.isHidden = true
        let webAreaView = windowController.webAreaView
        windowController.rootView.addSubview(glassView)
        leadingInset = label.leadingAnchor.constraint(equalTo: messageContent.leadingAnchor)
        trailingInset = label.trailingAnchor.constraint(equalTo: messageContent.trailingAnchor)
        height = glassView.heightAnchor.constraint(equalToConstant: OverlayMetrics.toastHeight)
        NSLayoutConstraint.activate([
            leadingInset,
            trailingInset,
            height,
            label.centerYAnchor.constraint(equalTo: messageContent.centerYAnchor),
            glassView.centerXAnchor.constraint(equalTo: webAreaView.centerXAnchor),
            glassView.bottomAnchor.constraint(equalTo: webAreaView.bottomAnchor, constant: -24),
        ])
    }

    func show(_ message: String) {
        label.stringValue = message
        label.font = InterfaceFont.toast
        leadingInset.constant = OverlayMetrics.toastPadding
        trailingInset.constant = -OverlayMetrics.toastPadding
        height.constant = OverlayMetrics.toastHeight
        height.isActive = true
        present(messageContent, cornerRadius: OverlayMetrics.toastHeight / 2, duration: Self.visibleDuration)
    }

    func show(card: NSView, cornerRadius: CGFloat, duration: TimeInterval) {
        height.isActive = false
        card.translatesAutoresizingMaskIntoConstraints = false
        present(card, cornerRadius: cornerRadius, duration: duration)
    }

    private func present(_ content: NSView, cornerRadius: CGFloat, duration: TimeInterval) {
        generation += 1
        let shownGeneration = generation
        if glassView.contentView !== content {
            NSLayoutConstraint.deactivate(contentEdges)
            glassView.contentView = content
            contentEdges = [
                content.leadingAnchor.constraint(equalTo: glassView.leadingAnchor),
                content.trailingAnchor.constraint(equalTo: glassView.trailingAnchor),
                content.topAnchor.constraint(equalTo: glassView.topAnchor),
                content.bottomAnchor.constraint(equalTo: glassView.bottomAnchor),
            ]
            NSLayoutConstraint.activate(contentEdges)
        }
        glassView.cornerRadius = cornerRadius
        glassView.superview?.addSubview(glassView)
        glassView.isHidden = false
        OverlayAnimation.appear(glassView)
        scheduleDismissal(of: shownGeneration, after: duration)
    }

    private var holdsCard: Bool {
        guard let window = glassView.window, !glassView.isHidden, glassView.contentView !== messageContent else { return false }
        if NSEvent.pressedMouseButtons & 1 != 0 { return true }
        let location = glassView.convert(window.mouseLocationOutsideOfEventStream, from: nil)
        return glassView.bounds.contains(location)
    }

    private func scheduleDismissal(of shownGeneration: Int, after duration: TimeInterval) {
        DispatchQueue.main.asyncAfter(deadline: .now() + duration) { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.generation == shownGeneration else { return }
                if self.holdsCard {
                    self.scheduleDismissal(of: shownGeneration, after: 0.5)
                    return
                }
                OverlayAnimation.disappear(self.glassView) { [weak self] in
                    guard let self, self.generation == shownGeneration else { return }
                    self.glassView.isHidden = true
                }
            }
        }
    }
}
