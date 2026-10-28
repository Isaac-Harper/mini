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

    var body: some View {
        HStack(spacing: 8) {
            FaviconView(image: tab.favicon, size: 16)
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
        .padding(.horizontal, 8)
        .frame(height: SidebarMetrics.rowHeight)
        .background {
            if isHovered {
                RoundedRectangle(cornerRadius: SidebarMetrics.rowCornerRadius, style: .continuous).fill(.fill.quaternary)
            }
        }
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
        .onTapGesture { shell.reveal(tab) }
    }
}
