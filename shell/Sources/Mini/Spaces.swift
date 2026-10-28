import AppKit
import CMiniCore
import Observation

@MainActor
final class TabIdentifierMint {
    private var nextIdentifier: MiniTabId = 1

    func mint() -> MiniTabId {
        defer { nextIdentifier += 1 }
        return nextIdentifier
    }
}

@MainActor
@Observable
final class Space: Identifiable {
    let id: String
    var name: String
    var symbol: String
    let usesDefaultProfile: Bool
    let store: TabStore

    static let symbols = [
        "person.fill", "briefcase.fill", "house.fill", "star.fill", "heart.fill", "leaf.fill",
        "book.fill", "graduationcap.fill", "gamecontroller.fill", "paintbrush.fill", "hammer.fill", "globe",
    ]

    init(id: String, name: String, symbol: String, usesDefaultProfile: Bool, identifiers: TabIdentifierMint) {
        self.id = id
        self.name = name
        self.symbol = symbol
        self.usesDefaultProfile = usesDefaultProfile
        store = TabStore(identifiers: identifiers)
    }

    nonisolated static func newIdentifier() -> String {
        UUID().uuidString.lowercased()
    }

    nonisolated static func cacheDirectory(forSpace identifier: String, rootCacheDirectory: URL) -> URL {
        rootCacheDirectory.appendingPathComponent("Spaces").appendingPathComponent(identifier)
    }
}
