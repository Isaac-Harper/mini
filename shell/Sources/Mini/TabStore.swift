import CMiniCore
import Observation

@MainActor
protocol TabStoreObserver: AnyObject {
    func tabStore(_ store: TabStore, didSelect tab: Tab?, previous: Tab?)
    func tabStore(_ store: TabStore, didRemove tabs: [Tab])
    func tabStoreDidChangeStructure(_ store: TabStore)
}

struct VisibleTab: Identifiable {
    let tab: Tab
    let depth: Int
    var id: MiniTabId { tab.id }
}

@MainActor
@Observable
final class TabStore {
    private(set) var pinnedTabs: [Tab] = []
    private(set) var rootTabs: [Tab] = []
    private(set) var selectedTab: Tab?

    @ObservationIgnored weak var observer: TabStoreObserver?
    @ObservationIgnored private var nextIdentifier: MiniTabId = 1
    @ObservationIgnored private var tabsByIdentifier: [MiniTabId: Tab] = [:]
    @ObservationIgnored private var closedTabs: [ClosedTab] = []

    private struct ClosedTab {
        let url: String
        let parentIdentifier: MiniTabId?
    }

    var visibleTabs: [VisibleTab] {
        rootTabs.flatMap { visibleSubtree(of: $0, depth: 0) }
    }

    var selectableTabs: [Tab] {
        pinnedTabs + visibleTabs.map(\.tab)
    }

    var allTabs: [Tab] {
        pinnedTabs + rootTabs.flatMap(\.subtree)
    }

    var canReopenClosedTab: Bool { !closedTabs.isEmpty }

    func tab(withIdentifier identifier: MiniTabId) -> Tab? {
        tabsByIdentifier[identifier]
    }

    func rootAncestor(of tab: Tab) -> Tab {
        var current = tab
        while let parent = current.parent { current = parent }
        return current
    }

    @discardableResult
    func newTab(url: String, title: String = "", parent: Tab?, after sibling: Tab? = nil) -> Tab {
        let tab = makeTab(url: url, title: title)
        if parent?.isPinned == true || sibling?.isPinned == true {
            insert(tab, into: nil, at: 0)
            observer?.tabStoreDidChangeStructure(self)
            return tab
        }
        let siblings = children(of: parent)
        let index = sibling.map { position(of: $0, in: siblings) + 1 } ?? siblings.count
        insert(tab, into: parent, at: index)
        if let parent { parent.isCollapsed = false }
        observer?.tabStoreDidChangeStructure(self)
        return tab
    }

    @discardableResult
    func newPinnedTab(pinnedURL: String, url: String, title: String) -> Tab {
        let tab = makeTab(url: url, title: title)
        tab.pinnedURL = pinnedURL
        pinnedTabs.append(tab)
        observer?.tabStoreDidChangeStructure(self)
        return tab
    }

    func pin(_ tab: Tab) {
        guard !tab.isPinned, !tab.url.isEmpty else { return }
        let parent = tab.parent
        let index = position(of: tab, in: children(of: parent))
        detach(tab)
        for (offset, child) in tab.children.enumerated() {
            insert(child, into: parent, at: index + offset)
        }
        tab.children = []
        tab.isCollapsed = false
        tab.pinnedURL = tab.url
        pinnedTabs.append(tab)
        observer?.tabStoreDidChangeStructure(self)
    }

    func unpin(_ tab: Tab) {
        guard tab.isPinned else { return }
        pinnedTabs.remove(at: position(of: tab, in: pinnedTabs))
        tab.pinnedURL = nil
        insert(tab, into: nil, at: 0)
        observer?.tabStoreDidChangeStructure(self)
    }

    func select(_ tab: Tab?) {
        guard tab !== selectedTab else { return }
        if let tab {
            precondition(tabsByIdentifier[tab.id] === tab, "Selecting a tab that is not in the store")
            var ancestor = tab.parent
            while let current = ancestor {
                current.isCollapsed = false
                ancestor = current.parent
            }
        }
        let previous = selectedTab
        selectedTab = tab
        observer?.tabStore(self, didSelect: tab, previous: previous)
        observer?.tabStoreDidChangeStructure(self)
    }

    func close(_ tab: Tab) {
        if tab.isPinned {
            unload(pinned: tab)
            return
        }
        let siblings = children(of: tab.parent)
        let index = position(of: tab, in: siblings)
        var replacement: Tab?
        let closesSelection = selectedTab.map { $0 === tab || $0.isDescendant(of: tab) } ?? false
        if closesSelection {
            if index + 1 < siblings.count {
                replacement = siblings[index + 1]
            } else if index > 0 {
                replacement = siblings[index - 1]
            } else {
                replacement = tab.parent
            }
            selectedTab = nil
        }
        if !tab.url.isEmpty {
            closedTabs.append(ClosedTab(url: tab.url, parentIdentifier: tab.parent?.id))
        }
        detach(tab)
        let removedTabs = tab.subtree
        for removedTab in removedTabs {
            tabsByIdentifier[removedTab.id] = nil
        }
        observer?.tabStore(self, didRemove: removedTabs)
        if closesSelection {
            select(replacement)
        }
        observer?.tabStoreDidChangeStructure(self)
    }

