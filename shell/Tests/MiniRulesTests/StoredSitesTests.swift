import Foundation
import Testing
import MiniRules

struct StoredSitesTests {
    private let kinds = [
        SitePermissionKind(bit: 1 << 0, name: "Camera"),
        SitePermissionKind(bit: 1 << 1, name: "Microphone"),
        SitePermissionKind(bit: 1 << 3, name: "Location"),
        SitePermissionKind(bit: 1 << 4, name: "Notifications", isNotifications: true),
    ]

    private func sites(
        _ decisions: [String: StoredPermissionDecision] = [:],
        exempt: Set<String> = [],
        zoom: [String: Double] = [:],
        opened: [String: Set<String>] = [:],
        names: [String: String] = [:]
    ) -> [StoredSite] {
        StoredSites.sites(
            permissionDecisions: decisions, adBlockExemptHosts: exempt, zoomLevels: zoom,
            alwaysOpenedSchemes: opened, applicationNames: names, kinds: kinds)
    }

    @Test func alwaysOpenedApplicationsJoinTheSiteAndNameEachAppOnce() {
        let result = sites([
            "https://zoom.us": StoredPermissionDecision(allowed: 1 << 1, denied: 0),
        ], opened: [
            "https://zoom.us": ["zoommtg", "zoomus"],
            "https://app.example": ["vscode"],
            "https://empty.example": [],
        ], names: ["zoommtg": "zoom.us", "zoomus": "zoom.us"])
        #expect(result.map(\.host) == ["app.example", "zoom.us"])
        #expect(result[0].origins == ["https://app.example"])
        #expect(result[0].summary == "Opens vscode: links")
        #expect(result[1].summary == "Microphone allowed, Opens zoom.us")
        #expect(StoredSites.matching(result, query: "opens zoom").map(\.host) == ["zoom.us"])
    }

    @Test func summaryListsPermissionsInKindOrderThenAdsAndZoom() {
        let summary = StoredSites.summary(allowed: 1 << 4 | 1 << 0, denied: 1 << 3, openedApplications: [], allowsAds: true, zoomLevel: 0.5, kinds: kinds)
        #expect(summary == "Camera allowed, Location blocked, Notifications on, Ads allowed, Zoom 110%")
    }

    @Test func deniedNotificationsReadOff() {
        #expect(StoredSites.summary(allowed: 0, denied: 1 << 4, openedApplications: [], allowsAds: false, zoomLevel: nil, kinds: kinds) == "Notifications off")
    }

    @Test func zoomPercentFollowsTheCefFactor() {
        #expect(StoredSites.zoomPercent(level: 0) == 100)
        #expect(StoredSites.zoomPercent(level: 1) == 120)
        #expect(StoredSites.zoomPercent(level: -1) == 83)
        #expect(StoredSites.zoomPercent(level: 0.5) == 110)
    }

    @Test func originsOfOneHostMergeIntoOneSite() {
        let result = sites([
            "https://meet.google.com": StoredPermissionDecision(allowed: 1 << 0, denied: 0),
            "http://meet.google.com:8080": StoredPermissionDecision(allowed: 1 << 1, denied: 1 << 0 | 1 << 3),
        ], exempt: ["meet.google.com"], zoom: ["meet.google.com": 1])
        #expect(result.count == 1)
        let site = result[0]
        #expect(site.host == "meet.google.com")
        #expect(site.origins == ["http://meet.google.com:8080", "https://meet.google.com"])
        #expect(site.allowedPermissions == 1 << 0 | 1 << 1)
        #expect(site.deniedPermissions == 1 << 3)
        #expect(site.summary == "Camera allowed, Microphone allowed, Location blocked, Ads allowed, Zoom 120%")
    }

    @Test func hostOnlyDecisionsMakeSitesAndZeroZoomDoesNot() {
        let result = sites(exempt: ["news.example"], zoom: ["docs.example": -1, "plain.example": 0])
        #expect(result.map(\.host) == ["docs.example", "news.example"])
        #expect(result[0].origins.isEmpty)
        #expect(result[0].summary == "Zoom 83%")
        #expect(result[1].summary == "Ads allowed")
    }

    @Test func unparsableOriginsAreSkipped() {
        #expect(sites(["not an origin": StoredPermissionDecision(allowed: 1, denied: 0)]).isEmpty)
    }

    @Test func sitesSortIgnoringWww() {
        let result = sites(exempt: ["www.zeta.example", "alpha.example", "www.beta.example", "beta.example"])
        #expect(result.map(\.host) == ["alpha.example", "beta.example", "www.beta.example", "www.zeta.example"])
    }

    @Test func searchMatchesHostOrSummaryIgnoringCase() {
        let result = sites([
            "https://meet.google.com": StoredPermissionDecision(allowed: 1 << 0, denied: 0),
        ], exempt: ["news.example"], zoom: ["docs.example": 1])
        #expect(StoredSites.matching(result, query: "").count == 3)
        #expect(StoredSites.matching(result, query: "  ").count == 3)
        #expect(StoredSites.matching(result, query: "GOOGLE").map(\.host) == ["meet.google.com"])
        #expect(StoredSites.matching(result, query: "camera").map(\.host) == ["meet.google.com"])
        #expect(StoredSites.matching(result, query: "ads ").map(\.host) == ["news.example"])
        #expect(StoredSites.matching(result, query: "zoom").map(\.host) == ["docs.example"])
        #expect(StoredSites.matching(result, query: "nothing").isEmpty)
    }
}
