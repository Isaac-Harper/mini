import CMiniCore
import Foundation

struct ArchivedTab: Codable, Equatable {
    let url: String
    let title: String
    let archivedAt: Date
    let spaceIdentifier: String?
}

struct ArchiveChange {
    let added: [ArchivedTab]
    let displaced: [ArchivedTab]
}

enum ArchivePolicy {
    static let idleThreshold: TimeInterval = 12 * 60 * 60
    static let fadeStart: TimeInterval = 6 * 60 * 60
    static let fadedOpacity = 0.5

    static func idleOpacity(idleFor idle: TimeInterval) -> Double {
        guard idle > fadeStart else { return 1 }
        let fraction = min((idle - fadeStart) / (idleThreshold - fadeStart), 1)
        return 1 - fraction * (1 - fadedOpacity)
    }

    struct Candidate {
        let identifier: MiniTabId
        let lastSelectedAt: Date
        let isSelected: Bool
        let isSaved: Bool
        let children: [Candidate]
    }

    static func tabsToArchive(in roots: [Candidate], now: Date) -> [MiniTabId] {
        var archived: [MiniTabId] = []
        for root in roots {
            collect(root, now: now, into: &archived)
        }
        return archived
    }

    @discardableResult
    private static func collect(_ candidate: Candidate, now: Date, into archived: inout [MiniTabId]) -> Bool {
        var everyChildArchived = true
        for child in candidate.children where !collect(child, now: now, into: &archived) {
            everyChildArchived = false
        }
        guard everyChildArchived, !candidate.isSelected, !candidate.isSaved,
              now.timeIntervalSince(candidate.lastSelectedAt) >= idleThreshold
        else { return false }
        archived.append(candidate.identifier)
        return true
    }
}

@MainActor
final class ArchiveStore {
    private(set) var entries: [ArchivedTab]
    private let fileURL: URL

    private static let capacity = 200

    init(directory: URL) {
        fileURL = directory.appendingPathComponent("archive.json")
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            entries = []
            return
        }
        do {
            entries = try JSONDecoder().decode([ArchivedTab].self, from: Data(contentsOf: fileURL))
        } catch {
            NSLog("Mini: ignoring unreadable archive at %@: %@", fileURL.path, String(describing: error))
            entries = []
        }
    }

    @discardableResult
    func add(_ newEntries: [ArchivedTab]) -> ArchiveChange {
        guard !newEntries.isEmpty else { return ArchiveChange(added: [], displaced: []) }
        let kept = Self.newestPerURL(newEntries.reversed() + entries)
        let displaced = entries.filter { !kept.contains($0) }
        entries = kept
        save()
        return ArchiveChange(added: newEntries.filter(kept.contains), displaced: displaced)
    }

    func revert(_ change: ArchiveChange) {
        let restored = (entries.filter { !change.added.contains($0) } + change.displaced)
            .enumerated()
            .sorted { $0.element.archivedAt != $1.element.archivedAt ? $0.element.archivedAt > $1.element.archivedAt : $0.offset < $1.offset }
            .map(\.element)
        entries = Self.newestPerURL(restored)
        save()
    }

    private static func newestPerURL(_ candidates: [ArchivedTab]) -> [ArchivedTab] {
        var seenURLs = Set<String>()
        return Array(candidates.filter { seenURLs.insert($0.url).inserted }.prefix(capacity))
    }

    func remove(_ entry: ArchivedTab) {
        entries.removeAll { $0 == entry }
        save()
    }

    private func save() {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(entries).write(to: fileURL, options: .atomic)
        } catch {
            fatalError("Could not write archive to \(fileURL.path): \(error)")
        }
    }
}
