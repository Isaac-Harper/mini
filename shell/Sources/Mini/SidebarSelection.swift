import AppKit
import CMiniCore
import SwiftUI

extension ShellController {
    var selectedRowTabs: [Tab] {
        guard store.rowSelection.isMultiple else { return [] }
        return store.rowSelection.identifiers.compactMap(store.tab(withIdentifier:))
    }

    func groupTabs(including tab: Tab) -> [Tab]? {
        let tabs = selectedRowTabs
        return tabs.contains { $0 === tab } ? tabs : nil
    }

    func clickRow(_ tab: Tab, modifiers: NSEvent.ModifierFlags = NSEvent.modifierFlags) {
        let modifiers = modifiers.intersection([.command, .shift, .option, .control])
        let order = store.visibleTabs.map(\.id)
        let active = store.selectedTab.flatMap { $0.isPinned ? nil : visibleRowIdentifier(of: $0) }
        switch modifiers {
        case .shift:
            store.rowSelection.extend(to: tab.id, active: active, in: order)
        case .command:
            store.rowSelection.toggle(tab.id, active: active, in: order)
        default:
            store.rowSelection.clear()
            store.select(tab)
            return
        }
        if store.rowSelection.isMultiple, windowController.isSidebarVisible, windowController.focusSidebar() {
            sidebarKeyboard.showsRing = false
            sidebarKeyboard.focusedTabIdentifier = tab.id
        }
    }

    func extendRowSelection(by offset: Int, from focused: Tab) -> Tab? {
        let order = store.visibleTabs.map(\.id)
        guard let next = store.rowSelection.extend(by: offset, from: focused.id, in: order) else { return nil }
        return store.tab(withIdentifier: next)
    }

    func clearRowSelection() {
        store.rowSelection.clear()
    }

    private func visibleRowIdentifier(of tab: Tab) -> MiniTabId? {
        store.visibleTabs.first { $0.tab === tab || $0.split?.contains(tab) == true }?.id
    }

    private func withSplitPartners(_ tabs: [Tab]) -> [Tab] {
        tabs.flatMap { tab in [tab] + (store.split(containing: tab).flatMap { $0.partner(of: tab) }.map { [$0] } ?? []) }
    }

    private func outermost(_ tabs: [Tab]) -> [Tab] {
        tabs.filter { tab in !tabs.contains { tab.isDescendant(of: $0) } }
    }

    func closeTabs(_ tabs: [Tab]) {
        let targets = outermost(withSplitPartners(tabs))
        store.rowSelection.clear()
        performUndoable(targets.count == 1 ? "Close Tab" : "Close Tabs") {
            for tab in targets where store.tab(withIdentifier: tab.id) === tab {
                store.close(tab)
            }
        }
    }

    func archiveTabs(_ tabs: [Tab]) {
        let targets = outermost(withSplitPartners(tabs)).filter { !$0.isPinned && !$0.isSaved }
        let now = Date()
        let entries = targets.flatMap(\.subtree).filter { !$0.url.isEmpty }
            .map { ArchivedTab(url: $0.url, title: $0.displayTitle, archivedAt: now, spaceIdentifier: currentSpace.id) }
        store.rowSelection.clear()
        performUndoable(targets.count == 1 ? "Archive Tab" : "Archive Tabs", archiving: entries) {
            for tab in targets where store.tab(withIdentifier: tab.id) === tab {
                store.remove(tab)
            }
        }
    }

    func pinTabs(_ tabs: [Tab]) {
        store.rowSelection.clear()
        performUndoable(tabs.count == 1 ? "Pin Tab" : "Pin Tabs") {
            for tab in tabs { store.pin(tab) }
        }
    }

    func saveTabs(_ tabs: [Tab]) {
        let targets = outermost(withSplitPartners(tabs)).filter(store.canSave)
        store.rowSelection.clear()
        performUndoable(targets.count == 1 ? "Save Tab" : "Save Tabs") {
            for tab in targets { store.save(tab) }
        }
    }

