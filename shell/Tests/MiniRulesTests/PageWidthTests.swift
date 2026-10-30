import Testing
import MiniRules

struct PageWidthTests {
    @Test func snapsToDetentsWithinAFewPoints() {
        #expect(PageWidth.dragged(to: 771, fullWidth: 1400) == 768)
        #expect(PageWidth.dragged(to: 762, fullWidth: 1400) == 768)
        #expect(PageWidth.dragged(to: 380.4, fullWidth: 1400) == 375)
        #expect(PageWidth.dragged(to: 1278, fullWidth: 1400) == 1280)
    }

    @Test func outsideTheSnapDistanceFollowsThePointer() {
        #expect(PageWidth.dragged(to: 775.4, fullWidth: 1400) == 775)
        #expect(PageWidth.dragged(to: 600, fullWidth: 1400) == 600)
    }

    @Test func detentsAtOrBeyondTheFullWidthDoNotSnap() {
        #expect(PageWidth.dragged(to: 1020, fullWidth: 1100) == 1024)
        #expect(PageWidth.dragged(to: 1275, fullWidth: 1279) == nil)
        #expect(PageWidth.dragged(to: 1250, fullWidth: 1280) == 1250)
    }

    @Test func clampsToTheMinimum() {
        #expect(PageWidth.dragged(to: 100, fullWidth: 1400) == 320)
        #expect(PageWidth.dragged(to: -40, fullWidth: 1400) == 320)
        #expect(PageWidth.dragged(to: 100, fullWidth: 300) == nil)
    }

    @Test func reachingTheFullWidthMeansFull() {
        #expect(PageWidth.dragged(to: 1500, fullWidth: 1400) == nil)
        #expect(PageWidth.dragged(to: 1396, fullWidth: 1400) == nil)
        #expect(PageWidth.dragged(to: 1390, fullWidth: 1400) == 1390)
    }

    @Test func displayedWidthFollowsTheAvailableSpace() {
        #expect(PageWidth.displayed(nil, fullWidth: 1000) == nil)
        #expect(PageWidth.displayed(768, fullWidth: 1000) == 768)
        #expect(PageWidth.displayed(1024, fullWidth: 1000) == nil)
        #expect(PageWidth.displayed(320, fullWidth: 300) == nil)
    }

    @Test func detentOnlyAtTheTableWidths() {
        #expect(PageWidth.detent(at: 768) == 768)
        #expect(PageWidth.detent(at: 769) == nil)
        #expect(PageWidth.detent(at: nil) == nil)
    }
}
