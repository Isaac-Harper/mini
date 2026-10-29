import SwiftUI

struct SavedSectionHeader: View {
    var body: some View {
        Text("Saved")
            .font(InterfaceFont.sectionHeader)
            .foregroundStyle(.tertiary)
            .padding(.leading, SidebarMetrics.footerRowPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: SidebarMetrics.sectionHeaderHeight)
    }
}

struct SavedSectionDivider: View {
    var body: some View {
        Rectangle()
            .fill(.separator)
            .frame(height: 1)
            .padding(.horizontal, SidebarMetrics.footerRowPadding)
            .frame(height: SidebarMetrics.sectionDividerHeight)
    }
}

struct SaveDropRow: View {
    let shell: ShellController

    private var isTargeted: Bool { shell.sidebarDrag.target == .savedEnd }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: SidebarMetrics.rowCornerRadius, style: .continuous)
        HStack(spacing: SidebarMetrics.iconSpacing) {
            Image(systemName: "bookmark")
                .font(InterfaceFont.controlSymbol)
            Text("Drop to Save")
        }
        .foregroundStyle(isTargeted ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
        .frame(maxWidth: .infinity)
        .frame(height: SidebarMetrics.rowHeight)
        .background(shape.fill(isTargeted ? AnyShapeStyle(.tint.opacity(0.15)) : AnyShapeStyle(.clear)))
        .overlay(shape.strokeBorder(isTargeted ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary.opacity(0.5)), style: StrokeStyle(lineWidth: 1.5, dash: [4, 3])))
        .padding(.top, SidebarMetrics.accessorySpacing)
        .onDrop(of: SidebarDragModel.acceptedTypes, delegate: SavedEndDropDelegate(shell: shell))
    }
}

struct SavedEndDropDelegate: DropDelegate {
    let shell: ShellController

    private var model: SidebarDragModel { shell.sidebarDrag }

    func validateDrop(info: DropInfo) -> Bool {
        model.isDraggingUnsavedTab
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        guard validateDrop(info: info) else { return DropProposal(operation: .forbidden) }
        model.target = .savedEnd
        return DropProposal(operation: .move)
    }

    func dropExited(info: DropInfo) {
        if model.target == .savedEnd { model.target = nil }
    }

    func performDrop(info: DropInfo) -> Bool {
        guard let dragged = model.draggedTab, validateDrop(info: info) else { return false }
        model.drop(dragged) {
            shell.performUndoable("Save Tab") { shell.store.save(dragged) }
        }
        model.end()
        return true
    }
}