    private func unload(pinned tab: Tab) {
        guard let pinnedURL = tab.pinnedURL else { preconditionFailure("Unloading a tab that is not pinned") }
        let index = position(of: tab, in: pinnedTabs)
        let freshTab = makeTab(url: pinnedURL, title: tab.title)
        freshTab.pinnedURL = pinnedURL
        freshTab.favicon = tab.favicon
        pinnedTabs[index] = freshTab
        tabsByIdentifier[tab.id] = nil
        let closesSelection = selectedTab === tab
        if closesSelection {
            selectedTab = nil
        }
        observer?.tabStore(self, didRemove: [tab])
        if closesSelection {
            if index + 1 < pinnedTabs.count {
                select(pinnedTabs[index + 1])
            } else if index > 0 {
                select(pinnedTabs[index - 1])
            } else {
                select(rootTabs.first)
            }
        }
        observer?.tabStoreDidChangeStructure(self)
    }

    func indent(_ tab: Tab) {
        guard canIndent(tab), let newParent = previousSibling(of: tab) else { return }
        detach(tab)
        insert(tab, into: newParent, at: newParent.children.count)
        newParent.isCollapsed = false
        observer?.tabStoreDidChangeStructure(self)
    }

    func outdent(_ tab: Tab) {
        guard let parent = tab.parent else { return }
        detach(tab)
        let index = position(of: parent, in: children(of: parent.parent)) + 1
        insert(tab, into: parent.parent, at: index)
        observer?.tabStoreDidChangeStructure(self)
    }

    func canIndent(_ tab: Tab) -> Bool {
        !tab.isPinned && previousSibling(of: tab) != nil
    }

    func toggleCollapse(_ tab: Tab) {
        guard !tab.children.isEmpty else { return }
        tab.isCollapsed.toggle()
        if tab.isCollapsed, let selectedTab, selectedTab.isDescendant(of: tab) {
            select(tab)
        }
        observer?.tabStoreDidChangeStructure(self)
    }

    func selectNext() {
        selectVisible(offset: 1)
    }

    func selectPrevious() {
        selectVisible(offset: -1)
    }

    func select(index: Int) {
        let selectable = selectableTabs
        guard !selectable.isEmpty else { return }
        if index == 9 {
            select(selectable[selectable.count - 1])
        } else if index - 1 < selectable.count {
            select(selectable[index - 1])
        }
    }

    func reopenClosedTab() {
        guard let closedTab = closedTabs.popLast() else { return }
        let parent = closedTab.parentIdentifier.flatMap { tabsByIdentifier[$0] }
        select(newTab(url: closedTab.url, parent: parent))
    }

    private func selectVisible(offset: Int) {
        let selectable = selectableTabs
        guard !selectable.isEmpty else { return }
        guard let selectedTab, let index = selectable.firstIndex(where: { $0 === selectedTab }) else {
            select(selectable[0])
            return
        }
        let count = selectable.count
        select(selectable[((index + offset) % count + count) % count])
    }

    private func makeTab(url: String, title: String) -> Tab {
        let tab = Tab(id: nextIdentifier, url: url, title: title)
        nextIdentifier += 1
        tabsByIdentifier[tab.id] = tab
        return tab
    }

    private func visibleSubtree(of tab: Tab, depth: Int) -> [VisibleTab] {
        let row = VisibleTab(tab: tab, depth: depth)
        guard !tab.isCollapsed else { return [row] }
        return [row] + tab.children.flatMap { visibleSubtree(of: $0, depth: depth + 1) }
    }

    private func children(of parent: Tab?) -> [Tab] {
        parent?.children ?? rootTabs
    }

    private func position(of tab: Tab, in siblings: [Tab]) -> Int {
        guard let index = siblings.firstIndex(where: { $0 === tab }) else {
            preconditionFailure("Tab \(tab.id) is missing from its parent's children")
        }
        return index
    }

    private func previousSibling(of tab: Tab) -> Tab? {
        guard !tab.isPinned else { return nil }
        let siblings = children(of: tab.parent)
        let index = position(of: tab, in: siblings)
        return index > 0 ? siblings[index - 1] : nil
    }

    private func detach(_ tab: Tab) {
        let index = position(of: tab, in: children(of: tab.parent))
        if let parent = tab.parent {
            parent.children.remove(at: index)
        } else {
            rootTabs.remove(at: index)
        }
        tab.parent = nil
    }

    private func insert(_ tab: Tab, into parent: Tab?, at index: Int) {
        tab.parent = parent
        if let parent {
            parent.children.insert(tab, at: index)
        } else {
            rootTabs.insert(tab, at: index)
        }
    }
}
