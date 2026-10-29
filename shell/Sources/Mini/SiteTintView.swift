import SwiftUI

struct SiteTintView: View {
    let spaceColor: NSColor
    let neighborColor: NSColor?
    let swipeProgress: CGFloat
    let color: NSColor?
    let eveningStrength: Double

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.colorScheme) private var colorScheme

    private static let strength = 0.2
    private static let eveningColor = Color(red: 1, green: 0.6, blue: 0.22)

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

    private var eveningTint: Color {
        guard showsTint else { return .clear }
        return Self.eveningColor.opacity((colorScheme == .dark ? 0.07 : 0.06) * eveningStrength)
    }

    private var tint: Color {
        guard let color, showsTint else { return .clear }
        return Color(nsColor: color).opacity(Self.strength * color.alphaComponent * (1 - swipeProgress))
    }

    var body: some View {
        ZStack {
            Rectangle()
                .fill(eveningTint)
                .animation(.easeInOut(duration: 3), value: eveningStrength)
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
