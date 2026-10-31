import Foundation
import Testing
import MiniRules

struct DevBuildTests {
    private let start = Date(timeIntervalSinceReferenceDate: 1_000_000)

    @Test func aRebuildEndsWhenReady() {
        var status = DevBuildStatus()
        status.apply(.rebuilding, at: start)
        #expect(status.isRebuilding)
        #expect(status.rebuildExpiry() == start.addingTimeInterval(10))
        status.apply(.ready(milliseconds: 230), at: start.addingTimeInterval(1))
        #expect(!status.isRebuilding)
        #expect(status.rebuildExpiry() == nil)
    }

    @Test func aRebuildTimesOutAfterTenSeconds() {
        var status = DevBuildStatus()
        status.apply(.rebuilding, at: start)
        status.expireRebuild(at: start.addingTimeInterval(9.9))
        #expect(status.isRebuilding)
        status.expireRebuild(at: start.addingTimeInterval(10))
        #expect(!status.isRebuilding)
    }

    @Test func aLaterRebuildRestartsTheTimeout() {
        var status = DevBuildStatus()
        status.apply(.rebuilding, at: start)
        status.apply(.rebuilding, at: start.addingTimeInterval(8))
        status.expireRebuild(at: start.addingTimeInterval(10))
        #expect(status.isRebuilding)
        #expect(status.rebuildExpiry() == start.addingTimeInterval(18))
    }

    @Test func aCompileErrorEndsTheRebuildAndClearsWithTheOverlayOrTheNextReady() {
        var status = DevBuildStatus()
        status.apply(.rebuilding, at: start)
        status.apply(.compileErrorShown(detail: "Module not found: ./missing"), at: start)
        #expect(!status.isRebuilding)
        #expect(status.hasCompileError)
        #expect(status.compileErrorDetail == "Module not found: ./missing")
        status.apply(.compileErrorCleared, at: start)
        #expect(!status.hasCompileError)
        status.apply(.compileErrorShown(detail: ""), at: start)
        #expect(status.hasCompileError)
        #expect(status.compileErrorDetail == nil)
        status.apply(.ready(milliseconds: nil), at: start)
        #expect(!status.hasCompileError)
    }

    @Test func aRebuildKeepsAnErrorUntilItIsReady() {
        var status = DevBuildStatus()
        status.apply(.compileErrorShown(detail: "x"), at: start)
        status.apply(.rebuilding, at: start)
        #expect(status.hasCompileError)
        #expect(status.isRebuilding)
    }

    @Test func theDetailIsOneShortLine() {
        var status = DevBuildStatus()
        status.apply(.compileErrorShown(detail: String(repeating: "a", count: 120) + "\nsecond"), at: start)
        #expect(status.compileErrorDetail == String(repeating: "a", count: 79) + "\u{2026}")
    }

    @Test func refreshLabelsUseTheDurationText() {
        #expect(DevBuildStatus.refreshLabel(milliseconds: 230) == "refresh 230ms")
        #expect(DevBuildStatus.refreshLabel(milliseconds: 1400) == "refresh 1.4s")
    }

    @Test func onlyLocalDevelopmentCollectsBuilds() {
        #expect(PageHealth.collectsBuilds(for: "http://localhost:3000/"))
        #expect(PageHealth.collectsBuilds(for: "http://127.0.0.1:5173/app"))
        #expect(!PageHealth.collectsBuilds(for: "https://mini-git-feature-isaac.vercel.app/"))
        #expect(!PageHealth.collectsBuilds(for: "https://example.com/"))
    }
}
