import AppKit
import CMiniCore

@MainActor
struct TabArrangementSnapshot {
    @MainActor
    struct Node {
        let tab: Tab
        let url: String
        let title: String
        let favicon: NSImage?
        let pinnedURL: String?
        let savedURL: String?
        let savedTitle: String
        let isCollapsed: Bool
        let children: [Node]

        init(_ tab: Tab) {
            self.tab = tab
            url = tab.url
            title = tab.title
            favicon = tab.favicon
            pinnedURL = tab.pinnedURL
            savedURL = tab.savedURL
            savedTitle = tab.savedTitle
            isCollapsed = tab.isCollapsed
            children = tab.children.map(Node.init)
        }

        var subtree: [Node] { [self] + children.flatMap(\.subtree) }

        var signature: String {
            "\(tab.id)|\(pinnedURL ?? "")|\(savedURL ?? "")|\(isCollapsed)(\(children.map(\.signature).joined(separator: ",")))"
        }
    }

    @MainActor
    struct Split {
        let leading: Tab
        let trailing: Tab
        let fraction: Double
    }

    let pinned: [Node]
    let savedRoots: [Node]
    let roots: [Node]
    let splits: [Split]
    let selected: Tab?

    init(of store: TabStore) {
        pinned = store.pinnedTabs.map(Node.init)
        savedRoots = store.savedRootTabs.map(Node.init)
        roots = store.rootTabs.map(Node.init)
        splits = store.splits.map { Split(leading: $0.leading, trailing: $0.trailing, fraction: $0.fraction) }
        selected = store.selectedTab
    }

    var nodes: [Node] { (pinned + savedRoots + roots).flatMap(\.subtree) }

    var signature: String {
        let tree = [pinned, savedRoots, roots].map { $0.map(\.signature).joined(separator: ";") }.joined(separator: "/")
        let pairs = splits.map { "\($0.leading.id)-\($0.trailing.id)" }.joined(separator: ",")
        return tree + "#" + pairs
    }
}

@MainActor
final class TabUndoRecord {
    let actionName: String
    let target: TabArrangementSnapshot
    let source: TabArrangementSnapshot

    init(actionName: String, target: TabArrangementSnapshot, source: TabArrangementSnapshot) {
        self.actionName = actionName
        self.target = target
        self.source = source
    }

    var inverse: TabUndoRecord {
        TabUndoRecord(actionName: actionName, target: source, source: target)
    }
}

extension ShellController {
    func performUndoable(_ actionName: String, _ action: () -> Void) {
        let store = self.store
        let before = TabArrangementSnapshot(of: store)
        action()
        let after = TabArrangementSnapshot(of: store)
        guard before.signature != after.signature else { return }
        register(TabUndoRecord(actionName: actionName, target: before, source: after), in: store)
    }

    func forgetTabUndo(for store: TabStore) {
        tabUndoManager.removeAllActions(withTarget: store)
    }

    private var mainWindowTakesCommands: Bool {
        NSApp.keyWindow.map { $0 === window } ?? true
    }

    var undoRoutesToTabs: Bool {
        guard mainWindowTakesCommands, !isOverlayActive else { return false }
        let responder = window.firstResponder
        if responder is NSText { return false }
        if let view = responder as? NSView, let tab = displayedTabs.first(where: { view.isDescendant(of: $0.hostView) }) {
            return tab.hasBrowser && !mini_browser_has_editable_focus(tab.id)
        }
        return true
    }

    func pageUndoKeyPressed(_ event: NSEvent, in identifier: MiniTabId, redo: Bool) -> Bool {
        pageUndoKeyTimestamp = event.timestamp
        guard mainWindowTakesCommands, !isOverlayActive,
              let tab = store.tab(withIdentifier: identifier), displayedTabs.contains(where: { $0 === tab }),
              tab.hasBrowser, !mini_browser_has_editable_focus(identifier)
        else { return false }
        let undoManager = tabUndoManager
        if redo {
            guard undoManager.canRedo else { return false }
            undoManager.redo()
        } else {
            guard undoManager.canUndo else { return false }
            undoManager.undo()
        }
        return true
    }

    func updateUndoMenuItems(in menu: NSMenu) {
        let routesToTabs = undoRoutesToTabs
        let undoManager = tabUndoManager
        for item in menu.items {
            switch item.tag {
            case MainMenu.undoItemTag:
                item.target = routesToTabs ? self : nil
                item.action = routesToTabs ? #selector(undoTabAction(_:)) : Selector(("undo:"))
                item.title = routesToTabs ? undoManager.undoMenuItemTitle : "Undo"
            case MainMenu.redoItemTag:
                item.target = routesToTabs ? self : nil
                item.action = routesToTabs ? #selector(redoTabAction(_:)) : Selector(("redo:"))
                item.title = routesToTabs ? undoManager.redoMenuItemTitle : "Redo"
            default:
                break
            }
        }
    }

    @objc func undoTabAction(_ sender: Any?) {
        guard !isRedispatchedPageUndoKey else { return }
        tabUndoManager.undo()
    }

    @objc func redoTabAction(_ sender: Any?) {
        guard !isRedispatchedPageUndoKey else { return }
        tabUndoManager.redo()
    }

