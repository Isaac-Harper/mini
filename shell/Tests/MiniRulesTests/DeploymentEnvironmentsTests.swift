import Foundation
import Testing
import MiniRules

struct DeploymentEnvironmentsTests {
    private static func lastTwoLabels(_ host: String) -> String? {
        let labels = host.split(separator: ".")
        return labels.count >= 2 ? labels.suffix(2).joined(separator: ".") : nil
    }

    private static func page(_ url: String, _ title: String = "", minutesAgo: Double) -> VisitedPage {
        VisitedPage(url: url, title: title, lastVisit: Date(timeIntervalSinceReferenceDate: 1_000_000 - minutesAgo * 60))
    }

    private static func environments(_ address: String, _ pages: [VisitedPage]) -> [DeploymentEnvironment] {
        DeploymentEnvironments.of(address: address, visitedPages: pages, registrableDomain: lastTwoLabels)
    }

    private static func hosts(_ environments: [DeploymentEnvironment]) -> [String] {
        environments.map(\.displayHost)
    }

    private static let linkedLocalPages = [
        page("http://localhost:3000/", "Mini", minutesAgo: 5),
        page("http://localhost:3000/pricing", "Pricing | Mini", minutesAgo: 4),
        page("https://mini-git-feature-isaac.vercel.app/", "Mini", minutesAgo: 30),
        page("https://mini-git-feature-isaac.vercel.app/pricing/", "Pricing | Mini", minutesAgo: 31),
        page("https://mini.dev/docs", "Docs | Mini", minutesAgo: 60),
    ]

    @Test func previewPairsOnlyWithAVisitedProduction() {
        let preview = "https://mini-git-feature-isaac.vercel.app/a"
        let found = Self.environments(preview, [
            Self.page("https://github.com/", minutesAgo: 1),
            Self.page("https://mini.dev/", minutesAgo: 2),
            Self.page("https://mini.vercel.app/", minutesAgo: 3),
        ])
        #expect(Self.hosts(found) == ["mini-git-feature-isaac.vercel.app", "mini.dev"])
        #expect(found.map(\.kind) == [.preview, .production])
        #expect(found.map(\.isCurrent) == [true, false])
        #expect(Self.hosts(Self.environments(preview, [Self.page("https://minimal.dev/", minutesAgo: 1)])) == ["mini-git-feature-isaac.vercel.app"])
        #expect(Self.hosts(Self.environments(preview, [])) == ["mini-git-feature-isaac.vercel.app"])
    }

    @Test func productionListsVisitedPreviewsMostRecentFirstCappedAtThree() {
        let found = Self.environments("https://mini.dev/", [
            Self.page("https://mini-git-a-isaac.vercel.app/", minutesAgo: 40),
            Self.page("https://mini-a1b2c3d4e-isaac.vercel.app/", minutesAgo: 10),
            Self.page("https://mini-git-b-isaac.vercel.app/", minutesAgo: 20),
            Self.page("https://mini-git-c-isaac.vercel.app/", minutesAgo: 30),
            Self.page("https://other-git-a-isaac.vercel.app/", minutesAgo: 1),
        ])
        #expect(Self.hosts(found) == ["mini-a1b2c3d4e-isaac.vercel.app", "mini-git-b-isaac.vercel.app", "mini-git-c-isaac.vercel.app", "mini.dev"])
        #expect(Self.hosts(Self.environments("https://other.dev/", [Self.page("https://mini-git-a-isaac.vercel.app/", minutesAgo: 1)])) == ["other.dev"])
    }

