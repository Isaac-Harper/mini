import Testing
import MiniRules

struct RowSelectionTests {
    let order = ["a", "b", "c", "d", "e"]

    @Test func shiftClickSelectsTheRangeFromTheActiveRow() {
        var selection = RowSelection<String>()
        selection.extend(to: "d", active: "b", in: order)
        #expect(selection.identifiers == ["b", "c", "d"])
        #expect(selection.isMultiple)
    }

    @Test func shiftClickUpwardKeepsVisibleOrder() {
        var selection = RowSelection<String>()
        selection.extend(to: "a", active: "c", in: order)
        #expect(selection.identifiers == ["a", "b", "c"])
    }

    @Test func secondShiftClickPivotsAroundTheSameAnchor() {
        var selection = RowSelection<String>()
        selection.extend(to: "e", active: "c", in: order)
        selection.extend(to: "a", active: "c", in: order)
        #expect(selection.identifiers == ["a", "b", "c"])
    }

    @Test func commandClickTogglesSingleRowsAndStartsFromTheActiveRow() {
        var selection = RowSelection<String>()
        selection.toggle("d", active: "a", in: order)
        #expect(selection.identifiers == ["a", "d"])
        selection.toggle("b", active: "a", in: order)
        #expect(selection.identifiers == ["a", "b", "d"])
        selection.toggle("a", active: "a", in: order)
        #expect(selection.identifiers == ["b", "d"])
    }

    @Test func togglingDownToOneRowClears() {
        var selection = RowSelection<String>()
        selection.toggle("d", active: "a", in: order)
        selection.toggle("d", active: "a", in: order)
        #expect(selection.identifiers.isEmpty)
        #expect(!selection.isMultiple)
        #expect(selection.anchor == nil)
    }

    @Test func shiftClickOnTheActiveRowSelectsNothing() {
        var selection = RowSelection<String>()
        selection.extend(to: "b", active: "b", in: order)
        #expect(selection.identifiers.isEmpty)
    }

    @Test func shiftArrowsExtendAndShrinkFromTheFocusedRow() {
        var selection = RowSelection<String>()
        #expect(selection.extend(by: 1, from: "b", in: order) == "c")
        #expect(selection.identifiers == ["b", "c"])
        #expect(selection.extend(by: 1, from: "b", in: order) == "d")
        #expect(selection.identifiers == ["b", "c", "d"])
        #expect(selection.extend(by: -1, from: "b", in: order) == "c")
        #expect(selection.identifiers == ["b", "c"])
        #expect(selection.extend(by: -1, from: "b", in: order) == "b")
        #expect(selection.identifiers.isEmpty)
        #expect(selection.extend(by: -1, from: "b", in: order) == "a")
        #expect(selection.identifiers == ["a", "b"])
    }

    @Test func shiftArrowsStopAtTheEnds() {
        var selection = RowSelection<String>()
        #expect(selection.extend(by: 1, from: "d", in: order) == "e")
        #expect(selection.extend(by: 1, from: "d", in: order) == "e")
        #expect(selection.identifiers == ["d", "e"])
    }

    @Test func removedRowsDropOut() {
        var selection = RowSelection<String>()
        selection.extend(to: "d", active: "a", in: order)
        selection.retain(["a", "c", "e"])
        #expect(selection.identifiers == ["a", "c"])
        selection.retain(["a", "e"])
        #expect(selection.identifiers.isEmpty)
    }

    @Test func clearForgetsTheAnchor() {
        var selection = RowSelection<String>()
        selection.extend(to: "d", active: "a", in: order)
        selection.clear()
        selection.extend(to: "e", active: "c", in: order)
        #expect(selection.identifiers == ["c", "d", "e"])
    }
}
