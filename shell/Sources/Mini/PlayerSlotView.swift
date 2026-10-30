import MiniRules
import SwiftUI

struct PlayerSlotView: View {
    let shell: ShellController
    let tab: Tab

    @Environment(\.sidebarStore) private var sidebarStore
    @Environment(\.reportsSidebarRowFrames) private var isMainSidebar
    @Environment(\.selectionNamespace) private var namespace
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var store: TabStore { sidebarStore ?? shell.store }

    private var presentation: PlayerSlot.Presentation { shell.playerDock.presentation(of: tab, in: store) }

    private var isSelected: Bool { store.selectedTab === tab }

    var body: some View {
        Group {
            if presentation == .slot {
                slot
            } else {
                row
            }
        }
        .animation(reduceMotion ? .easeInOut(duration: PlayerDock.fadeDuration) : .easeInOut(duration: PlayerDock.flightDuration), value: presentation)
        .contextMenu { PlayerTabMenu(shell: shell, tab: tab) }
    }

    private var slot: some View {
        let shape = RoundedRectangle(cornerRadius: CornerMetrics.playerSlot, style: .continuous)
        return shape.fill(.black)
            .aspectRatio(PlayerSlot.aspectRatio, contentMode: .fit)
            .frame(maxWidth: .infinity)
            .overlay { SidebarFocusRing(shell: shell, tab: tab, cornerRadius: CornerMetrics.playerSlot) }
            .onGeometryChange(for: CGRect.self, of: { $0.frame(in: .global) }) { frame in
                guard store === shell.store else { return }
                shell.playerDock.reportSlotFrame(frame, in: isMainSidebar ? .main : .peek)
            }
            .onDisappear {
                guard store === shell.store else { return }
                shell.playerDock.reportSlotFrame(nil, in: isMainSidebar ? .main : .peek)
            }
            .transition(.opacity)
    }

    private var row: some View {
        HStack(spacing: SidebarMetrics.iconSpacing) {
            TabIconView(tab: tab, size: SidebarMetrics.iconSize)
            Text("Player")
                .lineLimit(1)
                .foregroundStyle(.primary)
            Spacer(minLength: 0)
            AudioToggleButton(shell: shell, tab: tab)
        }
        .modifier(PlayerRowChrome(isSelected: isSelected, namespace: namespace))
        .overlay { SidebarFocusRing(shell: shell, tab: tab, cornerRadius: SidebarMetrics.rowCornerRadius) }
        .help(tab.displayTitle)
        .onTapGesture {
            Haptics.controlActivated(.press)
            shell.clearRowSelection()
            shell.store.select(tab)
        }
        .transition(.opacity)
    }
}

struct EmptyPlayerRow: View {
    let shell: ShellController

    var body: some View {
        HStack(spacing: SidebarMetrics.iconSpacing) {
            if let favicon = shell.faviconCache.image(forPageAt: PlayerSlot.homeURL) {
                FaviconView(image: favicon, size: SidebarMetrics.iconSize)
            } else {
                Image(systemName: "play.rectangle.fill")
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(.red)
                    .frame(width: SidebarMetrics.iconSize, height: SidebarMetrics.iconSize)
            }
            Text("Player")
                .lineLimit(1)
                .foregroundStyle(.primary)
            Spacer(minLength: 0)
        }
        .modifier(PlayerRowChrome(isSelected: false, namespace: nil))
        .help("YouTube")
        .onTapGesture {
            Haptics.controlActivated(.press)
            shell.createPlayer()
        }
        .contextMenu {
            Button("Hide Player", systemImage: "eye.slash") { shell.performUndoable("Hide Player") { shell.store.setShowsPlayerSlot(false) } }
        }
        .transition(.opacity)
    }
}

private struct PlayerRowChrome: ViewModifier {
    let isSelected: Bool
    let namespace: Namespace.ID?

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: SidebarMetrics.rowCornerRadius, style: .continuous)
        return content
            .padding(.leading, SidebarMetrics.footerRowPadding)
            .padding(.trailing, SidebarMetrics.rowTrailingPadding)
            .frame(height: SidebarMetrics.rowHeight)
            .background {
                if isSelected {
                    if let namespace {
                        shape.fill(.tint.opacity(0.22)).matchedGeometryEffect(id: "pinnedSelection", in: namespace)
                    } else {
                        shape.fill(.tint.opacity(0.22))
                    }
                }
            }
            .hoverHighlight(suppressed: isSelected)
            .glassEffect(.regular.interactive(), in: shape)
            .contentShape(shape)
    }
}

struct PlayerTabMenu: View {
    let shell: ShellController
    let tab: Tab

    var body: some View {
        if shell.playerDock.dockedTab === tab {
            Button("Close Video", systemImage: "stop.circle") { shell.playerDock.closeVideo() }
        }
        Button("Remove Player Tab", systemImage: "rectangle.slash") { shell.performUndoable("Remove Player Tab") { shell.store.removePlayer() } }
        Divider()
        Button("Close Tab", systemImage: "xmark") { shell.performUndoable("Close Tab") { shell.store.close(tab) } }
    }
}

struct PlayerDockControls: View {
    let shell: ShellController
    let dock: PlayerDock

    var body: some View {
        ZStack {
            Color.black.opacity(dock.isHovered ? 0.25 : 0)
                .contentShape(Rectangle())
                .onTapGesture {
                    Haptics.controlActivated(.toggle)
                    shell.expandPlayer()
                }
            if dock.isHovered, let tab = dock.dockedTab {
                controls(for: tab)
                    .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: dock.isHovered ? HoverStyle.fadeIn : HoverStyle.fadeOut), value: dock.isHovered)
        .contextMenu {
            if let tab = dock.dockedTab {
                PlayerTabMenu(shell: shell, tab: tab)
            }
        }
    }

    private func controls(for tab: Tab) -> some View {
        GlassEffectContainer(spacing: SidebarMetrics.playerControlSpacing) {
            VStack(spacing: 0) {
                HStack(spacing: SidebarMetrics.playerControlSpacing) {
                    control("pip.enter", help: "Picture in Picture", feedback: .toggle) { dock.popOut() }
                    Spacer(minLength: 0)
                    control("xmark", help: "Close Video", feedback: .toggle) { dock.closeVideo() }
                }
                Spacer(minLength: 0)
                HStack(spacing: SidebarMetrics.playerControlSpacing) {
                    control("gobackward.10", help: "Back 10 Seconds", feedback: .press) { dock.skip(by: -10) }
                    control(tab.isPlayingAudio ? "pause.fill" : "play.fill", help: tab.isPlayingAudio ? "Pause" : "Play", feedback: .toggle, size: SidebarMetrics.playerPrimaryControlSize) {
                        dock.togglePlayback()
                    }
                    control("goforward.10", help: "Forward 10 Seconds", feedback: .press) { dock.skip(by: 10) }
                }
                Spacer(minLength: 0)
            }
            .padding(SidebarMetrics.playerControlInset)
        }
    }

    private func control(_ symbol: String, help: String, feedback: ControlFeedback, size: CGFloat = SidebarMetrics.playerControlSize, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .contentTransition(.symbolEffect(.replace))
                .font(InterfaceFont.controlSymbol)
                .foregroundStyle(.primary)
                .frame(width: size, height: size)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .focusable(false)
        .hoverHighlight(cornerRadius: size / 2)
        .glassEffect(.regular.interactive(), in: Circle())
        .hapticFeedback(feedback)
        .help(help)
    }
}