    func makeTabsRegular(_ tabs: [Tab]) {
        let targets = outermost(withSplitPartners(tabs)).filter(\.isSaved)
        store.rowSelection.clear()
        performUndoable(targets.count == 1 ? "Remove from Saved" : "Make Tabs Regular") {
            for tab in targets.reversed() { store.unsave(tab) }
        }
    }

    func copyLinks(_ tabs: [Tab]) {
        let lines = withSplitPartners(tabs).filter { !$0.url.isEmpty }.map { "\($0.displayTitle)\n\($0.url)" }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(lines.joined(separator: "\n"), forType: .string)
        toast.show("Copied")
    }

    func openInSplitView(_ tabs: [Tab]) {
        guard tabs.count == 2 else { preconditionFailure("Split view needs exactly two tabs") }
        store.rowSelection.clear()
        performUndoable("Open in Split View") {
            store.makeSplit(leading: tabs[0], trailing: tabs[1])
            store.select(tabs[0])
        }
    }

    func moveTabs(_ tabs: [Tab], relativeTo target: Tab, position: TabDropPosition) {
        let movable = outermost(withSplitPartners(tabs)).filter { store.canMove($0, relativeTo: target) }
        store.rowSelection.clear()
        performUndoable("Move Tabs") {
            switch position {
            case .before, .inside:
                for tab in movable { store.move(tab, relativeTo: target, position: position) }
            case .after:
                var previous = target
                for tab in movable {
                    store.move(tab, relativeTo: previous, position: .after)
                    previous = tab
                }
            }
        }
    }

    func moveTabsToEnd(_ tabs: [Tab]) {
        let movable = outermost(withSplitPartners(tabs))
        store.rowSelection.clear()
        performUndoable("Move Tabs") {
            for tab in movable { store.moveToEnd(tab) }
        }
    }

    func pinTabs(_ tabs: [Tab], at index: Int) {
        store.rowSelection.clear()
        performUndoable("Pin Tabs") {
            for (offset, tab) in tabs.enumerated() { store.pin(tab, at: index + offset) }
        }
    }
}

struct GroupTabMenu: View {
    let shell: ShellController
    let tabs: [Tab]

    var body: some View {
        let count = tabs.count
        let savable = tabs.filter { !$0.isSaved }.count
        let saved = count - savable
        if count == 2 {
            Button("Open in Split View") { shell.openInSplitView(tabs) }
        }
        Button("Copy \(count) Links") { shell.copyLinks(tabs) }
        Divider()
        Button("Pin \(count) Tabs") { shell.pinTabs(tabs) }
        if savable > 0 {
            Button(savable == 1 ? "Save Tab" : "Save \(savable) Tabs") { shell.saveTabs(tabs) }
        }
        if saved > 0 {
            Button(saved == 1 ? "Make Tab Regular" : "Make \(saved) Tabs Regular") { shell.makeTabsRegular(tabs) }
        }
        Divider()
        if savable > 0 {
            Button(savable == 1 ? "Archive Tab" : "Archive \(savable) Tabs") { shell.archiveTabs(tabs) }
        }
        Button("Close \(count) Tabs") { shell.closeTabs(tabs) }
    }
}

struct RowHighlight: View {
    let isSelected: Bool
    let isInGroup: Bool
    var cornerRadius = SidebarMetrics.rowCornerRadius

    @Environment(\.selectionNamespace) private var namespace

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        ZStack {
            if isSelected {
                if let namespace {
                    SelectionHighlight(shape: shape).matchedGeometryEffect(id: "selection", in: namespace)
                } else {
                    SelectionHighlight(shape: shape)
                }
            } else if isInGroup {
                shape.fill(.tint.opacity(0.12))
            }
        }
    }
}

extension EnvironmentValues {
    @Entry var selectionNamespace: Namespace.ID? = nil
}
