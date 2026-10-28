import CMiniCore
import SwiftUI

enum SidebarMetrics {
    static let rowHeight: CGFloat = 28
    static let rowCornerRadius: CGFloat = 8
    static let edgeInset: CGFloat = 8
    static let indentation: CGFloat = 16
}

struct SidebarView: View {
    let shell: ShellController

    private var store: TabStore { shell.store }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            AddressPill(shell: shell)
                .padding(.horizontal, SidebarMetrics.edgeInset)
                .padding(.top, 4)
                .padding(.bottom, 12)
            if !store.pinnedTabs.isEmpty {
                PinnedTabsView(shell: shell)
                    .padding(.horizontal, SidebarMetrics.edgeInset)
                    .padding(.bottom, 12)
            }
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(store.visibleTabs) { visibleTab in
                        TabRowView(shell: shell, tab: visibleTab.tab, depth: visibleTab.depth)
                    }
                }
                .padding(.horizontal, SidebarMetrics.edgeInset)
            }
            .scrollIndicators(.never)
            Spacer(minLength: 0)
            footer
        }
        .font(.system(size: 13))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            Color.clear
                .contentShape(Rectangle())
                .gesture(WindowDragGesture())
        }
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(shell.downloads.visibleDownloads) { download in
                DownloadRowView(download: download) { shell.downloads.activate(download) }
                    .transition(.opacity)
            }
            SidebarActionRow(title: "New Tab", systemImage: "plus") {
                shell.commandBar.open(mode: .newTab)
            }
        }
        .animation(.easeInOut(duration: 0.3), value: shell.downloads.visibleDownloads.map(\.id))
        .padding(.horizontal, SidebarMetrics.edgeInset)
        .padding(.bottom, SidebarMetrics.edgeInset)
    }
}

struct SidebarActionRow: View {
    let title: String
    let systemImage: String
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: systemImage)
                    .font(.system(size: 13, weight: .regular))
                    .frame(width: 16)
                Text(title)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 0)
            }
            .foregroundStyle(.secondary)
            .padding(.horizontal, 8)
            .frame(height: SidebarMetrics.rowHeight)
            .background {
                if isHovered {
                    RoundedRectangle(cornerRadius: SidebarMetrics.rowCornerRadius, style: .continuous).fill(.fill.quaternary)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focusable(false)
        .onHover { isHovered = $0 }
    }
}

private struct AddressPill: View {
    let shell: ShellController

    var body: some View {
        let selected = shell.store.selectedTab
        let host = selected.flatMap { URLInput.host(of: $0.url) }
        GlassEffectContainer(spacing: 8) {
            HStack(spacing: 0) {
                Button {
                    shell.commandBar.open(mode: .editCurrent)
                } label: {
                    Text(host ?? "Search or enter address")
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .foregroundStyle(host == nil ? .tertiary : .secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.leading, 12)
                        .frame(height: 32)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .focusable(false)
                if let selected, selected.hasLoginForm, selected.hasBrowser {
                    Button {
                        shell.fillPassword(nil)
                    } label: {
                        Image(systemName: "key.fill")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.secondary)
                            .frame(width: 28, height: 32)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .focusable(false)
                    .help("Fill Password")
                }
                if let selected, !selected.url.isEmpty {
                    Button {
                        if selected.isLoading {
                            shell.stopLoading(nil)
                        } else {
                            shell.reloadSelected()
                        }
                    } label: {
                        Image(systemName: selected.isLoading ? "xmark" : "arrow.clockwise")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.secondary)
                            .frame(width: 32, height: 32)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .focusable(false)
                    .help(selected.isLoading ? "Stop" : "Reload")
                }
            }
            .glassEffect(.regular.interactive(), in: Capsule())
        }
    }
}
