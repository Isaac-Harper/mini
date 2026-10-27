import AppKit

final class BrowserHostView: NSView {
    var onWebViewAttached: (() -> Void)?

    var webView: NSView? { subviews.first }

    override func layout() {
        super.layout()
        sizeSubviewsToBounds()
    }

    override func resizeSubviews(withOldSize oldSize: NSSize) {
        super.resizeSubviews(withOldSize: oldSize)
        sizeSubviewsToBounds()
    }

    override func didAddSubview(_ subview: NSView) {
        super.didAddSubview(subview)
        subview.frame = bounds
        subview.autoresizingMask = [.width, .height]
        onWebViewAttached?()
    }

    private func sizeSubviewsToBounds() {
        for subview in subviews where subview.frame != bounds {
            subview.frame = bounds
        }
    }
}
