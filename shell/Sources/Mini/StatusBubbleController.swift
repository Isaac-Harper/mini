import AppKit

@MainActor
final class StatusBubbleController {
    private unowned let shell: ShellController
    private let webAreaView: WebAreaView
    private let glassView = NSGlassEffectView()
    private let label = NSTextField(labelWithString: "")
    private let leadingConstraint: NSLayoutConstraint
    private let trailingConstraint: NSLayoutConstraint
    private var hideGeneration = 0
    private var isShowing = false

    private static let inset: CGFloat = 8
    private static let height: CGFloat = 24
    private static let horizontalPadding: CGFloat = 10
    private static let hideDelay: TimeInterval = 0.25
    private static let pointerMargin: CGFloat = 24

    init(shell: ShellController, windowController: MainWindowController) {
        self.shell = shell
        webAreaView = windowController.webAreaView
        label.font = .systemFont(ofSize: 12)
        label.textColor = .secondaryLabelColor
        label.lineBreakMode = .byTruncatingMiddle
        label.translatesAutoresizingMaskIntoConstraints = false
        let content = NSView()
        content.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(label)
        glassView.contentView = content
        glassView.cornerRadius = Self.height / 2
        glassView.translatesAutoresizingMaskIntoConstraints = false
        glassView.isHidden = true
        windowController.rootView.addSubview(glassView)
        leadingConstraint = glassView.leadingAnchor.constraint(equalTo: webAreaView.leadingAnchor, constant: Self.inset)
        trailingConstraint = glassView.trailingAnchor.constraint(equalTo: webAreaView.trailingAnchor, constant: -Self.inset)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: Self.horizontalPadding),
            label.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -Self.horizontalPadding),
            label.centerYAnchor.constraint(equalTo: content.centerYAnchor),
            content.leadingAnchor.constraint(equalTo: glassView.leadingAnchor),
            content.trailingAnchor.constraint(equalTo: glassView.trailingAnchor),
            content.topAnchor.constraint(equalTo: glassView.topAnchor),
            content.bottomAnchor.constraint(equalTo: glassView.bottomAnchor),
            glassView.heightAnchor.constraint(equalToConstant: Self.height),
            glassView.bottomAnchor.constraint(equalTo: webAreaView.bottomAnchor, constant: -Self.inset),
            glassView.widthAnchor.constraint(lessThanOrEqualTo: webAreaView.widthAnchor, multiplier: 0.5),
            leadingConstraint,
        ])
    }

    func statusChanged(for tab: Tab, text: String) {
        guard shell.displayedTabs.contains(where: { $0 === tab }) else { return }
        guard !text.isEmpty else {
            scheduleHide()
            return
        }
        hideGeneration += 1
        label.stringValue = text
        placeAwayFromPointer()
        glassView.superview?.addSubview(glassView)
        glassView.isHidden = false
        if !isShowing {
            isShowing = true
            glassView.alphaValue = 0
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.12
                glassView.animator().alphaValue = 1
            }
        } else {
            glassView.alphaValue = 1
        }
    }

    func hide() {
        hideGeneration += 1
        isShowing = false
        glassView.isHidden = true
    }

    private func scheduleHide() {
        guard isShowing else { return }
        hideGeneration += 1
        let generation = hideGeneration
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.hideDelay) { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.hideGeneration == generation else { return }
                self.isShowing = false
                NSAnimationContext.runAnimationGroup({ context in
                    context.duration = 0.15
                    self.glassView.animator().alphaValue = 0
                }, completionHandler: {
                    MainActor.assumeIsolated {
                        guard self.hideGeneration == generation else { return }
                        self.glassView.isHidden = true
                    }
                })
            }
        }
    }

    private func placeAwayFromPointer() {
        guard let window = webAreaView.window else { return }
        let pointer = webAreaView.convert(window.mouseLocationOutsideOfEventStream, from: nil)
        let width = min(label.intrinsicContentSize.width + Self.horizontalPadding * 2, webAreaView.bounds.width / 2)
        let bubbleTop = Self.inset + Self.height + Self.pointerMargin
        let nearLeading = pointer.x < Self.inset + width + Self.pointerMargin && pointer.y < bubbleTop
        leadingConstraint.isActive = !nearLeading
        trailingConstraint.isActive = nearLeading
    }
}
