import AppKit

@MainActor
final class ToastController {
    private let glassView = NSGlassEffectView()
    private let label = NSTextField(labelWithString: "")
    private var generation = 0
    private var leadingInset: NSLayoutConstraint!
    private var trailingInset: NSLayoutConstraint!
    private var height: NSLayoutConstraint!

    private static let visibleDuration: TimeInterval = 1.2

    init(windowController: MainWindowController) {
        label.translatesAutoresizingMaskIntoConstraints = false
        let content = NSView()
        content.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(label)
        glassView.contentView = content
        glassView.translatesAutoresizingMaskIntoConstraints = false
        glassView.isHidden = true
        let webAreaView = windowController.webAreaView
        windowController.rootView.addSubview(glassView)
        leadingInset = label.leadingAnchor.constraint(equalTo: content.leadingAnchor)
        trailingInset = label.trailingAnchor.constraint(equalTo: content.trailingAnchor)
        height = glassView.heightAnchor.constraint(equalToConstant: OverlayMetrics.toastHeight)
        NSLayoutConstraint.activate([
            leadingInset,
            trailingInset,
            height,
            label.centerYAnchor.constraint(equalTo: content.centerYAnchor),
            content.leadingAnchor.constraint(equalTo: glassView.leadingAnchor),
            content.trailingAnchor.constraint(equalTo: glassView.trailingAnchor),
            content.topAnchor.constraint(equalTo: glassView.topAnchor),
            content.bottomAnchor.constraint(equalTo: glassView.bottomAnchor),
            glassView.centerXAnchor.constraint(equalTo: webAreaView.centerXAnchor),
            glassView.bottomAnchor.constraint(equalTo: webAreaView.bottomAnchor, constant: -24),
        ])
    }

    func show(_ message: String) {
        generation += 1
        let shownGeneration = generation
        label.stringValue = message
        label.font = InterfaceFont.toast
        leadingInset.constant = OverlayMetrics.toastPadding
        trailingInset.constant = -OverlayMetrics.toastPadding
        height.constant = OverlayMetrics.toastHeight
        glassView.cornerRadius = OverlayMetrics.toastHeight / 2
        glassView.superview?.addSubview(glassView)
        glassView.isHidden = false
        OverlayAnimation.appear(glassView)
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.visibleDuration) { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.generation == shownGeneration else { return }
                OverlayAnimation.disappear(self.glassView) { [weak self] in
                    guard let self, self.generation == shownGeneration else { return }
                    self.glassView.isHidden = true
                }
            }
        }
    }
}
