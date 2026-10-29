import Testing
import MiniRules

struct FaviconToneTests {
    func icon(_ pixel: [UInt8], count: Int, transparent: Int) -> [UInt8] {
        Array([[UInt8]](repeating: pixel, count: count).joined()) + [UInt8](repeating: 0, count: transparent * 4)
    }

    @Test func darkGlyphOnTransparencyNeedsAPlateOnDarkGlassOnly() {
        let tone = FaviconTone.measure(premultipliedRGBA: icon([20, 20, 23, 255], count: 300, transparent: 276))
        #expect(tone.luminance < 0.01)
        #expect(abs(tone.coverage - 300.0 / 576) < 0.001)
        #expect(tone.needsBackingPlate(on: .dark))
        #expect(!tone.needsBackingPlate(on: .light))
    }

    @Test func whiteGlyphNeedsAPlateOnLightGlassOnly() {
        let tone = FaviconTone.measure(premultipliedRGBA: icon([255, 255, 255, 255], count: 200, transparent: 376))
        #expect(tone.luminance > 0.99)
        #expect(tone.needsBackingPlate(on: .light))
        #expect(!tone.needsBackingPlate(on: .dark))
    }

    @Test func colorfulIconsStayUntouched() {
        let orange = icon([255, 115, 25, 255], count: 400, transparent: 0)
        let blue = icon([25, 128, 255, 255], count: 176, transparent: 0)
        let tone = FaviconTone.measure(premultipliedRGBA: orange + blue)
        #expect(tone.coverage == 1)
        #expect(!tone.needsBackingPlate(on: .dark))
        #expect(!tone.needsBackingPlate(on: .light))
    }

    @Test func premultipliedEdgesCountAtTheirTrueColor() {
        let tone = FaviconTone.measure(premultipliedRGBA: icon([128, 128, 128, 128], count: 10, transparent: 0))
        #expect(tone.luminance > 0.99)
        #expect(abs(tone.coverage - 128.0 / 255) < 0.001)
    }

    @Test func emptyOrNearlyEmptyIconsGetNothing() {
        #expect(!FaviconTone.measure(premultipliedRGBA: icon([0, 0, 0, 0], count: 0, transparent: 576)).needsBackingPlate(on: .dark))
        #expect(!FaviconTone.measure(premultipliedRGBA: icon([0, 0, 0, 255], count: 10, transparent: 566)).needsBackingPlate(on: .dark))
    }
}
