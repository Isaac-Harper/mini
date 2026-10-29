import Foundation
import MiniRules

struct SavedSpaceContents: Codable, Sendable {
    enum TabKind: String, Codable {
        case regular
        case saved
    }

    struct SavedTab: Codable {
        let url: String
        let title: String
        let isCollapsed: Bool
        let children: [SavedTab]
        let lastSelectedAt: Date?
        let kind: TabKind?
        let savedURL: String?
        let savedTitle: String?
        let foldedDay: Date?
        let foldedAt: Date?
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
    let player: SavedPinnedTab?
    let selectsPlayer: Bool?

    static let empty = SavedSpaceContents(tabs: [], selectedPath: nil, pinnedTabs: nil, selectedPinnedIndex: nil, splits: nil, player: nil, selectsPlayer: nil)
}

struct SavedSpace: Codable {
    let id: String
    let name: String
    let symbol: String
    let color: SpaceColor?
    let usesDefaultProfile: Bool
    let contents: SavedSpaceContents
}

struct SavedSession: Codable {
    let spaces: [SavedSpace]
    let currentSpace: String
    let closedDay: Date?

    static func initial(personalContents: SavedSpaceContents) -> SavedSession {
        let personal = SavedSpace(id: Space.newIdentifier(), name: "Personal", symbol: "person.fill", color: .amber, usesDefaultProfile: true, contents: personalContents)
        let work = SavedSpace(id: Space.newIdentifier(), name: "Work", symbol: "briefcase.fill", color: .blue, usesDefaultProfile: false, contents: .empty)
        return SavedSession(spaces: [personal, work], currentSpace: personal.id, closedDay: nil)
    }
}

@MainActor
final class SessionStore {
    private let fileURL: URL
    private var pendingSave: DispatchWorkItem?
    var closedDay: Date?

    init(directory: URL) {
        fileURL = directory.appendingPathComponent("session.json")
    }

    func load() -> SavedSession {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return .initial(personalContents: .empty) }
        let data: Data
        do {
            data = try Data(contentsOf: fileURL)
        } catch {
            fatalError("Could not read session at \(fileURL.path): \(error)")
        }
        if let session = try? JSONDecoder().decode(SavedSession.self, from: data), !session.spaces.isEmpty {
            closedDay = session.closedDay
            return session
        }
        do {
            return .initial(personalContents: try JSONDecoder().decode(SavedSpaceContents.self, from: data))
        } catch {
            NSLog("Mini: ignoring unreadable session at %@: %@", fileURL.path, String(describing: error))
            return .initial(personalContents: .empty)
        }
    }

