import Foundation

public struct SitePermissionKind: Sendable, Equatable {
    public let bit: UInt32
    public let name: String
    public let isNotifications: Bool

    public init(bit: UInt32, name: String, isNotifications: Bool = false) {
        self.bit = bit
        self.name = name
        self.isNotifications = isNotifications
    }
}

public struct StoredPermissionDecision: Sendable, Equatable {
    public let allowed: UInt32
    public let denied: UInt32

    public init(allowed: UInt32, denied: UInt32) {
        self.allowed = allowed
        self.denied = denied
    }
}

public struct StoredSite: Sendable, Equatable, Identifiable {
    public let host: String
    public let origins: [String]
    public let allowedPermissions: UInt32
    public let deniedPermissions: UInt32
    public let allowsAds: Bool
    public let zoomLevel: Double?
    public let summary: String

    public var id: String { host }
}

public enum StoredSites {
    public static func sites(
        permissionDecisions: [String: StoredPermissionDecision],
        adBlockExemptHosts: Set<String>,
        zoomLevels: [String: Double],
        kinds: [SitePermissionKind]
    ) -> [StoredSite] {
        var originsByHost: [String: [String]] = [:]
        for origin in permissionDecisions.keys {
            guard let host = host(ofOrigin: origin) else { continue }
            originsByHost[host, default: []].append(origin)
        }
        let hosts = Set(originsByHost.keys)
            .union(adBlockExemptHosts)
            .union(zoomLevels.filter { $0.value != 0 }.keys)
        return hosts.map { host in
            let origins = (originsByHost[host] ?? []).sorted()
            let allowed = origins.reduce(UInt32(0)) { $0 | (permissionDecisions[$1]?.allowed ?? 0) }
            let denied = origins.reduce(UInt32(0)) { $0 | (permissionDecisions[$1]?.denied ?? 0) } & ~allowed
            let zoomLevel = zoomLevels[host].flatMap { $0 == 0 ? nil : $0 }
            let allowsAds = adBlockExemptHosts.contains(host)
            return StoredSite(
                host: host,
                origins: origins,
                allowedPermissions: allowed,
                deniedPermissions: denied,
                allowsAds: allowsAds,
                zoomLevel: zoomLevel,
                summary: summary(allowed: allowed, denied: denied, allowsAds: allowsAds, zoomLevel: zoomLevel, kinds: kinds)
            )
        }
        .sorted(by: isOrderedBefore)
    }

    public static func summary(allowed: UInt32, denied: UInt32, allowsAds: Bool, zoomLevel: Double?, kinds: [SitePermissionKind]) -> String {
        var parts: [String] = []
        for kind in kinds {
            if allowed & kind.bit != 0 {
                parts.append(kind.isNotifications ? "\(kind.name) on" : "\(kind.name) allowed")
            } else if denied & kind.bit != 0 {
                parts.append(kind.isNotifications ? "\(kind.name) off" : "\(kind.name) blocked")
            }
        }
        if allowsAds { parts.append("Ads allowed") }
        if let zoomLevel { parts.append("Zoom \(zoomPercent(level: zoomLevel))%") }
        return parts.joined(separator: ", ")
    }

    public static func zoomPercent(level: Double) -> Int {
        Int((pow(1.2, level) * 100).rounded())
    }

    public static func matching(_ sites: [StoredSite], query: String) -> [StoredSite] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !needle.isEmpty else { return sites }
        return sites.filter { $0.host.contains(needle) || $0.summary.lowercased().contains(needle) }
    }

    public static func host(ofOrigin origin: String) -> String? {
        guard let host = URLComponents(string: origin)?.host?.lowercased(), !host.isEmpty else { return nil }
        return host
    }

    private static func isOrderedBefore(_ first: StoredSite, _ second: StoredSite) -> Bool {
        let firstKey = sortKey(first.host)
        let secondKey = sortKey(second.host)
        return firstKey == secondKey ? first.host < second.host : firstKey < secondKey
    }

    private static func sortKey(_ host: String) -> String {
        host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }
}
