import AppKit
import CMiniCore
import Observation
import SwiftUI
import UniformTypeIdentifiers

@MainActor
@Observable
final class SidebarDragModel {
    enum Target: Equatable {
        case row(MiniTabId, TabDropPosition)
        case pinned(Int)
        case savedEnd
        case end
    }

    private(set) var draggedTab: Tab?
    var target: Target?

    @ObservationIgnored private var releaseTimer: Timer?

    static let acceptedTypes: [UTType] = [.text]

    func beginDrag(_ tab: Tab) -> NSItemProvider {
        draggedTab = tab
        target = nil
        releaseTimer?.invalidate()
        let timer = Timer(timeInterval: 0.2, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard NSEvent.pressedMouseButtons & 1 == 0 else { return }
                self?.end()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        releaseTimer = timer
        return NSItemProvider(object: "mini-tab:\(tab.id)" as NSString)
    }

    func end() {
        releaseTimer?.invalidate()
        releaseTimer = nil
        draggedTab = nil
        target = nil
    }

    var isDraggingUnpinnedTab: Bool {
        draggedTab.map { !$0.isPinned && !$0.url.isEmpty } ?? false
    }

    var isDraggingUnsavedTab: Bool {
        draggedTab.map { !$0.isSaved && !$0.url.isEmpty } ?? false
    }
}

struct TabRowDropDelegate: DropDelegate {
    let shell: ShellController
    let tab: Tab

    private var model: SidebarDragModel { shell.sidebarDrag }

    private func dropPosition(_ info: DropInfo) -> TabDropPosition {
        let height = SidebarMetrics.rowHeight
        if info.location.y < height * 0.25 { return .before }
        if info.location.y > height * 0.75 { return .after }
        return .inside
    }

    func validateDrop(info: DropInfo) -> Bool {
        guard let dragged = model.draggedTab else { return false }
        return shell.store.canMove(dragged, relativeTo: tab)
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        guard validateDrop(info: info) else { return DropProposal(operation: .forbidden) }
        model.target = .row(tab.id, dropPosition(info))
        return DropProposal(operation: .move)
    }

    func dropExited(info: DropInfo) {
        if case .row(tab.id, _) = model.target { model.target = nil }
    }

    func performDrop(info: DropInfo) -> Bool {
        guard let dragged = model.draggedTab, shell.store.canMove(dragged, relativeTo: tab) else { return false }
        shell.performUndoable(dragged.isPinned ? "Unpin Tab" : "Move Tab") { shell.store.move(dragged, relativeTo: tab, position: dropPosition(info)) }
        model.end()
        return true
    }
}

struct PinnedDropDelegate: DropDelegate {
    let shell: ShellController
    let index: Int

    private var model: SidebarDragModel { shell.sidebarDrag }

    func validateDrop(info: DropInfo) -> Bool {
        guard let dragged = model.draggedTab else { return false }
        return dragged.isPinned || !dragged.url.isEmpty
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        guard validateDrop(info: info) else { return DropProposal(operation: .forbidden) }
        model.target = .pinned(index)
        return DropProposal(operation: .move)
    }

    func dropExited(info: DropInfo) {
        if model.target == .pinned(index) { model.target = nil }
    }

    func performDrop(info: DropInfo) -> Bool {
        guard let dragged = model.draggedTab, validateDrop(info: info) else { return false }
        if dragged.isPinned {
            shell.performUndoable("Move Tab") { shell.store.movePinned(dragged, to: index) }
        } else {
            shell.performUndoable("Pin Tab") { shell.store.pin(dragged, at: index) }
        }
        model.end()
        return true
    }
}

struct TabListEndDropDelegate: DropDelegate {
    let shell: ShellController

    private var model: SidebarDragModel { shell.sidebarDrag }

    func validateDrop(info: DropInfo) -> Bool {
        model.draggedTab != nil
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        guard validateDrop(info: info) else { return DropProposal(operation: .forbidden) }
        model.target = .end
        return DropProposal(operation: .move)
    }

    func dropExited(info: DropInfo) {
        if model.target == .end { model.target = nil }
    }

    func performDrop(info: DropInfo) -> Bool {
        guard let dragged = model.draggedTab else { return false }
        shell.performUndoable(dragged.isPinned ? "Unpin Tab" : "Move Tab") { shell.store.moveToEnd(dragged) }
        model.end()
        return true
    }
}

struct TabDropIndicator: View {
    let shell: ShellController
    let tab: Tab
    let depth: Int

    var body: some View {
        if case .row(tab.id, let position) = shell.sidebarDrag.target {
            switch position {
            case .before:
                InsertionLine(depth: depth).frame(maxHeight: .infinity, alignment: .top)
            case .after:
                InsertionLine(depth: depth).frame(maxHeight: .infinity, alignment: .bottom)
            case .inside:
                RoundedRectangle(cornerRadius: SidebarMetrics.rowCornerRadius, style: .continuous)
                    .fill(.tint.opacity(0.18))
                    .strokeBorder(.tint.opacity(0.8), lineWidth: 1.5)
            }
        }
    }
}

struct InsertionLine: View {
    let depth: Int

    var body: some View {
        Capsule()
            .fill(.tint)
            .frame(height: 2)
            .padding(.leading, 4 + CGFloat(depth) * SidebarMetrics.indentation)
            .allowsHitTesting(false)
    }
}
