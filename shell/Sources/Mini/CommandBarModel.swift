import Foundation
import MiniRules
import Observation

typealias CommandBarMode = CommandEntry

enum CommandSuggestion: Identifiable {
    case switchToTab(Tab)
    case open(URLInput.Interpretation)
    case searchSuggestion(String)
    case archived(ArchivedTab)
    case history(HistoryEntry)
    case openLinks([PastedLink])
    case action(CommandAction)
    case localServer(LocalServer)
    case notice(String)

    var id: String {
        switch self {
        case .switchToTab(let tab): "tab-\(tab.id)"
        case .open: "open"
        case .searchSuggestion(let text): "suggestion-\(text)"
        case .archived(let entry): "archived-\(entry.url)"
        case .history(let entry): "history-\(entry.url)"
        case .openLinks: "open-links"
        case .action(let action): "action-\(action.id)"
        case .localServer(let server): "server-\(server.port)"
        case .notice(let text): "notice-\(text)"
        }
    }

    var isSelectable: Bool {
        if case .notice = self { return false }
        return true
    }

    var isEnabledAction: Bool {
        if case .action(let action) = self { return action.isEnabled }
        return false
    }
}

struct CommandRow: Identifiable {
    let suggestion: CommandSuggestion
    let header: String?

    var id: String { suggestion.id }
}

@MainActor
@Observable
final class CommandBarModel {
    private enum Content {
        case browse
        case typed
        case actions
        case links
    }

    private(set) var rows: [CommandRow] = []
    private(set) var selectedIndex: Int?
    private(set) var keyboardSelectionCount = 0
    private(set) var sessionCount = 0

    @ObservationIgnored private var content = Content.browse
    @ObservationIgnored private var query = ""
    @ObservationIgnored private var completion: String?
    @ObservationIgnored private var tabs: [Tab] = []
    @ObservationIgnored private weak var selectedTab: Tab?
    @ObservationIgnored private weak var playerTab: Tab?
    @ObservationIgnored private var archived: [ArchivedTab] = []
    @ObservationIgnored private var history: [HistoryEntry] = []
    @ObservationIgnored private var searchSuggestions: [String] = []
    @ObservationIgnored private var localServers: [LocalServer] = []
    @ObservationIgnored private var pointerAnchor: CGPoint?

    private static let maximumActionRows = 10
    static let actionHint = "Type > for actions"
    static let noMatchingActions = "No Matching Actions"

    var trimmedQuery: String { query.trimmingCharacters(in: .whitespacesAndNewlines) }

    var selectedSuggestion: CommandSuggestion? {
        guard let selectedIndex, rows.indices.contains(selectedIndex) else { return nil }
        return rows[selectedIndex].suggestion
    }

    private var allowsNoSelection: Bool { content == .browse }

    func showBrowse(tabs: [Tab], selectedTab: Tab?, playerTab: Tab?, frequent: [HistoryEntry], removedIndex: Int? = nil) {
        content = .browse
        query = ""
        completion = nil
        self.tabs = tabs
        self.selectedTab = selectedTab
        self.playerTab = playerTab
        history = frequent
        searchSuggestions = []
        rebuild(fallback: removedIndex, keepingSelection: false)
    }

    func update(query: String, completion: String?, tabs: [Tab], playerTab: Tab?, selectedTab: Tab?, archived: [ArchivedTab], history: [HistoryEntry],
                removedIndex: Int? = nil) {
        content = .typed
        self.query = query
        self.completion = completion
        self.tabs = tabs
        self.playerTab = playerTab
        self.selectedTab = selectedTab
        self.archived = archived
        self.history = history
        searchSuggestions = CommandResults.retainedSuggestions(searchSuggestions, query: trimmedQuery)
        rebuild(fallback: removedIndex ?? 0, keepingSelection: removedIndex == nil)
    }

    func setSearchSuggestions(_ texts: [String], for suggestionQuery: String) {
        guard content == .typed, suggestionQuery == trimmedQuery else { return }
        searchSuggestions = texts
        rebuild(fallback: 0, keepingSelection: true)
    }

    func setLocalServers(_ servers: [LocalServer]) {
        localServers = servers
        guard content == .browse || content == .typed else { return }
        rebuild(fallback: content == .typed ? 0 : nil, keepingSelection: true)
    }

    func showLinks(_ links: [PastedLink]) {
        content = .links
        query = ""
        completion = nil
        searchSuggestions = []
        rows = [CommandRow(suggestion: .openLinks(links), header: nil)]
        selectedIndex = 0
    }

    func showActions(_ actions: [CommandAction]) {
        let previous = selectedSuggestion?.id
        content = .actions
        query = ""
        completion = nil
        searchSuggestions = []
        let suggestions = actions.prefix(Self.maximumActionRows).map(CommandSuggestion.action)
        rows = suggestions.isEmpty ? [CommandRow(suggestion: .notice(Self.noMatchingActions), header: nil)] : suggestions.map { CommandRow(suggestion: $0, header: nil) }
        let firstEnabled = rows.firstIndex { $0.suggestion.isEnabledAction } ?? 0
        selectedIndex = CommandSelection.retainedIndex(previous: previous, in: rows.map(\.id), selectable: rows.map(\.suggestion.isSelectable), fallback: firstEnabled)
    }

    func moveSelection(by offset: Int) {
        selectedIndex = CommandSelection.moved(selectedIndex, by: offset, selectable: rows.map(\.suggestion.isSelectable), allowsNone: allowsNoSelection)
        keyboardSelectionCount += 1
    }

    func beginSession(pointerAt location: CGPoint) {
        pointerAnchor = location
        sessionCount += 1
    }

