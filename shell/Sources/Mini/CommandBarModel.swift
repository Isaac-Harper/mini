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
    case searchSuggestion(String)
    case archived(ArchivedTab)
    case history(HistoryEntry)

    var id: String {
        switch self {
        case .switchToTab(let tab): "tab-\(tab.id)"
        case .open: "open"
        case .searchSuggestion(let text): "suggestion-\(text)"
        case .archived(let entry): "archived-\(entry.url)"
        case .history(let entry): "history-\(entry.url)"
        }
    }

    var isArchived: Bool {
        if case .archived = self { return true }
        return false
    }

    var isHistory: Bool {
        if case .history = self { return true }
        return false
    }
}

@MainActor
@Observable
final class CommandBarModel {
    private(set) var suggestions: [CommandSuggestion] = []
    var selectedIndex = 0

    @ObservationIgnored private var query = ""
    @ObservationIgnored private var tabs: [Tab] = []
    @ObservationIgnored private weak var selectedTab: Tab?
    @ObservationIgnored private var archived: [ArchivedTab] = []
    @ObservationIgnored private var history: [HistoryEntry] = []
    @ObservationIgnored private var searchSuggestions: [String] = []
    @ObservationIgnored private var searchSuggestionsQuery = ""

    private static let maximumSearchSuggestions = 4
    private static let maximumOtherRows = 5
    private static let maximumHistoryRows = 4
    private static let recentTabCount = 5

    var trimmedQuery: String { query.trimmingCharacters(in: .whitespacesAndNewlines) }

    func showRecentTabs(from tabs: [Tab], excluding selectedTab: Tab?) {
        query = ""
        searchSuggestions = []
        suggestions = tabs
            .filter { $0 !== selectedTab }
            .sorted { $0.lastSelectedAt > $1.lastSelectedAt }
            .prefix(Self.recentTabCount)
            .map(CommandSuggestion.switchToTab)
        selectedIndex = 0
    }

    func clear() {
        query = ""
        searchSuggestions = []
        suggestions = []
        selectedIndex = 0
    }

    func update(query: String, tabs: [Tab], selectedTab: Tab?, archived: [ArchivedTab], history: [HistoryEntry]) {
        self.query = query
        self.tabs = tabs
        self.selectedTab = selectedTab
        self.archived = archived
        self.history = history
        guard !trimmedQuery.isEmpty else {
            showRecentTabs(from: tabs, excluding: selectedTab)
            return
        }
        rebuild()
    }

    func setSearchSuggestions(_ texts: [String], for suggestionQuery: String) {
        guard suggestionQuery == trimmedQuery else { return }
        searchSuggestions = texts
        searchSuggestionsQuery = suggestionQuery
        rebuild()
    }

    private func rebuild() {
        let trimmed = trimmedQuery
        let previouslySelectedIdentifier = selectedSuggestion?.id
        let tokens = trimmed.lowercased().split(whereSeparator: \.isWhitespace)
        let matchingTabs = tabs
            .filter { tab in
                guard tab !== selectedTab else { return false }
                let haystack = "\(tab.title) \(URLInput.host(of: tab.url) ?? tab.url)".lowercased()
                return tokens.allSatisfy { haystack.contains($0) }
            }
            .prefix(Self.maximumOtherRows)
            .map(CommandSuggestion.switchToTab)
        let matchingArchived = archived
            .filter { entry in
                let haystack = "\(entry.title) \(URLInput.host(of: entry.url) ?? entry.url)".lowercased()
                return tokens.allSatisfy { haystack.contains($0) }
            }
            .prefix(Self.maximumOtherRows - matchingTabs.count)
            .map(CommandSuggestion.archived)
        let openURLs = Set(tabs.map(\.url))
        let matchingHistory = Frecency.ranked(history, now: Date())
            .filter { !openURLs.contains($0.url) }
            .prefix(Self.maximumHistoryRows)
            .map(CommandSuggestion.history)
        let lowercasedQuery = trimmed.lowercased()
        let searchRows = searchSuggestions
            .filter { $0.lowercased() != lowercasedQuery }
            .prefix(Self.maximumSearchSuggestions)
            .map(CommandSuggestion.searchSuggestion)
        suggestions = [.open(URLInput.interpret(trimmed))] + searchRows + matchingTabs + matchingHistory + matchingArchived
        if let previouslySelectedIdentifier, let index = suggestions.firstIndex(where: { $0.id == previouslySelectedIdentifier }) {
            selectedIndex = index
        } else {
            selectedIndex = 0
        }
    }

    func moveSelection(by offset: Int) {
        guard !suggestions.isEmpty else { return }
        selectedIndex = min(max(selectedIndex + offset, 0), suggestions.count - 1)
    }

    var selectedSuggestion: CommandSuggestion? {
        suggestions.indices.contains(selectedIndex) ? suggestions[selectedIndex] : nil
    }
}