    @Test func theCurrentPreviewStaysListedBesideTheNewestOthers() {
        let found = Self.environments("https://mini-git-old-isaac.vercel.app/", [
            Self.page("https://mini-git-old-isaac.vercel.app/", minutesAgo: 90),
            Self.page("https://mini-git-a-isaac.vercel.app/", minutesAgo: 10),
            Self.page("https://mini-git-b-isaac.vercel.app/", minutesAgo: 20),
            Self.page("https://mini-git-c-isaac.vercel.app/", minutesAgo: 30),
        ])
        #expect(Self.hosts(found) == ["mini-git-a-isaac.vercel.app", "mini-git-b-isaac.vercel.app", "mini-git-old-isaac.vercel.app"])
        #expect(found.last?.isCurrent == true)
    }

    @Test func localhostLinksThroughTwoPathsWithTheSameTitle() {
        let found = Self.environments("http://localhost:3000/pricing", Self.linkedLocalPages)
        #expect(Self.hosts(found) == ["localhost:3000", "mini-git-feature-isaac.vercel.app", "mini.dev"])
        #expect(found.map(\.kind) == [.local, .preview, .production])
        #expect(found.first?.isCurrent == true)
    }

    @Test func previewAndProductionFindTheLinkedLocalPort() {
        let fromPreview = Self.environments("https://mini-git-feature-isaac.vercel.app/", Self.linkedLocalPages)
        #expect(Self.hosts(fromPreview) == ["localhost:3000", "mini-git-feature-isaac.vercel.app", "mini.dev"])
        let fromProduction = Self.environments("https://mini.dev/docs", Self.linkedLocalPages)
        #expect(Self.hosts(fromProduction) == ["localhost:3000", "mini-git-feature-isaac.vercel.app", "mini.dev"])
        #expect(fromProduction.last?.isCurrent == true)
    }

    @Test func localhostLinksStraightToAProductionWithoutPreviews() {
        let found = Self.environments("http://localhost:5173/", [
            Self.page("http://localhost:5173/", "Acme", minutesAgo: 1),
            Self.page("http://localhost:5173/about", "About Acme", minutesAgo: 2),
            Self.page("https://acme.com/", "Acme", minutesAgo: 100),
            Self.page("https://acme.com/about", "About Acme", minutesAgo: 101),
        ])
        #expect(Self.hosts(found) == ["localhost:5173", "acme.com"])
    }

    @Test func oneSharedPageOrDifferentTitlesNeverLink() {
        let onePath = Self.environments("http://localhost:3000/", [
            Self.page("http://localhost:3000/", "Mini", minutesAgo: 1),
            Self.page("http://localhost:3000/pricing", "Pricing | Mini", minutesAgo: 2),
            Self.page("https://mini.dev/", "Mini", minutesAgo: 3),
            Self.page("https://mini.dev/pricing", "Pricing", minutesAgo: 4),
        ])
        #expect(Self.hosts(onePath) == ["localhost:3000"])
        let commonPaths = Self.environments("http://localhost:3000/login", [
            Self.page("http://localhost:3000/login", "Log in | Mini", minutesAgo: 1),
            Self.page("http://localhost:3000/settings", "Settings | Mini", minutesAgo: 2),
            Self.page("https://github.com/login", "Sign in to GitHub", minutesAgo: 3),
            Self.page("https://github.com/settings", "Settings", minutesAgo: 4),
        ])
        #expect(Self.hosts(commonPaths) == ["localhost:3000"])
        let untitled = Self.environments("http://localhost:3000/", [
            Self.page("http://localhost:3000/", minutesAgo: 1),
            Self.page("http://localhost:3000/a", minutesAgo: 2),
            Self.page("https://mini.dev/", minutesAgo: 3),
            Self.page("https://mini.dev/a", minutesAgo: 4),
        ])
        #expect(Self.hosts(untitled) == ["localhost:3000"])
    }

    @Test func aReusedPortFollowsTheMostRecentlyVisitedLinkedProject() {
        let found = Self.environments("http://localhost:3000/", [
            Self.page("http://localhost:3000/", "Home", minutesAgo: 1),
            Self.page("http://localhost:3000/team", "Team", minutesAgo: 2),
            Self.page("https://old.dev/", "Home", minutesAgo: 500),
            Self.page("https://old.dev/team", "Team", minutesAgo: 501),
            Self.page("https://new.dev/", "Home", minutesAgo: 50),
            Self.page("https://new.dev/team", "Team", minutesAgo: 51),
        ])
        #expect(Self.hosts(found) == ["localhost:3000", "new.dev"])
    }

