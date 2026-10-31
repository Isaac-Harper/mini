import Testing
import MiniRules

struct ColorHexTests {
    @Test func channelsFormatAsUppercaseHex() {
        #expect(ColorHex.string(red: 0, green: 0, blue: 0) == "#000000")
        #expect(ColorHex.string(red: 1, green: 1, blue: 1) == "#FFFFFF")
        #expect(ColorHex.string(red: 1, green: 0.5, blue: 0) == "#FF8000")
    }

    @Test func outOfRangeChannelsClamp() {
        #expect(ColorHex.string(red: -0.2, green: 1.4, blue: 0.02) == "#00FF05")
    }

    @Test func oklchFromComponentsMatchesComputedColorPath() {
        #expect(TextStyle.oklch(red: 1, green: 0, blue: 0, alpha: 1) == "oklch(0.63 0.26 29)")
        #expect(TextStyle.oklch(red: 0, green: 0, blue: 0, alpha: 0.5) == "oklch(0 0 0 / 0.5)")
    }
}
