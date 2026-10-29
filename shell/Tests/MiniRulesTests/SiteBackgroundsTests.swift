import Testing
import MiniRules

struct SiteBackgroundsTests {
    @Test func onlyOpaqueColorsAreKept() {
        #expect(SiteBackgrounds.opaqueRGB(fromPacked: 0x1a2b3cff) == 0x1a2b3c)
        #expect(SiteBackgrounds.opaqueRGB(fromPacked: 0x1a2b3c80) == nil)
        #expect(SiteBackgrounds.opaqueRGB(fromPacked: 0) == nil)
    }

    @Test func recordingReplacesAHostAndMovesItLast() {
        var backgrounds = SiteBackgrounds(capacity: 3)
        backgrounds.record(0x111111, forHost: "a.com")
        backgrounds.record(0x222222, forHost: "b.com")
        backgrounds.record(0x333333, forHost: "a.com")
        #expect(backgrounds.rgb(forHost: "a.com") == 0x333333)
        #expect(backgrounds.entries.map(\.host) == ["b.com", "a.com"])
    }

    @Test func unchangedColorIsNotARecord() {
        var backgrounds = SiteBackgrounds(capacity: 3)
        let first = backgrounds.record(0x111111, forHost: "a.com")
        let second = backgrounds.record(0x111111, forHost: "a.com")
        #expect(first)
        #expect(!second)
    }

    @Test func oldestHostsFallOffAtCapacity() {
        var backgrounds = SiteBackgrounds(capacity: 2)
        backgrounds.record(1, forHost: "a.com")
        backgrounds.record(2, forHost: "b.com")
        backgrounds.record(3, forHost: "c.com")
        #expect(backgrounds.rgb(forHost: "a.com") == nil)
        #expect(backgrounds.entries.map(\.host) == ["b.com", "c.com"])
    }
}
