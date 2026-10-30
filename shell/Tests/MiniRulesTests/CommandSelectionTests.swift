import CoreGraphics
import Testing
import MiniRules

struct CommandSelectionTests {
    let identifiers = ["open", "tab", "header-free", "history"]
    let selectable = [true, true, false, true]

    @Test func theSelectedRowIsKeptWhenItStillExists() {
        #expect(CommandSelection.retainedIndex(previous: "history", in: identifiers, selectable: selectable, fallback: 0) == 3)
        #expect(CommandSelection.retainedIndex(previous: "gone", in: identifiers, selectable: selectable, fallback: 0) == 0)
        #expect(CommandSelection.retainedIndex(previous: "gone", in: identifiers, selectable: selectable, fallback: nil) == nil)
    }

    @Test func fallbackSkipsRowsThatCannotBeSelected() {
        #expect(CommandSelection.retainedIndex(previous: nil, in: ["notice", "a"], selectable: [false, true], fallback: 0) == 1)
        #expect(CommandSelection.retainedIndex(previous: nil, in: ["a", "notice"], selectable: [true, false], fallback: 1) == 0)
        #expect(CommandSelection.retainedIndex(previous: nil, in: ["notice"], selectable: [false], fallback: 0) == nil)
        #expect(CommandSelection.retainedIndex(previous: "notice", in: ["notice"], selectable: [false], fallback: 0) == nil)
    }

    @Test func arrowsStopAtTheEndsAndSkipUnselectableRows() {
        #expect(CommandSelection.moved(1, by: 1, selectable: selectable, allowsNone: false) == 3)
        #expect(CommandSelection.moved(3, by: 1, selectable: selectable, allowsNone: false) == 3)
        #expect(CommandSelection.moved(3, by: -1, selectable: selectable, allowsNone: false) == 1)
        #expect(CommandSelection.moved(0, by: -1, selectable: selectable, allowsNone: false) == 0)
    }

    @Test func listsWithoutAnInitialRowCanReturnToNone() {
        #expect(CommandSelection.moved(nil, by: 1, selectable: selectable, allowsNone: true) == 0)
        #expect(CommandSelection.moved(nil, by: -1, selectable: selectable, allowsNone: true) == nil)
        #expect(CommandSelection.moved(0, by: -1, selectable: selectable, allowsNone: true) == nil)
        #expect(CommandSelection.moved(nil, by: 1, selectable: [false], allowsNone: true) == nil)
    }

    @Test func thePointerTakesSelectionOnlyAfterItMoves() {
        let resting = CGPoint(x: 100, y: 200)
        #expect(CommandSelection.pointerTakesSelection(at: resting, anchor: resting) == false)
        #expect(CommandSelection.pointerTakesSelection(at: CGPoint(x: 101, y: 200), anchor: resting))
        #expect(CommandSelection.pointerTakesSelection(at: resting, anchor: nil))
    }

    @Test func escapeRevertsTypingBeforeClosing() {
        #expect(CommandEscape.action(text: "git", openingText: "") == .revert)
        #expect(CommandEscape.action(text: "", openingText: "") == .close)
        #expect(CommandEscape.action(text: "https://a.com/", openingText: "https://a.com/") == .close)
        #expect(CommandEscape.action(text: "news", openingText: "https://a.com/") == .revert)
    }
}

struct CommandOpenTargetTests {
    @Test func returnFollowsTheEntryPoint() {
        #expect(CommandOpenTarget.target(entry: .newTab, modifier: .none) == .newTab)
        #expect(CommandOpenTarget.target(entry: .newChildTab, modifier: .none) == .newChildTab)
        #expect(CommandOpenTarget.target(entry: .editCurrent, modifier: .none) == .currentTab)
    }

    @Test func commandReturnAlwaysOpensInTheBackground() {
        for entry in [CommandEntry.newTab, .newChildTab, .editCurrent] {
            #expect(CommandOpenTarget.target(entry: entry, modifier: .command) == .backgroundTab)
        }
        #expect(CommandReturnModifier(command: true, option: true) == .command)
    }

    @Test func optionReturnAlwaysOpensAChildOfTheCurrentTab() {
        for entry in [CommandEntry.newTab, .newChildTab, .editCurrent] {
            #expect(CommandOpenTarget.target(entry: entry, modifier: .option) == .newChildTab)
        }
    }
}
