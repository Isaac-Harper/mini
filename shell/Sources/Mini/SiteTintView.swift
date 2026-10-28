import SwiftUI

struct SiteTintView: View {
    let color: NSColor?

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast

    private static let strength = 0.2

    private var tint: Color {
        guard let color, !reduceTransparency, contrast != .increased else { return .clear }
        return Color(nsColor: color).opacity(Self.strength * color.alphaComponent)
    }

    var body: some View {
        Rectangle()
            .fill(tint)
            .ignoresSafeArea()
            .allowsHitTesting(false)
            .animation(.easeInOut(duration: 0.25), value: tint)
    }
}