    var removableSelection: CommandSuggestion? {
        guard let selectedIndex, let suggestion = selectedSuggestion, content == .browse || content == .typed && selectedIndex > 0 else { return nil }
        switch suggestion {
        case .switchToTab, .history, .archived: return suggestion
        default: return nil
        }
    }

    func pointerMoved(to location: CGPoint, over index: Int) {
        guard CommandSelection.pointerTakesSelection(at: location, anchor: pointerAnchor) else { return }
        pointerAnchor = location
        guard rows.indices.contains(index), rows[index].suggestion.isSelectable, selectedIndex != index else { return }
        selectedIndex = index
    }

    private func rebuild(fallback: Int?, keepingSelection: Bool) {
        let previous = keepingSelection ? selectedSuggestion?.id : nil
        rows = content == .browse ? browseRows() : typedRows()
        selectedIndex = CommandSelection.retainedIndex(previous: previous, in: rows.map(\.id), selectable: rows.map(\.suggestion.isSelectable), fallback: fallback)
    }

    private var openTabKeys: Set<String> {
        Set(tabs.map { CommandResults.key(forAddress: $0.url) })
    }

    private func browseRows() -> [CommandRow] {
        let recentTabs = tabs
            .filter { $0 !== selectedTab }
            .sorted { $0.lastSelectedAt > $1.lastSelectedAt }
            .map { CommandCandidate(CommandSuggestion.switchToTab($0), section: .tabs, key: CommandResults.key(forAddress: $0.url)) }
        let frequent = Frecency.ranked(history, now: Date())
            .map { CommandCandidate(CommandSuggestion.history($0), section: .history, key: CommandResults.key(forAddress: $0.url)) }
        let servers = localServers
            .map { CommandCandidate(CommandSuggestion.localServer($0), section: .localServers, key: CommandResults.key(forAddress: $0.address)) }
        let assembled = CommandResults.assemble(primary: nil, candidates: recentTabs + frequent + servers, suggestions: [], limits: .empty, excluding: openTabKeys)
        return withHeaders(assembled, titles: [.history: "Frequently Visited", .localServers: "Local Servers"])
            + [CommandRow(suggestion: .notice(Self.actionHint), header: nil)]
    }

    private func typedRows() -> [CommandRow] {
        let trimmed = trimmedQuery
        let tokens = trimmed.lowercased().split(whereSeparator: \.isWhitespace)
        let interpretation = primaryInterpretation(for: trimmed)
        let primaryKey = switch interpretation {
        case .address(let address): CommandResults.key(forAddress: address)
        case .search(let text): CommandResults.key(forSearch: text)
        }
        let matchingTabs = tabs
            .filter { tab in
                guard tab !== selectedTab else { return false }
                let haystack = "\(tab === playerTab ? "Player " : "")\(tab.title) \(URLInput.host(of: tab.url) ?? tab.url)".lowercased()
                return tokens.allSatisfy { haystack.contains($0) } || CommandResults.key(forAddress: tab.url) == primaryKey
            }
            .sorted { $0.lastSelectedAt > $1.lastSelectedAt }
            .map { CommandCandidate(CommandSuggestion.switchToTab($0), section: .tabs, key: CommandResults.key(forAddress: $0.url)) }
        let matchingServers = localServers
            .filter { server in
                let haystack = "\(server.processName) \(server.port) localhost".lowercased()
                return tokens.allSatisfy { haystack.contains($0.trimmingCharacters(in: CharacterSet(charactersIn: ":"))) }
            }
            .map { CommandCandidate(CommandSuggestion.localServer($0), section: .localServers, key: CommandResults.key(forAddress: $0.address)) }
        let matchingHistory = Frecency.ranked(history, now: Date())
            .map { CommandCandidate(CommandSuggestion.history($0), section: .history, key: CommandResults.key(forAddress: $0.url)) }
        let matchingArchived = archived
            .filter { entry in
                let haystack = "\(entry.title) \(URLInput.host(of: entry.url) ?? entry.url)".lowercased()
                return tokens.allSatisfy { haystack.contains($0) }
            }
            .map { CommandCandidate(CommandSuggestion.archived($0), section: .archived, key: CommandResults.key(forAddress: $0.url)) }
        let suggestionRows = searchSuggestions
            .map { CommandCandidate(CommandSuggestion.searchSuggestion($0), section: .suggestions, key: CommandResults.key(forSearch: $0)) }
        let assembled = CommandResults.assemble(primary: CommandCandidate(CommandSuggestion.open(interpretation), section: .primary, key: primaryKey),
                                                candidates: matchingTabs + matchingServers + matchingHistory + matchingArchived,
                                                suggestions: suggestionRows, limits: .typed, excluding: openTabKeys)
        return withHeaders(assembled, titles: [.localServers: "Local Servers", .history: "History", .archived: "Archived", .suggestions: "Search Suggestions"])
    }

    private func primaryInterpretation(for trimmed: String) -> URLInput.Interpretation {
        if let completion {
            return URLInput.interpret(completion)
        }
        if let port = LocalDevelopment.portShortcut(trimmed, listeningPorts: Set(localServers.map(\.port))) {
            return .address("http://localhost:\(port)")
        }
        return URLInput.interpret(trimmed)
    }

    private func withHeaders(_ candidates: [CommandCandidate<CommandSuggestion>], titles: [CommandSection: String]) -> [CommandRow] {
        candidates.indices.map { index in
            let section = candidates[index].section
            let startsSection = index == 0 || candidates[index - 1].section != section
            return CommandRow(suggestion: candidates[index].item, header: startsSection ? titles[section] : nil)
        }
    }
}
