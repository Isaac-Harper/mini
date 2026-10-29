import AppKit

final class BrowserHostView: NSView {
    var onWebViewAttached: (() -> Void)?

    var webView: NSView? { subviews.first }

    func setBackdrop(rgb: UInt32) {
        wantsLayer = true
        layer?.backgroundColor = CGColor(srgbRed: CGFloat(rgb >> 16 & 0xff) / 255, green: CGFloat(rgb >> 8 & 0xff) / 255,
                                         blue: CGFloat(rgb & 0xff) / 255, alpha: 1)
    }

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
