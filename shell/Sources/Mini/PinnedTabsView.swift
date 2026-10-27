import SwiftUI

struct PinnedTabsView: View {
    let shell: ShellController

    private let columns = [GridItem(.adaptive(minimum: 46), spacing: 6)]

    var body: some View {
        LazyVGrid(columns: columns, spacing: 6) {
            ForEach(shell.store.pinnedTabs) { tab in
                PinnedTabTile(shell: shell, tab: tab)
            }
        }
    }
}

private struct PinnedTabTile: View {
    let shell: ShellController
    let tab: Tab

    @State private var isHovered = false

    private var isSelected: Bool { shell.store.selectedTab === tab }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 10, style: .continuous)
        FaviconView(image: tab.favicon, size: 18)
            .frame(maxWidth: .infinity)
            .frame(height: 40)
            .background {
                if isSelected {
                    Color.clear.glassEffect(.regular, in: shape)
                } else {
                    shape.fill(.primary.opacity(isHovered ? 0.09 : 0.05))
                }
            }
            .contentShape(shape)
            .help(tab.displayTitle)
            .onHover { isHovered = $0 }
            .onTapGesture { shell.store.select(tab) }
            .contextMenu {
                Button("Unpin Tab") { shell.store.unpin(tab) }
                Button("Close Tab") { shell.store.close(tab) }
            }
    }
}
