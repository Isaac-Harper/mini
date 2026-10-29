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
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 16, height: 16)
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

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: SidebarMetrics.rowCornerRadius, style: .continuous)
        HStack(spacing: 8) {
            NowPlayingArtworkView(artwork: tab.mediaArtwork, favicon: tab.favicon)
            Text(tab.mediaTitle.isEmpty ? tab.displayTitle : tab.mediaTitle)
                .lineLimit(1)
                .truncationMode(.tail)
                .foregroundStyle(.primary)
            Spacer(minLength: 0)
            Button {
                shell.togglePlayback(of: tab)
            } label: {
                Image(systemName: tab.isPlayingAudio ? "pause.fill" : "play.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 20, height: 20)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .focusable(false)
            .help(tab.isPlayingAudio ? "Pause" : "Play")
        }
        .padding(.leading, 3)
        .padding(.trailing, 8)
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

    private static let side: CGFloat = 22

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 5, style: .continuous)
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
                FaviconView(image: favicon, size: 14)
            }
        }
        .frame(width: Self.side, height: Self.side)
        .animation(.easeInOut(duration: 0.4), value: artwork)
    }
}
