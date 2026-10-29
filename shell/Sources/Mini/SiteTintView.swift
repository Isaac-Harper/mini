import SwiftUI

struct SiteTintView: View {
    let spaceColor: NSColor
    let neighborColor: NSColor?
    let swipeProgress: CGFloat
    let color: NSColor?

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.colorScheme) private var colorScheme

    private static let strength = 0.2

    private var showsTint: Bool { !reduceTransparency && contrast != .increased }

    private var spaceStrength: Double { colorScheme == .dark ? 0.13 : 0.1 }

    private var spaceTint: Color {
        guard showsTint else { return .clear }
        return Color(nsColor: spaceColor).opacity(spaceStrength * (1 - swipeProgress))
    }

    private var neighborTint: Color {
        guard let neighborColor, showsTint else { return .clear }
        return Color(nsColor: neighborColor).opacity(spaceStrength * swipeProgress)
    }

    private var tint: Color {
        guard let color, showsTint else { return .clear }
        return Color(nsColor: color).opacity(Self.strength * color.alphaComponent * (1 - swipeProgress))
    }

    var body: some View {
        ZStack {
            Rectangle()
                .fill(spaceTint)
                .animation(.easeInOut(duration: 0.3), value: spaceColor)
            Rectangle()
                .fill(neighborTint)
            Rectangle()
                .fill(tint)
                .animation(.easeInOut(duration: 0.25), value: color)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }
}
