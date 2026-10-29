import SwiftUI

struct PinnedTabsView: View {
    let shell: ShellController

    private let columns = [GridItem(.adaptive(minimum: SidebarMetrics.pinnedTileMinimumWidth), spacing: SidebarMetrics.pinnedTileSpacing)]

    @Environment(\.sidebarStore) private var sidebarStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var store: TabStore { sidebarStore ?? shell.store }

    var body: some View {
        GlassEffectContainer(spacing: SidebarMetrics.pinnedTileSpacing) {
            LazyVGrid(columns: columns, spacing: SidebarMetrics.pinnedTileSpacing) {
                ForEach(Array(store.pinnedTabs.enumerated()), id: \.element.id) { index, tab in
                    PinnedTabTile(shell: shell, tab: tab, index: index)
                }
                if shell.sidebarDrag.isDraggingUnpinnedTab {
                    PinDropTile(shell: shell, index: store.pinnedTabs.count)
                }
            }
        }
        .animation(reduceMotion ? .easeInOut(duration: 0.12) : .spring(duration: 0.28, bounce: 0.12), value: store.selectedTab?.id)
    }
}

private struct PinDropTile: View {
    let shell: ShellController
    let index: Int

    private var isTargeted: Bool { shell.sidebarDrag.target == .pinned(index) }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: SidebarMetrics.pinnedTileCornerRadius, style: .continuous)
        Image(systemName: "pin")
            .font(InterfaceFont.controlSymbol)
            .foregroundStyle(isTargeted ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
            .frame(maxWidth: .infinity)
            .frame(height: SidebarMetrics.pinnedTileHeight)
            .background(shape.fill(isTargeted ? AnyShapeStyle(.tint.opacity(0.15)) : AnyShapeStyle(.clear)))
            .overlay(shape.strokeBorder(isTargeted ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary.opacity(0.5)), style: StrokeStyle(lineWidth: 1.5, dash: [4, 3])))
            .help("Drop to Pin")
            .onDrop(of: SidebarDragModel.acceptedTypes, delegate: PinnedDropDelegate(shell: shell, index: index))
    }
}

private struct PinnedTabTile: View {
    let shell: ShellController
    let tab: Tab
    let index: Int

    private var isDropTarget: Bool { shell.sidebarDrag.target == .pinned(index) }

    @Environment(\.sidebarStore) private var sidebarStore

    private var store: TabStore { sidebarStore ?? shell.store }

    private var isSelected: Bool { store.selectedTab === tab }

    @Environment(\.selectionNamespace) private var namespace

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: SidebarMetrics.pinnedTileCornerRadius, style: .continuous)
        ZStack {
            if isSelected {
                if let namespace {
                    shape.fill(.tint.opacity(0.22)).matchedGeometryEffect(id: "pinnedSelection", in: namespace)
                } else {
                    shape.fill(.tint.opacity(0.22))
                }
            }
            TabIconView(tab: tab, size: SidebarMetrics.iconSize)
                .overlay(alignment: .topTrailing) { UnreadBadgeView(tab: tab, isOnTile: true) }
        }
        .frame(maxWidth: .infinity)
        .frame(height: SidebarMetrics.pinnedTileHeight)
        .hoverHighlight(cornerRadius: SidebarMetrics.pinnedTileCornerRadius, suppressed: isSelected)
        .glassEffect(.regular.interactive(), in: shape)
        .overlay(alignment: .topTrailing) {
            AudioToggleButton(shell: shell, tab: tab).offset(x: 4, y: -4)
        }
        .overlay(alignment: .leading) {
            if isDropTarget {
                Capsule().fill(.tint).frame(width: 2).padding(.vertical, SidebarMetrics.rowTrailingPadding).offset(x: -(SidebarMetrics.pinnedTileSpacing + 2) / 2).allowsHitTesting(false)
            }
        }
        .overlay { SidebarFocusRing(shell: shell, tab: tab, cornerRadius: SidebarMetrics.pinnedTileCornerRadius) }
        .contentShape(shape)
        .help(tab.displayTitle)
        .onTapGesture {
            Haptics.controlActivated(.press)
            shell.clearRowSelection()
            shell.store.select(tab)
        }
        .onDrag { shell.sidebarDrag.beginDrag(tab) }
        .onDrop(of: SidebarDragModel.acceptedTypes, delegate: PinnedDropDelegate(shell: shell, index: index))
        .contextMenu {
            Button("Duplicate Tab") { shell.duplicate(tab) }
            Button("Unpin Tab") { shell.performUndoable("Unpin Tab") { shell.store.unpin(tab) } }
            Button("Save Tab") { shell.performUndoable("Save Tab") { shell.store.save(tab) } }
            Button("Close Tab") { shell.performUndoable("Close Tab") { shell.store.close(tab) } }
        }
    }
}
