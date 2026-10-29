import Foundation

public enum FuzzyMatch {
    public static func score(_ query: String, in candidate: String) -> Int? {
        let needle = Array(query.lowercased().filter { !$0.isWhitespace })
        guard !needle.isEmpty else { return 0 }
        let haystack = Array(candidate.lowercased())
        var score = 0
        var needleIndex = 0
        var previousMatch: Int?
        for (index, character) in haystack.enumerated() where needleIndex < needle.count && character == needle[needleIndex] {
            let startsWord = index == 0 || !haystack[index - 1].isLetter && !haystack[index - 1].isNumber
            score += 1
            if startsWord { score += 8 }
            if let previousMatch, previousMatch == index - 1 { score += 5 }
            if index == 0 { score += 4 }
            previousMatch = index
            needleIndex += 1
        }
        guard needleIndex == needle.count else { return nil }
        return score - haystack.count / 8
    }

    public static func rank<Item>(_ items: [Item], query: String, title: (Item) -> String, identifier: (Item) -> String, recent: [String]) -> [Item] {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        let recency = Dictionary(recent.enumerated().map { ($1, $0) }, uniquingKeysWith: { first, _ in first })
        let scored: [(offset: Int, item: Item, score: Int, recency: Int?)] = items.enumerated().compactMap { offset, item in
            guard let score = score(trimmed, in: title(item)) else { return nil }
            return (offset, item, score, recency[identifier(item)])
        }
        return scored.sorted { first, second in
            switch (first.recency, second.recency) {
            case let (first?, second?): return first < second
            case (.some, nil): return true
            case (nil, .some): return false
            case (nil, nil): return first.score != second.score ? first.score > second.score : first.offset < second.offset
            }
        }.map(\.item)
    }

    public static func remembering(_ identifier: String, in recent: [String], limit: Int) -> [String] {
        Array(([identifier] + recent.filter { $0 != identifier }).prefix(limit))
    }
}
