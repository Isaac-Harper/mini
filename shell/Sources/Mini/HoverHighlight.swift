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

class HoverHighlightButton: NSButton, TooltipText {
    var hoverCornerRadius: CGFloat = SidebarMetrics.rowCornerRadius
    var tooltip = "" {
        didSet {
            setAccessibilityHelp(tooltip.isEmpty ? nil : tooltip)
            GlassTooltip.shared.textChanged(for: self, to: tooltip)
        }
    }

    var tooltipText: String { tooltip }
    var feedback: ControlFeedback = .press
    var bouncesOnPress = true

    private let symbolView = SymbolImageView()

    func showSymbol(_ image: NSImage, pointSize: CGFloat) {
        symbolView.image = image
        symbolView.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: pointSize, weight: .regular)
        symbolView.contentTintColor = .secondaryLabelColor
        symbolView.translatesAutoresizingMaskIntoConstraints = false
        self.image = nil
        imagePosition = .noImage
        setAccessibilityLabel(image.accessibilityDescription)
        addSubview(symbolView)
        NSLayoutConstraint.activate([
            symbolView.centerXAnchor.constraint(equalTo: centerXAnchor),
            symbolView.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
        updateSymbolAlpha()
    }

    override var isEnabled: Bool {
        didSet { updateSymbolAlpha() }
    }

    private func updateSymbolAlpha() {
        symbolView.alphaValue = isEnabled ? 1 : 0.35
    }

    @discardableResult
    override func sendAction(_ action: Selector?, to target: Any?) -> Bool {
        Haptics.controlActivated(feedback)
        if bouncesOnPress, NSApp.currentEvent?.type == .leftMouseUp, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            symbolView.addSymbolEffect(.bounce)
        }
        return super.sendAction(action, to: target)
    }

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
        GlassTooltip.shared.hoverBegan(over: self, text: tooltip)
    }

    override func mouseExited(with event: NSEvent) {
        setHighlighted(false)
        GlassTooltip.shared.hoverEnded(over: self)
    }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        super.viewWillMove(toWindow: newWindow)
        if newWindow == nil { GlassTooltip.shared.hoverEnded(over: self) }
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

private final class SymbolImageView: NSImageView {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}