    func scheduleSave(of spaces: @escaping () -> (spaces: [Space], current: Space)) {
        pendingSave?.cancel()
        let save = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                let snapshot = spaces()
                self.save(snapshot.spaces, current: snapshot.current)
            }
        }
        pendingSave = save
        DispatchQueue.main.asyncAfter(deadline: .now() + 1, execute: save)
    }

    func save(_ spaces: [Space], current: Space) {
        pendingSave?.cancel()
        pendingSave = nil
        let session = SavedSession(
            spaces: spaces.map { space in
                SavedSpace(id: space.id, name: space.name, symbol: space.symbol, color: space.color, usesDefaultProfile: space.usesDefaultProfile, contents: Self.contents(of: space.store))
            },
            currentSpace: current.id,
            closedDay: closedDay
        )
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(session).write(to: fileURL, options: .atomic)
        } catch {
            fatalError("Could not write session to \(fileURL.path): \(error)")
        }
    }

    private static func contents(of store: TabStore) -> SavedSpaceContents {
        let selected = store.selectedTab
        return SavedSpaceContents(
            tabs: store.treeRoots.map(savedTab),
            selectedPath: selected.flatMap { $0.isPinned ? nil : path(of: $0, in: store) },
            pinnedTabs: store.pinnedTabs.map { tab in
                guard let pinnedURL = tab.pinnedURL else { preconditionFailure("Pinned list holds an unpinned tab") }
                return SavedSpaceContents.SavedPinnedTab(pinnedURL: pinnedURL, url: tab.url, title: tab.title)
            },
            selectedPinnedIndex: selected.flatMap { selectedTab in store.pinnedTabs.firstIndex { $0 === selectedTab } },
            splits: store.splits.map { split in
                SavedSpaceContents.SavedSplit(
                    leadingPath: path(of: split.leading, in: store),
                    trailingPath: path(of: split.trailing, in: store),
                    fraction: split.fraction
                )
            },
            player: store.playerTab.map { SavedSpaceContents.SavedPinnedTab(pinnedURL: $0.pinnedURL ?? PlayerSlot.homeURL, url: $0.url, title: $0.title) },
            selectsPlayer: store.playerTab.map { $0 === selected }
        )
    }

    func restore(_ contents: SavedSpaceContents, into store: TabStore) {
        if let player = contents.player {
            store.newPlayerTab(url: player.url, title: player.title)
        }
        for savedPinnedTab in contents.pinnedTabs ?? [] {
            store.newPinnedTab(pinnedURL: savedPinnedTab.pinnedURL, url: savedPinnedTab.url, title: savedPinnedTab.title)
        }
        for savedTab in contents.tabs {
            restore(savedTab, parent: nil, into: store)
        }
        for savedSplit in contents.splits ?? [] {
            guard let leading = Self.tab(at: savedSplit.leadingPath, in: store),
                  let trailing = Self.tab(at: savedSplit.trailingPath, in: store),
                  leading !== trailing
            else { continue }
            store.makeSplit(leading: leading, trailing: trailing, fraction: savedSplit.fraction)
        }
        if contents.selectsPlayer == true, let playerTab = store.playerTab {
            store.select(playerTab)
            return
        }
        if let selectedPinnedIndex = contents.selectedPinnedIndex, store.pinnedTabs.indices.contains(selectedPinnedIndex) {
            store.select(store.pinnedTabs[selectedPinnedIndex])
            return
        }
        guard let selectedPath = contents.selectedPath, !selectedPath.isEmpty else {
            store.select(store.selectableTabs.first)
            return
        }
        store.select(Self.tab(at: selectedPath, in: store, stoppingAtMissingIndex: true) ?? store.treeRoots.first)
    }

    private static func tab(at path: [Int], in store: TabStore, stoppingAtMissingIndex: Bool = false) -> Tab? {
        var siblings = store.treeRoots
        var found: Tab?
        for index in path {
            guard siblings.indices.contains(index) else { return stoppingAtMissingIndex ? found : nil }
            found = siblings[index]
            siblings = siblings[index].children
        }
        return found
    }

    private func restore(_ savedTab: SavedSpaceContents.SavedTab, parent: Tab?, into store: TabStore) {
        let savedURL = savedTab.kind == .saved || parent?.isSaved == true ? savedTab.savedURL ?? savedTab.url : nil
        let tab = store.newTab(url: savedTab.url, title: savedTab.title, parent: parent, savedURL: savedURL, savedTitle: savedTab.savedTitle)
        for child in savedTab.children {
            restore(child, parent: tab, into: store)
        }
        tab.isCollapsed = savedTab.isCollapsed && !tab.children.isEmpty
        tab.lastSelectedAt = savedTab.lastSelectedAt ?? Date()
        if parent == nil, !tab.isSaved, let day = savedTab.foldedDay, let foldedAt = savedTab.foldedAt {
            tab.dayFold = DayFold(day: day, foldedAt: foldedAt)
        }
    }

    private static func savedTab(_ tab: Tab) -> SavedSpaceContents.SavedTab {
        SavedSpaceContents.SavedTab(
            url: tab.url,
            title: tab.title,
            isCollapsed: tab.isCollapsed,
            children: tab.children.map(savedTab),
            lastSelectedAt: tab.lastSelectedAt,
            kind: tab.isSaved ? .saved : .regular,
            savedURL: tab.savedURL,
            savedTitle: tab.isSaved ? tab.savedTitle : nil,
            foldedDay: tab.dayFold?.day,
            foldedAt: tab.dayFold?.foldedAt
        )
    }

    private static func path(of tab: Tab, in store: TabStore) -> [Int] {
        var path: [Int] = []
        var current = tab
        while true {
            let siblings = current.parent?.children ?? store.treeRoots
            guard let index = siblings.firstIndex(where: { $0 === current }) else {
                preconditionFailure("Selected tab is missing from the tree")
            }
            path.insert(index, at: 0)
            guard let parent = current.parent else { return path }
            current = parent
        }
    }
}
