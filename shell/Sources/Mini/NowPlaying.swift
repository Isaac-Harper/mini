import CMiniCore
import SwiftUI

struct AudioToggleButton: View {
    let shell: ShellController
    let tab: Tab

    var body: some View {
        if tab.isPlayingAudio || tab.isAudioMuted {
            Button {
                shell.setMuted(!tab.isAudioMuted, for: tab)
            } label: {
                Image(systemName: tab.isAudioMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                    .font(InterfaceFont.accessorySymbol)
                    .foregroundStyle(.secondary)
                    .frame(width: SidebarMetrics.accessorySize, height: SidebarMetrics.accessorySize)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .focusable(false)
            .help(tab.isAudioMuted ? "Unmute Tab" : "Mute Tab")
        }
    }
}

struct NowPlayingRowView: View {
    let shell: ShellController
    let tab: Tab

    @State private var isHovered = false

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast

    private var tint: Color {
        guard !reduceTransparency, contrast != .increased,
              let color = tab.mediaArtworkTint ?? tab.favicon.flatMap(DominantColor.of) else { return .clear }
        return Color(nsColor: color).opacity(0.22)
    }

    private var isPlaying: Bool {
        shell.airPlay.tab === tab ? shell.airPlay.isPlaying : tab.isPlayingAudio
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: SidebarMetrics.rowCornerRadius, style: .continuous)
        HStack(spacing: SidebarMetrics.iconSpacing) {
            NowPlayingArtworkView(artwork: tab.mediaArtwork, favicon: tab.favicon)
            Text(tab.mediaTitle.isEmpty ? tab.displayTitle : tab.mediaTitle)
                .lineLimit(1)
                .truncationMode(.tail)
                .foregroundStyle(.primary)
            Spacer(minLength: 0)
            AirPlayButton(shell: shell, tab: tab)
            Button {
                shell.togglePlayback(of: tab)
            } label: {
                Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                    .font(InterfaceFont.controlSymbol)
                    .foregroundStyle(.secondary)
                    .frame(width: SidebarMetrics.accessorySize, height: SidebarMetrics.accessorySize)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .focusable(false)
            .help(isPlaying ? "Pause" : "Play")
        }
        .padding(.leading, SidebarMetrics.rowLeadingPadding)
        .padding(.trailing, SidebarMetrics.rowTrailingPadding)
        .frame(height: SidebarMetrics.rowHeight)
        .background {
            shape.fill(tint)
                .animation(.easeInOut(duration: 0.4), value: tint)
            if isHovered {
                shape.fill(.fill.quaternary)
            }
        }
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
        .onTapGesture { shell.reveal(tab) }
    }
}

private struct NowPlayingArtworkView: View {
    let artwork: NSImage?
    let favicon: NSImage?

    private static let side = SidebarMetrics.artworkSize

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: SidebarMetrics.rowCornerRadius - SidebarMetrics.rowLeadingPadding, style: .continuous)
        ZStack {
            if let artwork {
                Image(nsImage: artwork)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fill)
                    .frame(width: Self.side, height: Self.side)
                    .clipShape(shape)
                    .transition(.opacity)
            } else {
                shape.fill(.fill.quaternary)
                FaviconView(image: favicon, size: SidebarMetrics.iconSize - 4)
            }
        }
        .frame(width: Self.side, height: Self.side)
        .animation(.easeInOut(duration: 0.4), value: artwork)
    }
}
