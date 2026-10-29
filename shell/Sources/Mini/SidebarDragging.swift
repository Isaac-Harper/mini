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
    var target: Target? {
        didSet { noteDetent() }
    }
    var isPastTearOff = false {
        didSet { noteDetent() }
    }
    var isDockingWindow = false

    @ObservationIgnored var rowFrames: [MiniTabId: CGRect] = [:]
    @ObservationIgnored var onPointerMoved: ((Tab, NSPoint, Bool) -> Void)?
    @ObservationIgnored var onEnd: (() -> Void)?
    @ObservationIgnored var isSavedRow: ((MiniTabId) -> Bool)?
    @ObservationIgnored private var detent = DetentChange<TabDragDetent>()
    @ObservationIgnored private var releaseTimer: Timer?

    static let acceptedTypes: [UTType] = [.text]

    func beginDrag(_ tab: Tab) -> NSItemProvider {
        draggedTab = tab
        detent.reset()
        target = nil
        isPastTearOff = false
        releaseTimer?.invalidate()
        let timer = Timer(timeInterval: 1.0 / 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, let tab = self.draggedTab else { return }
                let isReleased = NSEvent.pressedMouseButtons & 1 == 0
                self.onPointerMoved?(tab, NSEvent.mouseLocation, isReleased)
                if isReleased {
                    self.end()
                }
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
        isPastTearOff = false
        detent.reset()
        onEnd?()
    }

    func drop(_ tab: Tab, _ perform: () -> Void) {
        let before = TabPlacement(of: tab)
        perform()
        if TabPlacement(of: tab) != before {
            Haptics.tabDropChangedPlacement()
        }
    }

    private func noteDetent() {
        guard draggedTab != nil else { return }
        let current = TabDragDetent.of(target, isPastTearOff: isPastTearOff) { [isSavedRow] identifier in isSavedRow?(identifier) ?? false }
        if detent.update(current) {
            Haptics.tabDragTargetChanged()
        }
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
        model.drop(dragged) {
            shell.performUndoable(dragged.isPinned ? "Unpin Tab" : "Move Tab") { shell.store.move(dragged, relativeTo: tab, position: dropPosition(info)) }
        }
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
        model.drop(dragged) {
            if dragged.isPinned {
                shell.performUndoable("Move Tab") { shell.store.movePinned(dragged, to: index) }
            } else {
                shell.performUndoable("Pin Tab") { shell.store.pin(dragged, at: index) }
            }
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
        model.drop(dragged) {
            shell.performUndoable(dragged.isPinned ? "Unpin Tab" : "Move Tab") { shell.store.moveToEnd(dragged) }
        }
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

extension EnvironmentValues {
    @Entry var reportsSidebarRowFrames = false
}

private struct SidebarRowFrameReporter: ViewModifier {
    let tab: Tab
    let model: SidebarDragModel

    @Environment(\.reportsSidebarRowFrames) private var reportsFrames

    func body(content: Content) -> some View {
        if reportsFrames {
            content.onGeometryChange(for: CGRect.self, of: { $0.frame(in: .global) }) { frame in
                model.rowFrames[tab.id] = frame
            }
        } else {
            content
        }
    }
}

extension View {
    func reportsSidebarRowFrame(of tab: Tab, to model: SidebarDragModel) -> some View {
        modifier(SidebarRowFrameReporter(tab: tab, model: model))
    }
}
