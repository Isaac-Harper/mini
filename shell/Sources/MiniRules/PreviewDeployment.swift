import Foundation

public struct PreviewDeployment: Equatable, Sendable {
    public enum Platform: Sendable {
        case vercel
        case netlify
        case cloudflarePages
    }

    public let platform: Platform
    public let project: String
    public let branch: String?

    public init(platform: Platform, project: String, branch: String?) {
        self.platform = platform
        self.project = project
        self.branch = branch
    }

    public static func of(host rawHost: String) -> PreviewDeployment? {
        let host = rawHost.lowercased()
        if let label = singleLabel(of: host, under: ".vercel.app") {
            return vercel(label)
        }
        if let label = singleLabel(of: host, under: ".netlify.app") {
            return netlify(label)
        }
        if host.hasSuffix(".pages.dev") {
            return cloudflarePages(host)
        }
        return nil
    }

    public static func productionProjects(ofHost rawHost: String, registrableDomain: (String) -> String?) -> [String] {
        let host = rawHost.lowercased()
        guard of(host: host) == nil else { return [] }
        for suffix in [".vercel.app", ".netlify.app", ".pages.dev"] {
            if let label = singleLabel(of: host, under: suffix) { return [label] }
        }
        if host.hasSuffix(".vercel.app") || host.hasSuffix(".netlify.app") || host.hasSuffix(".pages.dev") { return [] }
        let labels = host.split(separator: ".").map(String.init)
        guard labels.count >= 2, !labels.allSatisfy({ $0.allSatisfy(\.isNumber) }) else { return [] }
        let firstLabel = labels[0] == "www" ? labels[1] : labels[0]
        let domainLabel = (registrableDomain(host) ?? host).split(separator: ".").first.map(String.init) ?? firstLabel
        return firstLabel == domainLabel ? [firstLabel] : [firstLabel, domainLabel]
    }

    private static func singleLabel(of host: String, under suffix: String) -> String? {
        guard host.hasSuffix(suffix) else { return nil }
        let label = String(host.dropLast(suffix.count))
        return !label.isEmpty && !label.contains(".") ? label : nil
    }

    private static func isDeploymentHash(_ segment: Substring, length: Int) -> Bool {
        segment.count == length && segment.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber) }
            && segment.contains(where: \.isNumber) && segment.contains(where: \.isLetter)
    }

    private static func vercel(_ label: String) -> PreviewDeployment? {
        let segments = label.split(separator: "-", omittingEmptySubsequences: false)
        if let gitIndex = segments.firstIndex(of: "git"), gitIndex > 0 {
            let scopeLength = segments.last == "projects" ? 2 : 1
            let branchSegments = segments[(gitIndex + 1)...].dropLast(scopeLength)
            guard !branchSegments.isEmpty else { return nil }
            return PreviewDeployment(platform: .vercel, project: segments[..<gitIndex].joined(separator: "-"), branch: branchSegments.joined(separator: "-"))
        }
        guard let hashIndex = segments.lastIndex(where: { isDeploymentHash($0, length: 9) }), hashIndex > 0 else { return nil }
        return PreviewDeployment(platform: .vercel, project: segments[..<hashIndex].joined(separator: "-"), branch: nil)
    }

    private static func netlify(_ label: String) -> PreviewDeployment? {
        guard let separator = label.range(of: "--") else { return nil }
        let prefix = String(label[..<separator.lowerBound])
        let site = String(label[separator.upperBound...])
        guard !prefix.isEmpty, !site.isEmpty else { return nil }
        if prefix.hasPrefix("deploy-preview-"), prefix.dropFirst("deploy-preview-".count).allSatisfy(\.isNumber) {
            return PreviewDeployment(platform: .netlify, project: site, branch: nil)
        }
        if prefix.count == 24, prefix.allSatisfy(\.isHexDigit) {
            return PreviewDeployment(platform: .netlify, project: site, branch: nil)
        }
        return PreviewDeployment(platform: .netlify, project: site, branch: prefix)
    }

    private static func cloudflarePages(_ host: String) -> PreviewDeployment? {
        let labels = host.dropLast(".pages.dev".count).split(separator: ".", omittingEmptySubsequences: false)
        guard labels.count == 2, !labels[0].isEmpty, !labels[1].isEmpty else { return nil }
        let isHash = labels[0].count == 8 && labels[0].allSatisfy(\.isHexDigit)
        return PreviewDeployment(platform: .cloudflarePages, project: String(labels[1]), branch: isHash ? nil : String(labels[0]))
    }
}
