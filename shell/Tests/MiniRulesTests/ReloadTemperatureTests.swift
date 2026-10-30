import Foundation
import Testing
import MiniRules

struct ReloadTemperatureTests {
    private let start = Date(timeIntervalSinceReferenceDate: 1_000_000)
    private let page = "http://localhost:5173/"

    @Test func aReloadWithoutCacheIsColdAndRemembered() {
        let result = ReloadTemperatures.reload(ignoringCache: true, url: page, at: start, after: nil)
        #expect(result.temperature == .cold)
        #expect(result.remembered == ColdReload(url: page, date: start))
    }

    @Test func theNextNormalReloadOfTheSameURLIsWarmOnce() {
        let cold = ColdReload(url: page, date: start)
        let warm = ReloadTemperatures.reload(ignoringCache: false, url: page, at: start.addingTimeInterval(20), after: cold)
        #expect(warm.temperature == .warm)
        #expect(warm.remembered == nil)
        #expect(ReloadTemperatures.reload(ignoringCache: false, url: page, at: start.addingTimeInterval(30), after: warm.remembered).temperature == .plain)
    }

    @Test func anotherURLOrAnExpiredWindowIsPlain() {
        let cold = ColdReload(url: page, date: start)
        #expect(ReloadTemperatures.reload(ignoringCache: false, url: "http://localhost:5173/other", at: start.addingTimeInterval(5), after: cold).temperature == .plain)
        #expect(ReloadTemperatures.reload(ignoringCache: false, url: page, at: start.addingTimeInterval(601), after: cold).temperature == .plain)
        #expect(ReloadTemperatures.reload(ignoringCache: false, url: page, at: start.addingTimeInterval(-1), after: cold).temperature == .plain)
        #expect(ReloadTemperatures.reload(ignoringCache: false, url: page, at: start, after: nil).temperature == .plain)
    }

    @Test func labelsNameTheTemperatureOnlyWhenItIsKnown() {
        #expect(ReloadTemperatures.label(milliseconds: 142, temperature: .plain) == "142ms")
        #expect(ReloadTemperatures.label(milliseconds: 1400, temperature: .cold) == "cold 1.4s")
        #expect(ReloadTemperatures.label(milliseconds: 210, temperature: .warm) == "warm 210ms")
    }

    @Test func twoWordLabelsHoldLonger() {
        #expect(ReloadTemperatures.hold(for: .plain) == 1.5)
        #expect(ReloadTemperatures.hold(for: .cold) == 2)
        #expect(ReloadTemperatures.hold(for: .warm) == 2)
    }
}
