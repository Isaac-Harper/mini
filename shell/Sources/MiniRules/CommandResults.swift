import Foundation

public enum CommandSection: Hashable, Sendable {
    case primary
    case tabs
    case localServers
    case history
    case archived
    case suggestions
}

public struct CommandCandidate<Item> {
    public let item: Item
    public let section: CommandSection
    public let key: String?

    public init(_ item: Item, section: CommandSection, key: String?) {
        self.item = item
        self.section = section
        self.key = key
    }
}

public struct CommandResultLimits: Sendable {
    public let order: [CommandSection]
    public let perSection: [CommandSection: Int]
    public let localRows: Int

    public static let typed = CommandResultLimits(order: [.tabs, .localServers, .history, .archived],
                                                  perSection: [.tabs: 4, .localServers: 3, .history: 4, .archived: 3, .suggestions: 3], localRows: 6)
    public static let empty = CommandResultLimits(order: [.tabs, .history, .localServers],
                                                  perSection: [.tabs: 4, .history: 3, .localServers: 3], localRows: 8)

    public func limit(_ section: CommandSection) -> Int {
        perSection[section] ?? 0
    }
}

public enum CommandResults {
    public static func assemble<Item>(primary: CommandCandidate<Item>?, candidates: [CommandCandidate<Item>], suggestions: [CommandCandidate<Item>],
                                      limits: CommandResultLimits, excluding excludedKeys: Set<String> = []) -> [CommandCandidate<Item>] {
        var rows: [CommandCandidate<Item>] = []
        var seen: Set<String> = []
        var promotedIndex: Int?
        if let primary {
            if let key = primary.key, let index = candidates.firstIndex(where: { $0.section == .tabs && $0.key == key }) {
                promotedIndex = index
                rows.append(candidates[index])
            } else {
                rows.append(primary)
            }
            if let key = primary.key { seen.insert(key) }
        }
        var localCount = 0
        for section in limits.order {
            var sectionCount = 0
            for (index, candidate) in candidates.enumerated() where candidate.section == section && index != promotedIndex {
                guard sectionCount < limits.limit(section), localCount < limits.localRows else { break }
                if let key = candidate.key {
                    guard section == .tabs || !excludedKeys.contains(key), seen.insert(key).inserted else { continue }
                }
                rows.append(candidate)
                sectionCount += 1
                localCount += 1
            }
        }
        var suggestionCount = 0
        for suggestion in suggestions where suggestionCount < limits.limit(.suggestions) {
            if let key = suggestion.key {
                guard seen.insert(key).inserted else { continue }
            }
            rows.append(suggestion)
            suggestionCount += 1
        }
        return rows
    }

    public static func key(forAddress address: String) -> String {
        guard let components = URLComponents(string: address), let rawHost = components.host, !rawHost.isEmpty else {
            return address.lowercased()
        }
        let lowercasedHost = rawHost.lowercased()
        let host = lowercasedHost.hasPrefix("www.") ? String(lowercasedHost.dropFirst(4)) : lowercasedHost
        let scheme = components.scheme?.lowercased() ?? ""
        let schemeFamily = scheme == "http" || scheme == "https" ? "web" : scheme
        let port = components.port.map { ":\($0)" } ?? ""
        var path = components.percentEncodedPath
        if path.hasSuffix("/") { path.removeLast() }
        let query = components.percentEncodedQuery.map { "?" + $0 } ?? ""
        return "\(schemeFamily)://\(host)\(port)\(path)\(query)"
    }

    public static func key(forSearch query: String) -> String {
        "search:" + query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    public static func retainedSuggestions(_ previous: [String], query: String) -> [String] {
        let lowercasedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !lowercasedQuery.isEmpty else { return [] }
        return previous.filter { suggestion in
            let lowercased = suggestion.lowercased()
            return lowercased.hasPrefix(lowercasedQuery) && lowercased != lowercasedQuery
        }
    }
}
