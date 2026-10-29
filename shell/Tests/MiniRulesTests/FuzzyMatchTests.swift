import Testing
import MiniRules

struct FuzzyMatchTests {
    @Test func subsequencesMatchAndOthersDoNot() {
        #expect(FuzzyMatch.score("spv", in: "Split View") != nil)
        #expect(FuzzyMatch.score("dup", in: "Duplicate Tab") != nil)
        #expect(FuzzyMatch.score("xyz", in: "Duplicate Tab") == nil)
        #expect(FuzzyMatch.score("tabz", in: "Tab") == nil)
    }

    @Test func emptyQueryMatchesEverything() {
        #expect(FuzzyMatch.score("", in: "Anything") == 0)
        #expect(FuzzyMatch.score("  ", in: "Anything") == 0)
    }

    @Test func wordStartsAndRunsBeatScatteredLetters() {
        let wordStarts = FuzzyMatch.score("nt", in: "New Tab")!
        let scattered = FuzzyMatch.score("nt", in: "Print\u{2026}")!
        #expect(wordStarts > scattered)
        let run = FuzzyMatch.score("pin", in: "Pin Tab")!
        let spread = FuzzyMatch.score("pin", in: "Picture in Picture")!
        #expect(run > spread)
    }

    @Test func caseIsIgnored() {
        #expect(FuzzyMatch.score("SAFARI", in: "Open in Safari") != nil)
    }

    @Test func rankPutsRecentMatchesFirstInRecencyOrder() {
        let titles = ["New Tab", "Pin Tab", "Save Tab", "Split View"]
        let ranked = FuzzyMatch.rank(titles, query: "", title: { $0 }, identifier: { $0 }, recent: ["Split View", "Save Tab"])
        #expect(ranked == ["Split View", "Save Tab", "New Tab", "Pin Tab"])
    }

    @Test func rankFiltersAndOrdersByScore() {
        let titles = ["Print\u{2026}", "New Tab", "Next Tab"]
        let ranked = FuzzyMatch.rank(titles, query: "nt", title: { $0 }, identifier: { $0 }, recent: [])
        #expect(ranked.prefix(2).sorted() == ["New Tab", "Next Tab"])
        #expect(ranked.last == "Print\u{2026}")
        #expect(FuzzyMatch.rank(titles, query: "zzz", title: { $0 }, identifier: { $0 }, recent: ["New Tab"]).isEmpty)
    }

    @Test func rememberingMovesToTheFrontAndCaps() {
        #expect(FuzzyMatch.remembering("b", in: ["a", "b", "c"], limit: 3) == ["b", "a", "c"])
        #expect(FuzzyMatch.remembering("d", in: ["a", "b", "c"], limit: 3) == ["d", "a", "b"])
    }

    @Test func keyEquivalentsUseMenuSymbolsInMenuOrder() {
        #expect(KeyEquivalentText.describe(key: "c", control: false, option: true, shift: false, command: true) == "\u{2325}\u{2318}C")
        #expect(KeyEquivalentText.describe(key: "T", control: false, option: false, shift: false, command: true) == "\u{21E7}\u{2318}T")
        #expect(KeyEquivalentText.describe(key: "\t", control: true, option: false, shift: true, command: false) == "\u{2303}\u{21E7}\u{21E5}")
        #expect(KeyEquivalentText.describe(key: "\u{F701}", control: false, option: true, shift: false, command: true) == "\u{2325}\u{2318}\u{2193}")
        #expect(KeyEquivalentText.describe(key: "", control: false, option: false, shift: false, command: true) == "")
    }
}