    @Test func localPortsMergeLoopbackNamesAndKeepTheNewestOrigin() {
        let found = Self.environments("https://mini.dev/", [
            Self.page("http://127.0.0.1:3000/", "Mini", minutesAgo: 9),
            Self.page("http://localhost:3000/pricing", "Pricing | Mini", minutesAgo: 2),
            Self.page("https://mini.dev/", "Mini", minutesAgo: 3),
            Self.page("https://mini.dev/pricing", "Pricing | Mini", minutesAgo: 4),
        ])
        #expect(Self.hosts(found) == ["localhost:3000", "mini.dev"])
        #expect(found.first?.lastVisit == Date(timeIntervalSinceReferenceDate: 1_000_000 - 120))
    }

    @Test func pagesWithoutAnEnvironmentHaveNone() {
        #expect(Self.environments("file:///tmp/a.html", Self.linkedLocalPages).isEmpty)
        #expect(Self.environments("http://10.0.0.5/", Self.linkedLocalPages).isEmpty)
        #expect(Self.environments("about:blank", Self.linkedLocalPages).isEmpty)
    }

    @Test func cycleRunsLocalPreviewProductionAndBack() {
        let all = Self.linkedLocalPages
        let fromLocal = DeploymentEnvironments.next(in: Self.environments("http://localhost:3000/", all))
        #expect(fromLocal?.displayHost == "mini-git-feature-isaac.vercel.app")
        let fromPreview = DeploymentEnvironments.next(in: Self.environments("https://mini-git-feature-isaac.vercel.app/", all))
        #expect(fromPreview?.displayHost == "mini.dev")
        let fromProduction = DeploymentEnvironments.next(in: Self.environments("https://mini.dev/", all))
        #expect(fromProduction?.displayHost == "localhost:3000")
    }

    @Test func cycleSkipsMissingEnvironments() {
        let previewsOnly = [
            Self.page("https://mini-git-a-isaac.vercel.app/", minutesAgo: 1),
            Self.page("https://mini-git-b-isaac.vercel.app/", minutesAgo: 2),
            Self.page("https://mini-git-c-isaac.vercel.app/", minutesAgo: 3),
        ]
        #expect(DeploymentEnvironments.next(in: Self.environments("https://mini-git-c-isaac.vercel.app/", previewsOnly))?.displayHost == "mini-git-a-isaac.vercel.app")
        let productionAndPreview = [Self.page("https://mini-git-a-isaac.vercel.app/", minutesAgo: 1)]
        #expect(DeploymentEnvironments.next(in: Self.environments("https://mini.dev/", productionAndPreview))?.displayHost == "mini-git-a-isaac.vercel.app")
        #expect(DeploymentEnvironments.next(in: Self.environments("https://github.com/", previewsOnly)) == nil)
        #expect(DeploymentEnvironments.next(in: []) == nil)
    }

    @Test func movingKeepsPathQueryAndFragment() {
        let local = DeploymentEnvironment(kind: .local, scheme: "http", host: "localhost", port: 3000, lastVisit: nil, isCurrent: false)
        #expect(DeploymentEnvironments.address("https://mini.dev/docs/a?tab=2#install", movedTo: local) == "http://localhost:3000/docs/a?tab=2#install")
        let production = DeploymentEnvironment(kind: .production, scheme: "https", host: "mini.dev", port: nil, lastVisit: nil, isCurrent: false)
        #expect(DeploymentEnvironments.address("http://localhost:3000/pricing?plan=pro", movedTo: production) == "https://mini.dev/pricing?plan=pro")
    }
}
