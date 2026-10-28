import Foundation

struct SavedSession: Codable {
    struct SavedTab: Codable {
        let url: String
        let title: String
        let isCollapsed: Bool
        let children: [SavedTab]
        let lastSelectedAt: Date?
    }

    struct SavedPinnedTab: Codable {
        let pinnedURL: String
        let url: String
        let title: String
    }

    let tabs: [SavedTab]
    let selectedPath: [Int]?
    let pinnedTabs: [SavedPinnedTab]?
    let selectedPinnedIndex: Int?

    var isEmpty: Bool { tabs.isEmpty && (pinnedTabs ?? []).isEmpty }
}

@MainActor
final class SessionStore {
    private let fileURL: URL
    private var pendingSave: DispatchWorkItem?

    init(directory: URL) {
        fileURL = directory.appendingPathComponent("session.json")
    }

    func load() -> SavedSession? {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }
        do {
            return try JSONDecoder().decode(SavedSession.self, from: Data(contentsOf: fileURL))
        } catch {
            NSLog("Mini: ignoring unreadable session at %@: %@", fileURL.path, String(describing: error))
            return nil
        }
    }

    func scheduleSave(of store: TabStore) {
        pendingSave?.cancel()
        let save = DispatchWorkItem { [weak self, weak store] in
            MainActor.assumeIsolated {
                guard let self, let store else { return }
                self.save(store)
            }
        }
        pendingSave = save
        DispatchQueue.main.asyncAfter(deadline: .now() + 1, execute: save)
    }

    func save(_ store: TabStore) {
        pendingSave?.cancel()
        pendingSave = nil
        let selected = store.selectedTab
        let session = SavedSession(
            tabs: store.rootTabs.map(Self.savedTab),
            selectedPath: selected.flatMap { $0.isPinned ? nil : Self.path(of: $0, in: store) },
            pinnedTabs: store.pinnedTabs.map { tab in
                guard let pinnedURL = tab.pinnedURL else { preconditionFailure("Pinned list holds an unpinned tab") }
                return SavedSession.SavedPinnedTab(pinnedURL: pinnedURL, url: tab.url, title: tab.title)
            },
            selectedPinnedIndex: selected.flatMap { selectedTab in store.pinnedTabs.firstIndex { $0 === selectedTab } }
        )
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(session).write(to: fileURL, options: .atomic)
        } catch {
            fatalError("Could not write session to \(fileURL.path): \(error)")
        }
    }

    func restore(_ session: SavedSession, into store: TabStore) {
        for savedPinnedTab in session.pinnedTabs ?? [] {
            store.newPinnedTab(pinnedURL: savedPinnedTab.pinnedURL, url: savedPinnedTab.url, title: savedPinnedTab.title)
        }
        for savedTab in session.tabs {
            restore(savedTab, parent: nil, into: store)
        }
        if let selectedPinnedIndex = session.selectedPinnedIndex, store.pinnedTabs.indices.contains(selectedPinnedIndex) {
            store.select(store.pinnedTabs[selectedPinnedIndex])
            return
        }
        guard let selectedPath = session.selectedPath, !selectedPath.isEmpty else {
            store.select(store.selectableTabs.first)
            return
        }
        var siblings = store.rootTabs
        var selected: Tab?
        for index in selectedPath {
            guard siblings.indices.contains(index) else { break }
            selected = siblings[index]
            siblings = siblings[index].children
        }
        store.select(selected ?? store.rootTabs.first)
    }

    private func restore(_ savedTab: SavedSession.SavedTab, parent: Tab?, into store: TabStore) {
        let tab = store.newTab(url: savedTab.url, title: savedTab.title, parent: parent)
        for child in savedTab.children {
            restore(child, parent: tab, into: store)
        }
        tab.isCollapsed = savedTab.isCollapsed && !tab.children.isEmpty
        tab.lastSelectedAt = savedTab.lastSelectedAt ?? Date()
    }

    private static func savedTab(_ tab: Tab) -> SavedSession.SavedTab {
        SavedSession.SavedTab(
            url: tab.url,
            title: tab.title,
            isCollapsed: tab.isCollapsed,
            children: tab.children.map(savedTab),
            lastSelectedAt: tab.lastSelectedAt
        )
    }

    private static func path(of tab: Tab, in store: TabStore) -> [Int] {
        var path: [Int] = []
        var current = tab
        while true {
            let siblings = current.parent?.children ?? store.rootTabs
            guard let index = siblings.firstIndex(where: { $0 === current }) else {
                preconditionFailure("Selected tab is missing from the tree")
            }
            path.insert(index, at: 0)
            guard let parent = current.parent else { return path }
            current = parent
        }
    }
}
