import SwiftUI

struct PinnedTabsView: View {
    let shell: ShellController

    private let columns = [GridItem(.adaptive(minimum: 44), spacing: 8)]

    var body: some View {
        GlassEffectContainer(spacing: 8) {
            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(shell.store.pinnedTabs) { tab in
                    PinnedTabTile(shell: shell, tab: tab)
                }
            }
        }
    }
}

private struct PinnedTabTile: View {
    let shell: ShellController
    let tab: Tab

    private var isSelected: Bool { shell.store.selectedTab === tab }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
        FaviconView(image: tab.favicon, size: 18)
            .frame(maxWidth: .infinity)
            .frame(height: 40)
            .glassEffect(isSelected ? .regular.tint(.primary.opacity(0.12)).interactive() : .regular.interactive(), in: shape)
            .overlay(alignment: .topTrailing) {
                AudioToggleButton(shell: shell, tab: tab).offset(x: 4, y: -4)
            }
            .contentShape(shape)
            .help(tab.displayTitle)
            .onTapGesture { shell.store.select(tab) }
            .contextMenu {
                Button("Unpin Tab") { shell.store.unpin(tab) }
                Button("Close Tab") { shell.store.close(tab) }
            }
    }
}
