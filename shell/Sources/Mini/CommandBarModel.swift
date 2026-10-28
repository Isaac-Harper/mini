import Foundation
import Observation

enum CommandBarMode {
    case newTab
    case newChildTab
    case editCurrent
}

enum CommandSuggestion: Identifiable {
    case switchToTab(Tab)
    case open(URLInput.Interpretation)
    case archived(ArchivedTab)

    var id: String {
        switch self {
        case .switchToTab(let tab): "tab-\(tab.id)"
        case .open(let interpretation): "open-\(interpretation.url)"
        case .archived(let entry): "archived-\(entry.url)-\(entry.archivedAt.timeIntervalSince1970)"
        }
    }

    var isArchived: Bool {
        if case .archived = self { return true }
        return false
    }
}

@MainActor
@Observable
final class CommandBarModel {
    private(set) var suggestions: [CommandSuggestion] = []
    var selectedIndex = 0

    private static let maximumRows = 7
    private static let recentTabCount = 5

    func showRecentTabs(from tabs: [Tab], excluding selectedTab: Tab?) {
        suggestions = tabs
            .filter { $0 !== selectedTab }
            .sorted { $0.lastSelectedAt > $1.lastSelectedAt }
            .prefix(Self.recentTabCount)
            .map(CommandSuggestion.switchToTab)
        selectedIndex = 0
    }

    func clear() {
        suggestions = []
        selectedIndex = 0
    }

    func update(query: String, tabs: [Tab], selectedTab: Tab?, archived: [ArchivedTab]) {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            showRecentTabs(from: tabs, excluding: selectedTab)
            return
        }
        let tokens = trimmed.lowercased().split(whereSeparator: \.isWhitespace)
        let matchingTabs = tabs
            .filter { tab in
                guard tab !== selectedTab else { return false }
                let haystack = "\(tab.title) \(URLInput.host(of: tab.url) ?? tab.url)".lowercased()
                return tokens.allSatisfy { haystack.contains($0) }
            }
            .prefix(Self.maximumRows - 1)
            .map(CommandSuggestion.switchToTab)
        let matchingArchived = archived
            .filter { entry in
                let haystack = "\(entry.title) \(URLInput.host(of: entry.url) ?? entry.url)".lowercased()
                return tokens.allSatisfy { haystack.contains($0) }
            }
            .prefix(Self.maximumRows - 1 - matchingTabs.count)
            .map(CommandSuggestion.archived)
        suggestions = [.open(URLInput.interpret(trimmed))] + matchingTabs + matchingArchived
        selectedIndex = 0
    }

    func moveSelection(by offset: Int) {
        guard !suggestions.isEmpty else { return }
        selectedIndex = min(max(selectedIndex + offset, 0), suggestions.count - 1)
    }

    var selectedSuggestion: CommandSuggestion? {
        suggestions.indices.contains(selectedIndex) ? suggestions[selectedIndex] : nil
    }
}
