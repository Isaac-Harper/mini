import SwiftUI

struct TabRowView: View {
    let shell: ShellController
    let tab: Tab
    let depth: Int

    @State private var isHovered = false

    @Environment(\.sidebarStore) private var sidebarStore

    private var store: TabStore { sidebarStore ?? shell.store }

    private var isSelected: Bool { store.selectedTab === tab }

    private var isDimmed: Bool { tab.isSaved && !isSelected && !tab.hasBrowser }

    private var isInGroup: Bool { store.rowSelection.contains(tab.id) }

    var body: some View {
        HStack(spacing: SidebarMetrics.accessorySpacing) {
            disclosure
            Group {
                TabIconView(tab: tab, size: SidebarMetrics.iconSize)
                    .opacity(tab.isLoading ? 0.4 : 1)
                    .animation(.easeInOut(duration: 0.3), value: tab.isLoading)
                    .overlay(alignment: .topTrailing) { UnreadBadgeView(tab: tab) }
                    .padding(.trailing, SidebarMetrics.iconSpacing - SidebarMetrics.accessorySpacing)
                Text(tab.displayTitle)
                    .fadingTruncation()
                    .foregroundStyle(isSelected ? .primary : .secondary)
            }
            .opacity(isDimmed ? 0.5 : (isSelected || isHovered || tab.isSaved ? 1 : tab.idleFade))
            Spacer(minLength: 0)
            AudioToggleButton(shell: shell, tab: tab)
            if let savedURL = tab.savedURL, tab.hasLeftSavedURL {
                Button {
                    shell.navigate(tab, to: savedURL)
                } label: {
                    Image(systemName: "arrow.uturn.backward")
                        .font(InterfaceFont.accessorySymbol)
                        .foregroundStyle(.secondary)
                        .frame(width: SidebarMetrics.accessorySize, height: SidebarMetrics.accessorySize)
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
                        .font(InterfaceFont.accessorySymbol)
                        .foregroundStyle(.secondary)
                        .frame(width: SidebarMetrics.accessorySize, height: SidebarMetrics.accessorySize)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .focusable(false)
                .hapticFeedback(.press)
                .help("Close Tab")
            }
        }
        .padding(.leading, SidebarMetrics.indent(depth: depth))
        .padding(.trailing, SidebarMetrics.rowTrailingPadding)
        .frame(height: SidebarMetrics.rowHeight)
        .background { RowHighlight(isSelected: isSelected, isInGroup: isInGroup) }
        .hoverHighlight(suppressed: isSelected || isInGroup, isHovered: $isHovered)
        .overlay { TabDropIndicator(shell: shell, tab: tab, depth: depth) }
        .overlay { SidebarFocusRing(shell: shell, tab: tab, cornerRadius: SidebarMetrics.rowCornerRadius) }
        .reportsSidebarRowFrame(of: tab, to: shell.sidebarDrag)
        .contentShape(Rectangle())
        .onTapGesture {
            Haptics.controlActivated(.press)
            shell.clickRow(tab)
        }
        .onDrag { shell.sidebarDrag.beginDrag(tab) }
        .onDrop(of: SidebarDragModel.acceptedTypes, delegate: TabRowDropDelegate(shell: shell, tab: tab))
        .contextMenu {
            if let group = shell.groupTabs(including: tab) {
                GroupTabMenu(shell: shell, tabs: group)
            } else {
                menu
            }
        }
    }

    @ViewBuilder
    private var menu: some View {
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
            Divider()
            Button("Archive Tab") { shell.archiveTabs([tab]) }
            Button("Close Tab") { shell.performUndoable("Close Tab") { shell.store.close(tab) } }
        }
    }

    private var canOpenInSplitView: Bool {
        guard let selected = shell.store.selectedTab else { return false }
        return selected !== tab && !selected.isPinned
    }

    @ViewBuilder
    private var disclosure: some View {
        if tab.children.isEmpty {
            Color.clear.frame(width: SidebarMetrics.disclosureSize, height: SidebarMetrics.disclosureSize)
        } else {
            Image(systemName: "chevron.right")
                .font(InterfaceFont.accessorySymbol)
                .foregroundStyle(.tertiary)
                .rotationEffect(.degrees(tab.isCollapsed ? 0 : 90))
                .animation(.easeOut(duration: 0.15), value: tab.isCollapsed)
                .frame(width: SidebarMetrics.disclosureSize, height: SidebarMetrics.disclosureSize)
                .contentShape(Rectangle())
                .onTapGesture { shell.store.toggleCollapse(tab) }
        }
    }
}

