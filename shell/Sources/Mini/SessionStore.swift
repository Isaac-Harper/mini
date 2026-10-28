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

    struct SavedSplit: Codable {
        let leadingPath: [Int]
        let trailingPath: [Int]
        let fraction: Double
    }

    let tabs: [SavedTab]
    let selectedPath: [Int]?
    let pinnedTabs: [SavedPinnedTab]?
    let selectedPinnedIndex: Int?
    let splits: [SavedSplit]?

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
            selectedPinnedIndex: selected.flatMap { selectedTab in store.pinnedTabs.firstIndex { $0 === selectedTab } },
            splits: store.splits.map { split in
                SavedSession.SavedSplit(
                    leadingPath: Self.path(of: split.leading, in: store),
                    trailingPath: Self.path(of: split.trailing, in: store),
                    fraction: split.fraction
                )
            }
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
        for savedSplit in session.splits ?? [] {
            guard let leading = Self.tab(at: savedSplit.leadingPath, in: store),
                  let trailing = Self.tab(at: savedSplit.trailingPath, in: store),
                  leading !== trailing
            else { continue }
            store.makeSplit(leading: leading, trailing: trailing, fraction: savedSplit.fraction)
        }
        if let selectedPinnedIndex = session.selectedPinnedIndex, store.pinnedTabs.indices.contains(selectedPinnedIndex) {
            store.select(store.pinnedTabs[selectedPinnedIndex])
            return
        }
        guard let selectedPath = session.selectedPath, !selectedPath.isEmpty else {
            store.select(store.selectableTabs.first)
            return
        }
        store.select(Self.tab(at: selectedPath, in: store, stoppingAtMissingIndex: true) ?? store.rootTabs.first)
    }

    private static func tab(at path: [Int], in store: TabStore, stoppingAtMissingIndex: Bool = false) -> Tab? {
        var siblings = store.rootTabs
        var found: Tab?
        for index in path {
            guard siblings.indices.contains(index) else { return stoppingAtMissingIndex ? found : nil }
            found = siblings[index]
            siblings = siblings[index].children
        }
        return found
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
