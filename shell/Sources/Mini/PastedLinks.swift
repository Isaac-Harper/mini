import Foundation

struct PastedLink: Equatable, Identifiable {
    let url: String
    let title: String?

    var id: String { url }
}

enum PastedLinks {
    private static let trailingPunctuation = CharacterSet(charactersIn: ")]}>,.;:!?'\"")
    private static let pattern = try! NSRegularExpression(pattern: #"https?://[^\s<>"'`]+"#, options: [.caseInsensitive])

    static func parse(_ text: String) -> [PastedLink] {
        var links: [PastedLink] = []
        var seen: Set<String> = []
        var previousLine: String?
        for rawLine in text.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            let urls = urls(in: line)
            for url in urls where !seen.contains(url) {
                seen.insert(url)
                let title = urls.count == 1 && line == url ? previousLine : nil
                links.append(PastedLink(url: url, title: title))
            }
            previousLine = urls.isEmpty && !line.isEmpty ? line : nil
        }
        return links
    }

    private static func urls(in line: String) -> [String] {
        let range = NSRange(line.startIndex..., in: line)
        return pattern.matches(in: line, range: range).compactMap { match in
            guard let matchRange = Range(match.range, in: line) else { return nil }
            var url = String(line[matchRange])
            while let last = url.unicodeScalars.last, trailingPunctuation.contains(last) {
                url.removeLast()
            }
            guard let components = URLComponents(string: url), components.host?.isEmpty == false else { return nil }
            return url
        }
    }
}
