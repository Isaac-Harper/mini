import Foundation

public struct EdgeSummary: Equatable, Sendable {
    public let platform: String
    public let details: [String]

    public init(platform: String, details: [String]) {
        self.platform = platform
        self.details = details
    }

    public var text: String {
        ([platform] + details).joined(separator: " \u{00B7} ")
    }
}

public enum EdgeHeaders {
    public static let names = [
        "server", "age", "x-vercel-cache", "x-vercel-id", "cf-cache-status", "cf-ray", "x-nextjs-cache", "x-nextjs-prerender",
    ]

    public static func parse(lines: String) -> [String: String] {
        var headers: [String: String] = [:]
        for line in lines.split(separator: "\n") {
            guard let separator = line.firstIndex(of: ":") else { continue }
            let name = line[..<separator].trimmingCharacters(in: .whitespaces).lowercased()
            let value = line[line.index(after: separator)...].trimmingCharacters(in: .whitespaces)
            guard names.contains(name), !value.isEmpty, headers[name] == nil else { continue }
            headers[name] = value
        }
        return headers
    }

    public static func summary(of headers: [String: String]) -> EdgeSummary? {
        let server = headers["server"]?.lowercased()
        if headers["x-vercel-id"] != nil || headers["x-vercel-cache"] != nil || server == "vercel" {
            var details: [String] = []
            if let cache = headers["x-vercel-cache"] { details.append(cache.uppercased()) }
            if let regions = vercelRegions(headers["x-vercel-id"]) { details.append(regions) }
            if let nextCache = headers["x-nextjs-cache"] { details.append("Next.js \(nextCache.uppercased())") }
            if let age = ageText(headers["age"]) { details.append(age) }
            return EdgeSummary(platform: "Vercel", details: details)
        }
        if headers["cf-ray"] != nil || headers["cf-cache-status"] != nil || server == "cloudflare" {
            var details: [String] = []
            if let cache = headers["cf-cache-status"] { details.append(cache.uppercased()) }
            if let colo = cloudflareColo(headers["cf-ray"]) { details.append(colo) }
            if let age = ageText(headers["age"]) { details.append(age) }
            return EdgeSummary(platform: "Cloudflare", details: details)
        }
        if let nextCache = headers["x-nextjs-cache"] {
            return EdgeSummary(platform: "Next.js", details: [nextCache.uppercased()] + [ageText(headers["age"])].compactMap { $0 })
        }
        return nil
    }

    public static func vercelRegions(_ identifier: String?) -> String? {
        guard let identifier else { return nil }
        let segments = identifier.components(separatedBy: "::")
        let regions = segments.dropLast().filter(isRegionCode)
        guard let edge = regions.first else { return nil }
        guard regions.count > 1, let function = regions.last else { return edge }
        return "\(edge) \u{2192} \(function)"
    }

    public static func cloudflareColo(_ ray: String?) -> String? {
        guard let ray, let separator = ray.lastIndex(of: "-") else { return nil }
        let colo = ray[ray.index(after: separator)...]
        guard colo.count == 3, colo.allSatisfy({ $0.isASCII && $0.isLetter }) else { return nil }
        return colo.uppercased()
    }

    private static func isRegionCode(_ segment: String) -> Bool {
        let letters = segment.prefix { $0.isASCII && $0.isLetter }
        let digits = segment.dropFirst(letters.count)
        return letters.count == 3 && !digits.isEmpty && digits.allSatisfy(\.isNumber)
    }

    private static func ageText(_ value: String?) -> String? {
        guard let value, let seconds = Int(value), seconds > 0 else { return nil }
        if seconds < 60 { return "age \(seconds)s" }
        if seconds < 3600 { return "age \(seconds / 60)m" }
        if seconds < 86_400 { return "age \(seconds / 3600)h" }
        return "age \(seconds / 86_400)d"
    }
}