    private var isRedispatchedPageUndoKey: Bool {
        guard let event = NSApp.currentEvent, event.type == .keyDown, let pageUndoKeyTimestamp else { return false }
        return event.timestamp == pageUndoKeyTimestamp
    }

    private func register(_ record: TabUndoRecord, in store: TabStore) {
        let undoManager = tabUndoManager
        undoManager.beginUndoGrouping()
        undoManager.registerUndo(withTarget: store) { [weak self] store in
            MainActor.assumeIsolated {
                self?.apply(record, in: store)
            }
        }
        undoManager.setActionName(record.actionName)
        undoManager.endUndoGrouping()
    }

    private func apply(_ record: TabUndoRecord, in store: TabStore) {
        let space = space(of: store)
        if space !== currentSpace {
            switchToSpace(space)
        }
        restore(record.target, replacing: record.source, in: store)
        register(record.inverse, in: store)
    }

    private func liveTab(for tab: Tab, in store: TabStore) -> Tab? {
        if store.tab(withIdentifier: tab.id) === tab { return tab }
        return tabUndoReplacements[tab.id].flatMap { liveTab(for: $0, in: store) }
    }

    private func restore(_ target: TabArrangementSnapshot, replacing source: TabArrangementSnapshot, in store: TabStore) {
        let targetLive = Set(target.nodes.compactMap { liveTab(for: $0.tab, in: store) }.map(ObjectIdentifier.init))
        let closing = source.nodes
            .compactMap { liveTab(for: $0.tab, in: store) }
            .filter { !targetLive.contains(ObjectIdentifier($0)) }
        let closingIdentifiers = Set(closing.map(ObjectIdentifier.init))
        let extras = store.allTabs.filter { tab in
            !targetLive.contains(ObjectIdentifier(tab)) && !closingIdentifiers.contains(ObjectIdentifier(tab))
        }
        let extraIdentifiers = Set(extras.map(ObjectIdentifier.init))
        let extraRoots = extras.filter { tab in tab.parent.map { !extraIdentifiers.contains(ObjectIdentifier($0)) } ?? true }
        let extraPlacements = extraRoots.map { tab in
            (tab: tab,
             wasPinned: tab.isPinned,
             parent: tab.parent.flatMap { targetLive.contains(ObjectIdentifier($0)) ? $0 : nil },
             index: tab.isPinned
                 ? (store.pinnedTabs.firstIndex { $0 === tab } ?? 0)
                 : ((tab.parent?.children ?? (tab.isSaved ? store.savedRootTabs : store.rootTabs)).firstIndex { $0 === tab } ?? 0))
        }

        var resolved: [MiniTabId: Tab] = [:]
        var revived: [Tab] = []
        func build(_ node: TabArrangementSnapshot.Node) -> Tab {
            let tab: Tab
            if let live = liveTab(for: node.tab, in: store) {
                tab = live
            } else {
                tab = store.makeDetachedTab(url: node.url)
                tab.title = node.title
                tab.favicon = node.favicon
                tabUndoReplacements[node.tab.id] = tab
                revived.append(tab)
            }
            resolved[node.tab.id] = tab
            tab.pinnedURL = node.pinnedURL
            tab.savedURL = node.savedURL
            tab.savedTitle = node.savedTitle
            tab.isCollapsed = node.isCollapsed
            tab.children = node.children.map(build)
            for child in tab.children {
                child.parent = tab
            }
            return tab
        }
        var pinned = target.pinned.map(build)
        var savedRoots = target.savedRoots.map(build)
        var roots = target.roots.map(build)
        for tab in pinned + savedRoots + roots {
            tab.parent = nil
        }
        for tab in extras {
            tab.children = tab.children.filter { extraIdentifiers.contains(ObjectIdentifier($0)) }
        }
        for placement in extraPlacements {
            let tab = placement.tab
            if placement.wasPinned {
                tab.parent = nil
                pinned.insert(tab, at: min(placement.index, pinned.count))
            } else if let parent = placement.parent {
                tab.parent = parent
                parent.children.insert(tab, at: min(placement.index, parent.children.count))
            } else if tab.isSaved {
                tab.parent = nil
                savedRoots.insert(tab, at: min(placement.index, savedRoots.count))
            } else {
                tab.parent = nil
                roots.insert(tab, at: min(placement.index, roots.count))
            }
        }
        for tab in savedRoots.flatMap(\.subtree) where tab.savedURL == nil {
            tab.savedURL = tab.url
            tab.savedTitle = tab.title
        }
        for tab in roots.flatMap(\.subtree) {
            tab.savedURL = nil
        }
        var splits = target.splits.compactMap { split -> TabSplit? in
            guard let leading = resolved[split.leading.id], let trailing = resolved[split.trailing.id],
                  !leading.isPinned, !trailing.isPinned
            else { return nil }
            return TabSplit(leading: leading, trailing: trailing, fraction: split.fraction)
        }
        splits += store.splits.filter { split in
            extraIdentifiers.contains(ObjectIdentifier(split.leading)) && extraIdentifiers.contains(ObjectIdentifier(split.trailing))
                && !split.leading.isPinned && !split.trailing.isPinned
        }
        store.restoreArrangement(
            pinned: pinned,
            savedRoots: savedRoots,
            roots: roots,
            splits: splits,
            selecting: target.selected.flatMap { resolved[$0.id] },
            removing: closing,
            reviving: revived
        )
    }
}
