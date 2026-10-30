import Foundation

public struct VisitedPage: Equatable, Sendable {
    public let url: String
    public let title: String
    public let lastVisit: Date

    public init(url: String, title: String, lastVisit: Date) {
        self.url = url
        self.title = title
        self.lastVisit = lastVisit
    }
}

public struct DeploymentEnvironment: Equatable, Sendable {
    public enum Kind: Int, CaseIterable, Sendable {
        case local
        case preview
        case production
    }

    public let kind: Kind
    public let scheme: String
    public let host: String
    public let port: Int?
    public let lastVisit: Date?
    public let isCurrent: Bool

    public init(kind: Kind, scheme: String, host: String, port: Int?, lastVisit: Date?, isCurrent: Bool) {
        self.kind = kind
        self.scheme = scheme
        self.host = host
        self.port = port
        self.lastVisit = lastVisit
        self.isCurrent = isCurrent
    }

    public var displayHost: String {
        port.map { "\(host):\(String($0))" } ?? host
    }
}

public enum DeploymentEnvironments {
    public static let previewLimit = 3
    public static let linkingPathMinimum = 2

    public static func of(address: String, visitedPages: [VisitedPage], registrableDomain: (String) -> String?) -> [DeploymentEnvironment] {
        guard let current = Site(address: address, title: "", lastVisit: nil, registrableDomain: registrableDomain) else { return [] }
        var sitesByKey: [String: Site] = [:]
        for page in visitedPages {
            guard let site = Site(address: page.url, title: page.title, lastVisit: page.lastVisit, registrableDomain: registrableDomain) else { continue }
            sitesByKey[site.key] = sitesByKey[site.key].map { $0.merged(with: site) } ?? site
        }
        let sites = sitesByKey.values.sorted(by: Site.isMoreRecent)
        let currentSite = sitesByKey[current.key].map { $0.merged(with: current) } ?? current

        let previews: [Site]
        let production: Site?
        let local: Site?
        switch currentSite.kind {
        case .local:
            local = currentSite
            guard let linked = sites.first(where: { $0.kind != .local && $0.isLinked(to: currentSite) }) else {
                return [currentSite.environment(isCurrent: true)]
            }
            (previews, production) = project(of: linked, among: sites)
        case .preview, .production:
            (previews, production) = project(of: currentSite, among: sites)
            let projectSites = previews + (production.map { [$0] } ?? [])
            local = sites.first { site in site.kind == .local && projectSites.contains { site.isLinked(to: $0) } }
        }

        var listedPreviews = Array(previews.filter { $0.key != currentSite.key }.prefix(currentSite.kind == .preview ? previewLimit - 1 : previewLimit))
        if currentSite.kind == .preview {
            listedPreviews.append(currentSite)
            listedPreviews.sort(by: Site.isMoreRecent)
        }
        let listed = (local.map { [$0] } ?? []) + listedPreviews + (production.map { [$0] } ?? [])
        return listed.map { $0.environment(isCurrent: $0.key == currentSite.key) }
    }

    public static func next(in environments: [DeploymentEnvironment]) -> DeploymentEnvironment? {
        guard let current = environments.first(where: \.isCurrent) else { return nil }
        let kinds = DeploymentEnvironment.Kind.allCases
        for step in 1...kinds.count {
            let kind = kinds[(current.kind.rawValue + step) % kinds.count]
            if let candidate = environments.first(where: { $0.kind == kind && !$0.isCurrent }) {
                return candidate
            }
        }
        return nil
    }

    public static func address(_ address: String, movedTo environment: DeploymentEnvironment) -> String? {
        guard var components = URLComponents(string: address) else { return nil }
        components.scheme = environment.scheme
        components.host = environment.host
        components.port = environment.port
        return components.string
    }

    private static func project(of site: Site, among sites: [Site]) -> (previews: [Site], production: Site?) {
        if let preview = site.preview {
            let production = sites.first { $0.kind == .production && $0.productionProjects.contains(preview.project) }
            return (sites.filter { $0.preview?.project == preview.project }, production)
        }
        return (sites.filter { $0.preview.map { site.productionProjects.contains($0.project) } ?? false }, site)
    }
}

private struct TitledPath: Hashable {
    let path: String
    let title: String
}

private struct Site {
    let key: String
    let kind: DeploymentEnvironment.Kind
    let scheme: String
    let host: String
    let port: Int?
    let preview: PreviewDeployment?
    let productionProjects: [String]
    let lastVisit: Date?
    let titledPaths: Set<TitledPath>

    init?(address: String, title: String, lastVisit: Date?, registrableDomain: (String) -> String?) {
        guard let components = URLComponents(string: address), let scheme = components.scheme?.lowercased(), ["http", "https"].contains(scheme),
              let host = components.host?.lowercased(), !host.isEmpty else { return nil }
        let preview = PreviewDeployment.of(host: host)
        let productionProjects = PreviewDeployment.productionProjects(ofHost: host, registrableDomain: registrableDomain)
        if let localPort = LocalDevelopment.port(ofLocalAddress: address) {
            kind = .local
            key = "local:\(String(localPort))"
            port = localPort
        } else if preview != nil {
            kind = .preview
            key = host
            port = components.port
        } else if !productionProjects.isEmpty {
            kind = .production
            key = host
            port = components.port
        } else {
            return nil
        }
        self.scheme = scheme
        self.host = host
        self.preview = preview
        self.productionProjects = productionProjects
        self.lastVisit = lastVisit
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        titledPaths = trimmedTitle.isEmpty ? [] : [TitledPath(path: Self.normalizedPath(components.percentEncodedPath), title: trimmedTitle)]
    }

    private init(copying site: Site, lastVisit: Date?, titledPaths: Set<TitledPath>, origin: Site) {
        key = site.key
        kind = site.kind
        scheme = origin.scheme
        host = origin.host
        port = origin.port
        preview = origin.preview
        productionProjects = origin.productionProjects
        self.lastVisit = lastVisit
        self.titledPaths = titledPaths
    }

    func merged(with other: Site) -> Site {
        let newest = Self.isMoreRecent(other, self) ? other : self
        let lastVisit = [self.lastVisit, other.lastVisit].compactMap(\.self).max()
        return Site(copying: self, lastVisit: lastVisit, titledPaths: titledPaths.union(other.titledPaths), origin: newest)
    }

    func isLinked(to other: Site) -> Bool {
        Set(titledPaths.intersection(other.titledPaths).map(\.path)).count >= DeploymentEnvironments.linkingPathMinimum
    }

    func environment(isCurrent: Bool) -> DeploymentEnvironment {
        DeploymentEnvironment(kind: kind, scheme: scheme, host: host, port: port, lastVisit: lastVisit, isCurrent: isCurrent)
    }

    static func isMoreRecent(_ first: Site, _ second: Site) -> Bool {
        (first.lastVisit ?? .distantFuture) > (second.lastVisit ?? .distantFuture)
    }

    private static func normalizedPath(_ path: String) -> String {
        guard !path.isEmpty else { return "/" }
        return path.count > 1 && path.hasSuffix("/") ? String(path.dropLast()) : path
    }
}
