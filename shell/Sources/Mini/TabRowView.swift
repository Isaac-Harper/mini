import SwiftUI

struct TabRowView: View {
    let shell: ShellController
    let tab: Tab
    let depth: Int

    @State private var isHovered = false

    private static let indentation: CGFloat = 14

    private var isSelected: Bool { shell.store.selectedTab === tab }

    var body: some View {
        HStack(spacing: 6) {
            disclosure
            favicon
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
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 18, height: 18)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .focusable(false)
            }
        }
        .padding(.leading, 4 + CGFloat(depth) * Self.indentation)
        .padding(.trailing, 6)
        .frame(height: 30)
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
        let shape = RoundedRectangle(cornerRadius: 8, style: .continuous)
        if isSelected {
            Color.clear.glassEffect(.regular, in: shape)
        } else if isHovered {
            shape.fill(.primary.opacity(0.05))
        }
    }

    @ViewBuilder
    private var disclosure: some View {
        if tab.children.isEmpty {
            Color.clear.frame(width: 12, height: 12)
        } else {
            Image(systemName: "chevron.right")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.tertiary)
                .rotationEffect(.degrees(tab.isCollapsed ? 0 : 90))
                .frame(width: 12, height: 12)
                .contentShape(Rectangle())
                .onTapGesture { shell.store.toggleCollapse(tab) }
        }
    }

    private var favicon: some View {
        FaviconView(image: tab.favicon, size: 16)
            .opacity(tab.isLoading ? 0.35 : 1)
            .animation(.easeInOut(duration: 0.3), value: tab.isLoading)
    }
}
