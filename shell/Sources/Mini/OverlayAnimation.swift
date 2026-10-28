import AppKit

@MainActor
enum OverlayAnimation {
    private static var reducesMotion: Bool {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }

    static func appear(_ view: NSView) {
        view.alphaValue = 0
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.16
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            view.animator().alphaValue = 1
        }
        guard !reducesMotion else { return }
        view.superview?.layoutSubtreeIfNeeded()
        guard let layer = view.layer else { return }
        let bounds = view.bounds
        let scale: CGFloat = 0.96
        var transform = CATransform3DMakeTranslation(bounds.width * (1 - scale) / 2, bounds.height * (1 - scale) / 2, 0)
        transform = CATransform3DScale(transform, scale, scale, 1)
        let spring = CASpringAnimation(keyPath: "transform")
        spring.fromValue = NSValue(caTransform3D: transform)
        spring.toValue = NSValue(caTransform3D: CATransform3DIdentity)
        spring.damping = 22
        spring.stiffness = 340
        spring.duration = spring.settlingDuration
        layer.add(spring, forKey: "overlayAppear")
    }

    static func disappear(_ view: NSView, then finish: @escaping @MainActor () -> Void) {
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.12
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            view.animator().alphaValue = 0
        }, completionHandler: {
            MainActor.assumeIsolated {
                guard view.alphaValue == 0 else { return }
                finish()
            }
        })
    }
}
