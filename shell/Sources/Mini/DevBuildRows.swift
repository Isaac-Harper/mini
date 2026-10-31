import MiniRules
import SwiftUI

extension ShellController {
    func scheduleRebuildExpiry(of tab: Tab) {
        guard let expiry = tab.devBuild.rebuildExpiry() else { return }
        tab.devBuildExpiryGeneration += 1
        let generation = tab.devBuildExpiryGeneration
        DispatchQueue.main.asyncAfter(deadline: .now() + max(0, expiry.timeIntervalSinceNow)) { [weak tab] in
            MainActor.assumeIsolated {
                guard let tab, tab.devBuildExpiryGeneration == generation else { return }
                tab.devBuild.expireRebuild(at: Date())
            }
        }
    }
}

struct DevBuildFavicon: ViewModifier {
    let tab: Tab

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        if tab.devBuild.isRebuilding && !tab.isLoading {
            if reduceMotion {
                content.opacity(0.5)
            } else {
                content.phaseAnimator([1.0, 0.35]) { content, opacity in
                    content.opacity(opacity)
                } animation: { _ in
                    .easeInOut(duration: 0.8)
                }
            }
        } else {
            content
        }
    }
}

struct BuildErrorMarkView: View {
    let tab: Tab
    var isOnTile = false

    private var height: CGFloat { isOnTile ? SidebarMetrics.tileBadgeHeight : SidebarMetrics.rowBadgeHeight }

    var body: some View {
        if tab.devBuild.hasCompileError {
            Color.clear
                .frame(width: 0, height: 0)
                .overlay {
                    Circle()
                        .fill(.red)
                        .frame(width: height * 0.6, height: height * 0.6)
                        .padding(SidebarMetrics.badgeRingWidth)
                        .background(Circle().fill(.background))
                        .fixedSize()
                }
                .offset(x: isOnTile ? 3 : -1, y: isOnTile ? 2 : -1)
                .allowsHitTesting(false)
                .accessibilityLabel("Build error")
        }
    }
}

extension View {
    func devBuildState(of tab: Tab, isOnTile: Bool = false) -> some View {
        modifier(DevBuildFavicon(tab: tab))
            .overlay(alignment: .bottomTrailing) { BuildErrorMarkView(tab: tab, isOnTile: isOnTile) }
            .glassTooltip(tab.devBuild.hasCompileError && !isOnTile ? "Build error" : "")
    }
}
