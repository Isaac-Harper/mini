import Observation

enum CommandBarMode {
    case newTab
    case newChildTab
    case editCurrent
}

enum CommandSuggestion: Identifiable {
    case switchToTab(Tab)
    case open(URLInput.Interpretation)

    var id: String {
        switch self {
        case .switchToTab(let tab): "tab-\(tab.id)"
        case .open(let interpretation): "open-\(interpretation.url)"
        }
    }
}

@MainActor
@Observable
final class CommandBarModel {
    private(set) var suggestions: [CommandSuggestion] = []
    var selectedIndex = 0

    private static let maximumTabSuggestions = 5

    func update(query: String, tabs: [Tab], selectedTab: Tab?) {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            suggestions = []
            selectedIndex = 0
            return
        }
        let matchingTabs = tabs
            .filter { tab in
                tab !== selectedTab
                    && (tab.title.localizedCaseInsensitiveContains(trimmed) || tab.url.localizedCaseInsensitiveContains(trimmed))
            }
            .prefix(Self.maximumTabSuggestions)
            .map(CommandSuggestion.switchToTab)
        let openSuggestion = CommandSuggestion.open(URLInput.interpret(trimmed))
        suggestions = matchingTabs + [openSuggestion]
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
