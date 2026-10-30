import Testing
import MiniRules

struct InterfaceSizeTests {
    @Test func actualSizeIsOneHundredPercent() {
        #expect(InterfaceSize.scales[InterfaceSize.actualLevel] == 1)
        #expect(InterfaceSize.scales == InterfaceSize.scales.sorted())
    }

    @Test func missingOrOutOfRangeStoredLevelsClamp() {
        #expect(InterfaceSize.level(stored: nil) == InterfaceSize.actualLevel)
        #expect(InterfaceSize.level(stored: -3) == 0)
        #expect(InterfaceSize.level(stored: 99) == InterfaceSize.scales.count - 1)
        #expect(InterfaceSize.level(stored: 4) == 4)
    }

    @Test func steppingClampsAtBothEnds() {
        let last = InterfaceSize.scales.count - 1
        #expect(InterfaceSize.larger(than: 2) == 3)
        #expect(InterfaceSize.larger(than: last) == last)
        #expect(InterfaceSize.smaller(than: 2) == 1)
        #expect(InterfaceSize.smaller(than: 0) == 0)
    }

    @Test func scaledValuesRoundToHalfPoints() {
        #expect(InterfaceSize.scaled(28, by: 1) == 28)
        #expect(InterfaceSize.scaled(28, by: 1.25) == 35)
        #expect(InterfaceSize.scaled(13, by: 0.85) == 11)
        #expect(InterfaceSize.scaled(13, by: 1.08) == 14)
        #expect(InterfaceSize.scaled(8, by: 1.17) == 9.5)
    }

    @Test func sidebarWidthScalesProportionallyWithinTheNewLimits() {
        #expect(InterfaceSize.sidebarWidth(240, from: 1, to: 1.25, minimum: 250, maximum: 500) == 300)
        #expect(InterfaceSize.sidebarWidth(300, from: 1.25, to: 1, minimum: 200, maximum: 400) == 240)
        #expect(InterfaceSize.sidebarWidth(400, from: 1, to: 1.25, minimum: 250, maximum: 480) == 480)
        #expect(InterfaceSize.sidebarWidth(200, from: 1, to: 0.85, minimum: 170, maximum: 340) == 170)
    }
}