struct SplitTabRowView: View {
    let shell: ShellController
    let split: TabSplit
    let depth: Int

    @Environment(\.sidebarStore) private var sidebarStore

    private var store: TabStore { sidebarStore ?? shell.store }

    private var isSelected: Bool {
        store.selectedTab.map(split.contains) ?? false
    }

    var body: some View {
        HStack(spacing: SidebarMetrics.accessorySpacing) {
            Color.clear.frame(width: SidebarMetrics.disclosureSize, height: SidebarMetrics.disclosureSize)
            SplitTabHalfView(shell: shell, tab: split.leading, isPairSelected: isSelected)
            Rectangle()
                .fill(.separator)
                .frame(width: 1, height: SidebarMetrics.iconSize)
            SplitTabHalfView(shell: shell, tab: split.trailing, isPairSelected: isSelected)
        }
        .padding(.leading, SidebarMetrics.indent(depth: depth))
        .padding(.trailing, SidebarMetrics.rowLeadingPadding)
        .frame(height: SidebarMetrics.rowHeight)
        .background { RowHighlight(isSelected: isSelected, isInGroup: store.rowSelection.contains(split.leading.id)) }
        .hoverHighlight(suppressed: isSelected || store.rowSelection.contains(split.leading.id))
        .overlay { TabDropIndicator(shell: shell, tab: split.leading, depth: depth) }
        .overlay { SidebarFocusRing(shell: shell, tab: split.leading, cornerRadius: SidebarMetrics.rowCornerRadius) }
        .reportsSidebarRowFrame(of: split.leading, to: shell.sidebarDrag)
        .contentShape(Rectangle())
        .onDrag { shell.sidebarDrag.beginDrag(split.leading) }
        .onDrop(of: SidebarDragModel.acceptedTypes, delegate: TabRowDropDelegate(shell: shell, tab: split.leading))
        .contextMenu {
            if let group = shell.groupTabs(including: split.leading) {
                GroupTabMenu(shell: shell, tabs: group)
            } else {
                splitMenu
            }
        }
    }

    @ViewBuilder
    private var splitMenu: some View {
        Button("Separate Tabs") { shell.performUndoable("Separate Tabs") { shell.store.unsplit(split) } }
        Button("Close \(split.leading.displayTitle)") { shell.performUndoable("Close Tab") { shell.store.close(split.leading) } }
        Button("Close \(split.trailing.displayTitle)") { shell.performUndoable("Close Tab") { shell.store.close(split.trailing) } }
    }
}

private struct SplitTabHalfView: View {
    let shell: ShellController
    let tab: Tab
    let isPairSelected: Bool

    @State private var isHovered = false

    @Environment(\.sidebarStore) private var sidebarStore

    private var store: TabStore { sidebarStore ?? shell.store }

    private var isFocused: Bool { store.selectedTab === tab }

    var body: some View {
        HStack(spacing: SidebarMetrics.accessorySpacing) {
            Group {
                TabIconView(tab: tab, size: SidebarMetrics.iconSize)
                    .opacity(tab.isLoading ? 0.4 : 1)
                    .animation(.easeInOut(duration: 0.3), value: tab.isLoading)
                    .overlay(alignment: .topTrailing) { UnreadBadgeView(tab: tab) }
                Text(tab.displayTitle)
                    .fadingTruncation()
                    .foregroundStyle(isFocused ? .primary : .secondary)
            }
            .opacity(isPairSelected || isHovered ? 1 : tab.idleFade)
            Spacer(minLength: 0)
            AudioToggleButton(shell: shell, tab: tab)
            if isHovered {
                Button {
                    shell.performUndoable("Close Tab") { shell.store.close(tab) }
                } label: {
                    Image(systemName: "xmark")
                        .font(InterfaceFont.accessorySymbol)
                        .foregroundStyle(.secondary)
                        .frame(width: SidebarMetrics.accessorySize, height: SidebarMetrics.accessorySize)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .focusable(false)
                .hapticFeedback(.press)
                .help("Close Tab")
            }
        }
        .padding(.horizontal, SidebarMetrics.rowLeadingPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            if isPairSelected && isFocused {
                RoundedRectangle(cornerRadius: SidebarMetrics.rowCornerRadius - SidebarMetrics.rowLeadingPadding, style: .continuous)
                    .fill(.fill.tertiary)
                    .padding(.vertical, SidebarMetrics.rowLeadingPadding)
            }
        }
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
        .onTapGesture {
            Haptics.controlActivated(.press)
            shell.clickRow(tab)
        }
    }
}
