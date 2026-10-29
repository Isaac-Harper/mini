import AppKit
import SwiftUI

enum FocusRingMetrics {
    static let width: CGFloat = 2
    static let contrastWidth: CGFloat = 3
    static let offset: CGFloat = 3
    static let opacity = 0.85

    static func radius(around inner: CGFloat) -> CGFloat {
        inner + offset
    }

    static var currentWidth: CGFloat {
        NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast ? contrastWidth : width
    }

    static func color(_ accent: NSColor) -> NSColor {
        NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast ? accent : accent.withAlphaComponent(opacity)
    }
}

struct FocusRing: View {
    let cornerRadius: CGFloat?

    private static let capsuleRadius: CGFloat = 1_000

    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        let isStrong = contrast == .increased
        RoundedRectangle(cornerRadius: cornerRadius.map(FocusRingMetrics.radius(around:)) ?? Self.capsuleRadius, style: .continuous)
            .strokeBorder(.tint.opacity(isStrong ? 1 : FocusRingMetrics.opacity),
                          lineWidth: isStrong ? FocusRingMetrics.contrastWidth : FocusRingMetrics.width)
            .padding(-FocusRingMetrics.offset)
            .allowsHitTesting(false)
    }
}

final class FocusRingLayer: CAShapeLayer {
    func update(around rect: CGRect, cornerRadius: CGFloat, accent: NSColor) {
        let ringRect = rect.insetBy(dx: -FocusRingMetrics.offset, dy: -FocusRingMetrics.offset)
        let width = FocusRingMetrics.currentWidth
        let radius = FocusRingMetrics.radius(around: cornerRadius)
        path = CGPath(roundedRect: ringRect.insetBy(dx: width / 2, dy: width / 2), cornerWidth: radius - width / 2, cornerHeight: radius - width / 2, transform: nil)
        cornerCurve = .continuous
        fillColor = nil
        lineWidth = width
        strokeColor = FocusRingMetrics.color(accent).cgColor
    }
}

final class FocusRingView: NSView {
    var cornerRadius: CGFloat = 0 {
        didSet { needsLayout = true }
    }
    var accent = NSColor.controlAccentColor {
        didSet { needsLayout = true }
    }

    private let ring = FocusRingLayer()

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func layout() {
        super.layout()
        wantsLayer = true
        if ring.superlayer == nil { layer?.addSublayer(ring) }
        ring.frame = bounds
        ring.update(around: bounds.insetBy(dx: FocusRingMetrics.offset, dy: FocusRingMetrics.offset), cornerRadius: cornerRadius, accent: accent)
    }
}
