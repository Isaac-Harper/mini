import SwiftUI

struct PinnedTabsView: View {
    let shell: ShellController

    private let columns = [GridItem(.adaptive(minimum: 44), spacing: 8)]

    var body: some View {
        GlassEffectContainer(spacing: 8) {
            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(Array(shell.store.pinnedTabs.enumerated()), id: \.element.id) { index, tab in
                    PinnedTabTile(shell: shell, tab: tab, index: index)
                }
                if shell.sidebarDrag.isDraggingUnpinnedTab {
                    PinDropTile(shell: shell, index: shell.store.pinnedTabs.count)
                }
            }
        }
    }
}

private struct PinDropTile: View {
    let shell: ShellController
    let index: Int

    private var isTargeted: Bool { shell.sidebarDrag.target == .pinned(index) }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
        Image(systemName: "pin")
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(isTargeted ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
            .frame(maxWidth: .infinity)
            .frame(height: 40)
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

    private var isSelected: Bool { shell.store.selectedTab === tab }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
        TabIconView(tab: tab, size: 18)
            .frame(maxWidth: .infinity)
            .frame(height: 40)
            .glassEffect(isSelected ? .regular.tint(Color(nsColor: shell.currentSpace.color.accent).opacity(0.22)).interactive() : .regular.interactive(), in: shape)
            .overlay(alignment: .topTrailing) {
                AudioToggleButton(shell: shell, tab: tab).offset(x: 4, y: -4)
            }
            .overlay(alignment: .leading) {
                if isDropTarget {
                    Capsule().fill(.tint).frame(width: 2).padding(.vertical, 6).offset(x: -5).allowsHitTesting(false)
                }
            }
            .overlay { SidebarFocusRing(shell: shell, tab: tab, cornerRadius: 12) }
            .contentShape(shape)
            .help(tab.displayTitle)
            .onTapGesture { shell.store.select(tab) }
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
