import AppKit
import SwiftUI

private struct FadingTruncation: ViewModifier {
    let fadeWidth: CGFloat
    let tooltip: String?

    @State private var contentWidth: CGFloat = 0
    @State private var availableWidth: CGFloat = 0

    private var overflows: Bool { contentWidth > availableWidth + 0.5 }

    func body(content: Content) -> some View {
        content
            .lineLimit(1)
            .hidden()
            .frame(maxWidth: .infinity, alignment: .leading)
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { availableWidth = $0 }
            .overlay(alignment: .leading) {
                content
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                    .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { contentWidth = $0 }
            }
            .mask {
                HStack(spacing: 0) {
                    Rectangle()
                    if overflows {
                        LinearGradient(colors: [.black, .clear], startPoint: .leading, endPoint: .trailing)
                            .frame(width: fadeWidth)
                    }
                }
            }
            .glassTooltip(overflows ? tooltip ?? "" : "")
    }
}

extension View {
    func fadingTruncation(width: CGFloat = SidebarMetrics.titleFadeWidth, tooltip: String? = nil) -> some View {
        modifier(FadingTruncation(fadeWidth: width, tooltip: tooltip))
    }
}

final class FadingTextField: NSTextField {
    private let fadeMask = CAGradientLayer()

    override func layout() {
        super.layout()
        updateFade()
    }

    override var stringValue: String {
        didSet { updateFade() }
    }

    func updateFade() {
        wantsLayer = true
        let isEditing = currentEditor() != nil
        let overflows = !isEditing && attributedStringValue.size().width > bounds.width - 4
        if !isEditing {
            alignment = overflows ? .left : .center
        }
        guard overflows, bounds.width > SidebarMetrics.titleFadeWidth else {
            layer?.mask = nil
            return
        }
        let fadeStart = (bounds.width - SidebarMetrics.titleFadeWidth) / bounds.width
        fadeMask.frame = bounds
        fadeMask.startPoint = CGPoint(x: 0, y: 0.5)
        fadeMask.endPoint = CGPoint(x: 1, y: 0.5)
        fadeMask.colors = [NSColor.black.cgColor, NSColor.black.cgColor, NSColor.clear.cgColor]
        fadeMask.locations = [0, NSNumber(value: fadeStart), 1]
        layer?.mask = fadeMask
    }
}
