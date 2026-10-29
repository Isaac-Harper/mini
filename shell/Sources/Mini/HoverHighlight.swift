import AppKit
import SwiftUI

enum HoverStyle {
    static let fadeIn: TimeInterval = 0.08
    static let fadeOut: TimeInterval = 0.15
}

private struct HoverHighlight: ViewModifier {
    let cornerRadius: CGFloat
    let isSuppressed: Bool
    let isHovered: Binding<Bool>?

    @State private var isInside = false
    @Environment(\.colorSchemeContrast) private var contrast

    func body(content: Content) -> some View {
        content
            .background {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(contrast == .increased ? AnyShapeStyle(.fill.tertiary) : AnyShapeStyle(.fill.quaternary))
                    .opacity(isInside && !isSuppressed ? 1 : 0)
                    .animation(.easeOut(duration: isInside ? HoverStyle.fadeIn : HoverStyle.fadeOut), value: isInside)
                    .allowsHitTesting(false)
            }
            .onHover { inside in
                isInside = inside
                isHovered?.wrappedValue = inside
            }
    }
}

extension View {
    func hoverHighlight(cornerRadius: CGFloat = SidebarMetrics.rowCornerRadius, suppressed: Bool = false, isHovered: Binding<Bool>? = nil) -> some View {
        modifier(HoverHighlight(cornerRadius: cornerRadius, isSuppressed: suppressed, isHovered: isHovered))
    }
}

class HoverHighlightButton: NSButton {
    var hoverCornerRadius: CGFloat = SidebarMetrics.rowCornerRadius

    private let highlightLayer = CALayer()
    private var hoverArea: NSTrackingArea?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let hoverArea { removeTrackingArea(hoverArea) }
        let area = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeInActiveApp, .inVisibleRect], owner: self)
        addTrackingArea(area)
        hoverArea = area
    }

    override func layout() {
        super.layout()
        wantsLayer = true
        if highlightLayer.superlayer == nil {
            highlightLayer.opacity = 0
            layer?.insertSublayer(highlightLayer, at: 0)
        }
        highlightLayer.frame = bounds
        highlightLayer.cornerRadius = hoverCornerRadius
        highlightLayer.cornerCurve = .continuous
        effectiveAppearance.performAsCurrentDrawingAppearance {
            let contrast = NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast
            highlightLayer.backgroundColor = (contrast ? NSColor.tertiarySystemFill : NSColor.quaternarySystemFill).cgColor
        }
    }

    override func mouseEntered(with event: NSEvent) {
        setHighlighted(isEnabled)
    }

    override func mouseExited(with event: NSEvent) {
        setHighlighted(false)
    }

    func setHighlighted(_ highlighted: Bool) {
        needsLayout = true
        layoutSubtreeIfNeeded()
        let animation = CABasicAnimation(keyPath: "opacity")
        animation.fromValue = highlightLayer.presentation()?.opacity ?? highlightLayer.opacity
        animation.duration = highlighted ? HoverStyle.fadeIn : HoverStyle.fadeOut
        animation.timingFunction = CAMediaTimingFunction(name: .easeOut)
        highlightLayer.opacity = highlighted ? 1 : 0
        highlightLayer.add(animation, forKey: "hover")
    }
}
