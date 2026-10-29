import SwiftUI

struct SiteTintView: View {
    let spaceColor: NSColor
    let color: NSColor?

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.colorScheme) private var colorScheme

    private static let strength = 0.2

    private var showsTint: Bool { !reduceTransparency && contrast != .increased }

    private var spaceTint: Color {
        guard showsTint else { return .clear }
        return Color(nsColor: spaceColor).opacity(colorScheme == .dark ? 0.13 : 0.1)
    }

    private var tint: Color {
        guard let color, showsTint else { return .clear }
        return Color(nsColor: color).opacity(Self.strength * color.alphaComponent)
    }

    var body: some View {
        ZStack {
            Rectangle()
                .fill(spaceTint)
                .animation(.easeInOut(duration: 0.3), value: spaceTint)
            Rectangle()
                .fill(tint)
                .animation(.easeInOut(duration: 0.25), value: tint)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }
}
