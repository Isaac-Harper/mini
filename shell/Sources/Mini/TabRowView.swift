import SwiftUI

struct TabRowView: View {
    let shell: ShellController
    let tab: Tab
    let depth: Int

    @State private var isHovered = false

    private var isSelected: Bool { shell.store.selectedTab === tab }

    private var isDimmed: Bool { tab.isSaved && !isSelected && !tab.hasBrowser }

    var body: some View {
        HStack(spacing: 4) {
            disclosure
            Group {
                TabIconView(tab: tab, size: 16)
                    .opacity(tab.isLoading ? 0.4 : 1)
                    .animation(.easeInOut(duration: 0.3), value: tab.isLoading)
                    .padding(.trailing, 4)
                Text(tab.displayTitle)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .foregroundStyle(isSelected ? .primary : .secondary)
            }
            .opacity(isDimmed ? 0.5 : 1)
            Spacer(minLength: 0)
            AudioToggleButton(shell: shell, tab: tab)
            if let savedURL = tab.savedURL, tab.hasLeftSavedURL {
                Button {
                    shell.navigate(tab, to: savedURL)
                } label: {
                    Image(systemName: "arrow.uturn.backward")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.secondary)
                        .frame(width: 16, height: 16)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .focusable(false)
                .help("Back to Saved Page")
            }
            if isHovered {
                Button {
                    shell.performUndoable("Close Tab") { shell.store.close(tab) }
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
        .overlay { TabDropIndicator(shell: shell, tab: tab, depth: depth) }
        .overlay { SidebarFocusRing(shell: shell, tab: tab, cornerRadius: SidebarMetrics.rowCornerRadius) }
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
        .onTapGesture { shell.store.select(tab) }
        .onDrag { shell.sidebarDrag.beginDrag(tab) }
        .onDrop(of: SidebarDragModel.acceptedTypes, delegate: TabRowDropDelegate(shell: shell, tab: tab))
        .contextMenu {
            Button("Open in Split View") { shell.openInSplitView(tab) }
                .disabled(!canOpenInSplitView)
            Button("Duplicate Tab") { shell.duplicate(tab) }
                .disabled(tab.url.isEmpty)
            Button("Pin Tab") { shell.performUndoable("Pin Tab") { shell.store.pin(tab) } }
                .disabled(tab.url.isEmpty)
            if tab.isSaved {
                Button("Remove from Saved") { shell.performUndoable("Remove from Saved") { shell.store.unsave(tab) } }
                Divider()
                Button("Delete") { shell.performUndoable("Delete Tab") { shell.store.remove(tab) } }
            } else {
                Button("Save Tab") { shell.performUndoable("Save Tab") { shell.store.save(tab) } }
                    .disabled(!shell.store.canSave(tab))
                Button("Close Tab") { shell.performUndoable("Close Tab") { shell.store.close(tab) } }
            }
        }
    }

    private var canOpenInSplitView: Bool {
        guard let selected = shell.store.selectedTab else { return false }
        return selected !== tab && !selected.isPinned
    }

    @ViewBuilder
    private var rowBackground: some View {
        let shape = RoundedRectangle(cornerRadius: SidebarMetrics.rowCornerRadius, style: .continuous)
        if isSelected {
            SelectionHighlight(shape: shape)
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

struct SplitTabRowView: View {
    let shell: ShellController
    let split: TabSplit
    let depth: Int

    @State private var isHovered = false

    private var isSelected: Bool {
        shell.store.selectedTab.map(split.contains) ?? false
    }

    var body: some View {
        HStack(spacing: 2) {
            Color.clear.frame(width: 12, height: 12)
            SplitTabHalfView(shell: shell, tab: split.leading, isPairSelected: isSelected)
            Rectangle()
                .fill(.separator)
                .frame(width: 1, height: 14)
            SplitTabHalfView(shell: shell, tab: split.trailing, isPairSelected: isSelected)
        }
        .padding(.leading, 4 + CGFloat(depth) * SidebarMetrics.indentation)
        .padding(.trailing, 2)
        .frame(height: SidebarMetrics.rowHeight)
        .background {
            let shape = RoundedRectangle(cornerRadius: SidebarMetrics.rowCornerRadius, style: .continuous)
            if isSelected {
                SelectionHighlight(shape: shape)
            } else if isHovered {
                shape.fill(.fill.quaternary)
            }
        }
        .overlay { TabDropIndicator(shell: shell, tab: split.leading, depth: depth) }
        .overlay { SidebarFocusRing(shell: shell, tab: split.leading, cornerRadius: SidebarMetrics.rowCornerRadius) }
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
        .onDrag { shell.sidebarDrag.beginDrag(split.leading) }
        .onDrop(of: SidebarDragModel.acceptedTypes, delegate: TabRowDropDelegate(shell: shell, tab: split.leading))
        .contextMenu {
            Button("Separate Tabs") { shell.performUndoable("Separate Tabs") { shell.store.unsplit(split) } }
            Button("Close \(split.leading.displayTitle)") { shell.performUndoable("Close Tab") { shell.store.close(split.leading) } }
            Button("Close \(split.trailing.displayTitle)") { shell.performUndoable("Close Tab") { shell.store.close(split.trailing) } }
        }
    }
}

private struct SplitTabHalfView: View {
    let shell: ShellController
    let tab: Tab
    let isPairSelected: Bool

    @State private var isHovered = false

    private var isFocused: Bool { shell.store.selectedTab === tab }

    var body: some View {
        HStack(spacing: 4) {
            TabIconView(tab: tab, size: 16)
                .opacity(tab.isLoading ? 0.4 : 1)
                .animation(.easeInOut(duration: 0.3), value: tab.isLoading)
            Text(tab.displayTitle)
                .lineLimit(1)
                .truncationMode(.tail)
                .foregroundStyle(isFocused ? .primary : .secondary)
            Spacer(minLength: 0)
            AudioToggleButton(shell: shell, tab: tab)
            if isHovered {
                Button {
                    shell.performUndoable("Close Tab") { shell.store.close(tab) }
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
        .padding(.horizontal, 4)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            if isPairSelected && isFocused {
                RoundedRectangle(cornerRadius: SidebarMetrics.rowCornerRadius - 2, style: .continuous)
                    .fill(.fill.tertiary)
                    .padding(.vertical, 3)
            }
        }
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
        .onTapGesture { shell.store.select(tab) }
    }
}
