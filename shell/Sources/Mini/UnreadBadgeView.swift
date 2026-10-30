import MiniRules
import SwiftUI

struct UnreadBadgeView: View {
    let tab: Tab
    var isOnTile = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var height: CGFloat { isOnTile ? SidebarMetrics.tileBadgeHeight : SidebarMetrics.rowBadgeHeight }

    var body: some View {
        if let unread = tab.unread, unread.showsBadge {
            Color.clear
                .frame(width: 0, height: 0)
                .overlay {
                    badge(count: unread.count)
                        .padding(SidebarMetrics.badgeRingWidth)
                        .background(Capsule().fill(.background))
                        .keyframeAnimator(initialValue: 1.0, trigger: reduceMotion ? 0 : tab.unreadPulses) { content, scale in
                            content.scaleEffect(scale)
                        } keyframes: { _ in
                            CubicKeyframe(1.25, duration: 0.16)
                            SpringKeyframe(1, duration: 0.34, spring: .smooth)
                        }
                        .fixedSize()
                }
                .offset(x: isOnTile ? 3 : -1, y: isOnTile ? -2 : 1)
                .allowsHitTesting(false)
                .accessibilityLabel(unread.count.map { "\($0) unread" } ?? "Unread")
        }
    }

    @ViewBuilder
    private func badge(count: Int?) -> some View {
        if let count {
            Text(UnreadTitle.badgeLabel(count: count))
                .font(InterfaceFont.unreadBadge(onTile: isOnTile))
                .monospacedDigit()
                .foregroundStyle(.white)
                .lineLimit(1)
                .fixedSize()
                .padding(.horizontal, isOnTile ? 4 : 3)
                .frame(minWidth: height, minHeight: height)
                .background(Capsule().fill(.tint))
        } else {
            Circle().fill(.tint).frame(width: height * 0.6, height: height * 0.6)
        }
    }
}
