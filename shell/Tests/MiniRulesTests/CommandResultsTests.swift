import Testing
import MiniRules

struct CommandResultsTests {
    typealias Candidate = CommandCandidate<String>

    @Test func addressKeysIgnoreSchemeWwwTrailingSlashAndFragment() {
        let key = CommandResults.key(forAddress: "https://www.Example.com/")
        #expect(key == CommandResults.key(forAddress: "http://example.com"))
        #expect(key == CommandResults.key(forAddress: "https://example.com/#top"))
        #expect(key != CommandResults.key(forAddress: "https://example.com/a"))
        #expect(CommandResults.key(forAddress: "http://localhost:3000/") != CommandResults.key(forAddress: "http://localhost:3001/"))
    }

    @Test func primaryRowComesFirstThenSectionsInOrder() {
        let rows = CommandResults.assemble(
            primary: Candidate("open", section: .primary, key: "search:git"),
            candidates: [
                Candidate("archived", section: .archived, key: "a"),
                Candidate("history", section: .history, key: "h"),
                Candidate("server", section: .localServers, key: "s"),
                Candidate("tab", section: .tabs, key: "t"),
            ],
            suggestions: [Candidate("suggestion", section: .suggestions, key: "search:github")],
            limits: .typed
        )
        #expect(rows.map(\.item) == ["open", "tab", "server", "history", "archived", "suggestion"])
    }

    @Test func theSameAddressIsNeverShownTwice() {
        let rows = CommandResults.assemble(
            primary: Candidate("open", section: .primary, key: "search:x"),
            candidates: [
                Candidate("tab", section: .tabs, key: "web://a.com"),
                Candidate("history a", section: .history, key: "web://a.com"),
                Candidate("history b", section: .history, key: "web://b.com"),
                Candidate("archived b", section: .archived, key: "web://b.com"),
            ],
            suggestions: [Candidate("typed again", section: .suggestions, key: "search:x")],
            limits: .typed
        )
        #expect(rows.map(\.item) == ["open", "tab", "history b"])
    }

    @Test func openTabAddressesHideTheirHistoryArchiveAndServerRows() {
        let rows = CommandResults.assemble(
            primary: nil,
            candidates: [Candidate("tab", section: .tabs, key: "web://shown.com"), Candidate("current page", section: .history, key: "web://current.com"),
                         Candidate("tab past the cap", section: .history, key: "web://hidden.com"), Candidate("server", section: .localServers, key: "web://localhost:3000"),
                         Candidate("other", section: .history, key: "web://other.com")],
            suggestions: [],
            limits: .empty,
            excluding: ["web://current.com", "web://hidden.com", "web://shown.com", "web://localhost:3000"]
        )
        #expect(rows.map(\.item) == ["tab", "other"])
    }

    @Test func anOpenTabMatchingTheTypedAddressReplacesTheOpenRow() {
        let rows = CommandResults.assemble(
            primary: Candidate("open", section: .primary, key: "web://github.com"),
            candidates: [Candidate("other", section: .tabs, key: "web://x.com"), Candidate("github tab", section: .tabs, key: "web://github.com"),
                         Candidate("github history", section: .history, key: "web://github.com")],
            suggestions: [],
            limits: .typed
        )
        #expect(rows.map(\.item) == ["github tab", "other"])
    }

    @Test func sectionAndLocalLimitsCapTheList() {
        let tabs = (0..<10).map { Candidate("tab\($0)", section: .tabs, key: "t\($0)") }
        let history = (0..<10).map { Candidate("history\($0)", section: .history, key: "h\($0)") }
        let suggestions = (0..<10).map { Candidate("suggestion\($0)", section: .suggestions, key: "s\($0)") }
        let rows = CommandResults.assemble(primary: Candidate("open", section: .primary, key: nil), candidates: tabs + history, suggestions: suggestions, limits: .typed)
        #expect(rows.filter { $0.section == .tabs }.count == 4)
        #expect(rows.filter { $0.section == .history }.count == 2)
        #expect(rows.filter { $0.section == .suggestions }.count == 3)
        #expect(rows.count == 10)
    }

    @Test func emptyStateListsTabsThenFrequentHistoryThenServers() {
        let rows = CommandResults.assemble(primary: nil, candidates: [Candidate("server", section: .localServers, key: "s"), Candidate("frequent", section: .history, key: "h"),
                                                                      Candidate("tab", section: .tabs, key: "t"), Candidate("archived", section: .archived, key: "a")],
                                           suggestions: [Candidate("suggestion", section: .suggestions, key: "x")], limits: .empty)
        #expect(rows.map(\.item) == ["tab", "frequent", "server"])
    }

    @Test func emptyStateHasNoPrimaryRow() {
        let rows = CommandResults.assemble(primary: nil, candidates: [Candidate("tab", section: .tabs, key: "a"), Candidate("frequent", section: .history, key: "a"),
                                                                      Candidate("frequent b", section: .history, key: "b")],
                                           suggestions: [], limits: .empty)
        #expect(rows.map(\.item) == ["tab", "frequent b"])
    }

    @Test func staleSuggestionsStayOnlyWhileTheyStillMatch() {
        let previous = ["github", "github copilot", "gitlab"]
        #expect(CommandResults.retainedSuggestions(previous, query: "gith") == ["github", "github copilot"])
        #expect(CommandResults.retainedSuggestions(previous, query: "GitHub") == ["github copilot"])
        #expect(CommandResults.retainedSuggestions(previous, query: "rust").isEmpty)
        #expect(CommandResults.retainedSuggestions(previous, query: " ").isEmpty)
    }
}
