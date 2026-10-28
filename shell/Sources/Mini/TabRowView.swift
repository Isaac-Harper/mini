import SwiftUI

struct TabRowView: View {
    let shell: ShellController
    let tab: Tab
    let depth: Int

    @State private var isHovered = false

    private var isSelected: Bool { shell.store.selectedTab === tab }

    var body: some View {
        HStack(spacing: 4) {
            disclosure
            FaviconView(image: tab.favicon, size: 16)
                .opacity(tab.isLoading ? 0.4 : 1)
                .animation(.easeInOut(duration: 0.3), value: tab.isLoading)
                .padding(.trailing, 4)
            Text(tab.displayTitle)
                .lineLimit(1)
                .truncationMode(.tail)
                .foregroundStyle(isSelected ? .primary : .secondary)
            Spacer(minLength: 0)
            if isHovered {
                Button {
                    shell.store.close(tab)
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.secondary)
                        .frame(width: 16, height: 16)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .focusable(false)
                .help("Close Tab")
            }
        }
        .padding(.leading, 4 + CGFloat(depth) * SidebarMetrics.indentation)
        .padding(.trailing, 6)
        .frame(height: SidebarMetrics.rowHeight)
        .background { rowBackground }
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
        .onTapGesture { shell.store.select(tab) }
        .contextMenu {
            Button("Pin Tab") { shell.store.pin(tab) }
                .disabled(tab.url.isEmpty)
            Button("Close Tab") { shell.store.close(tab) }
        }
    }

    @ViewBuilder
    private var rowBackground: some View {
        let shape = RoundedRectangle(cornerRadius: SidebarMetrics.rowCornerRadius, style: .continuous)
        if isSelected {
            shape.fill(.fill.secondary)
        } else if isHovered {
            shape.fill(.fill.quaternary)
        }
    }

    @ViewBuilder
    private var disclosure: some View {
        if tab.children.isEmpty {
            Color.clear.frame(width: 12, height: 12)
        } else {
            Image(systemName: "chevron.right")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.tertiary)
                .rotationEffect(.degrees(tab.isCollapsed ? 0 : 90))
                .animation(.easeOut(duration: 0.15), value: tab.isCollapsed)
                .frame(width: 12, height: 12)
                .contentShape(Rectangle())
                .onTapGesture { shell.store.toggleCollapse(tab) }
        }
    }
}
