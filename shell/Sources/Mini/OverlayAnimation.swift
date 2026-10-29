import AppKit

@MainActor
enum OverlayAnimation {
    private static var reducesMotion: Bool {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }

    static func appear(_ view: NSView, scale: CGFloat = 0.96, blurring blurredView: NSView? = nil) {
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
        var transform = CATransform3DMakeTranslation(bounds.width * (1 - scale) / 2, bounds.height * (1 - scale) / 2, 0)
        transform = CATransform3DScale(transform, scale, scale, 1)
        let spring = CASpringAnimation(keyPath: "transform")
        spring.fromValue = NSValue(caTransform3D: transform)
        spring.toValue = NSValue(caTransform3D: CATransform3DIdentity)
        spring.damping = 22
        spring.stiffness = 340
        spring.duration = spring.settlingDuration
        layer.add(spring, forKey: "overlayAppear")
        if let blurredView {
            blurIn(blurredView)
        }
    }

    private static func blurIn(_ view: NSView) {
        guard let layer = view.layer, let blur = CIFilter(name: "CIGaussianBlur") else { return }
        view.layerUsesCoreImageFilters = true
        blur.name = "appearBlur"
        blur.setValue(0, forKey: kCIInputRadiusKey)
        layer.filters = [blur]
        let animation = CABasicAnimation(keyPath: "filters.appearBlur.inputRadius")
        animation.fromValue = 6
        animation.toValue = 0
        animation.duration = 0.18
        animation.timingFunction = CAMediaTimingFunction(name: .easeOut)
        CATransaction.begin()
        CATransaction.setCompletionBlock {
            MainActor.assumeIsolated { layer.filters = nil }
        }
        layer.add(animation, forKey: "appearBlur")
        CATransaction.commit()
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
