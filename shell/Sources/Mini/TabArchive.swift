import CMiniCore
import Foundation

struct ArchivedTab: Codable, Equatable {
    let url: String
    let title: String
    let archivedAt: Date
}

enum ArchivePolicy {
    static let idleThreshold: TimeInterval = 12 * 60 * 60

    struct Candidate {
        let identifier: MiniTabId
        let lastSelectedAt: Date
        let isSelected: Bool
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
        guard everyChildArchived, !candidate.isSelected,
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

    func add(_ newEntries: [ArchivedTab]) {
        guard !newEntries.isEmpty else { return }
        var seenURLs = Set<String>()
        entries = Array((newEntries.reversed() + entries).filter { seenURLs.insert($0.url).inserted }.prefix(Self.capacity))
        save()
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
