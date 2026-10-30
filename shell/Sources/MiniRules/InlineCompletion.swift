public enum InlineCompletion {
    public static let minimumTypedLength = 2

    public static func isTypingForward(previous: String, current: String) -> Bool {
        current.count > previous.count && current.lowercased().hasPrefix(previous.lowercased())
    }

    public static func completion(for typed: String, hosts: [String]) -> String? {
        guard typed.count >= minimumTypedLength, !typed.hasPrefix(">"),
              !typed.contains(where: { $0.isWhitespace || $0 == "/" || $0 == ":" || $0 == "?" || $0 == "#" })
        else { return nil }
        let lowercasedTyped = typed.lowercased()
        for host in hosts {
            let bare = host.lowercased().hasPrefix("www.") ? String(host.lowercased().dropFirst(4)) : host.lowercased()
            let candidate = lowercasedTyped.hasPrefix("www.") ? "www." + bare : bare
            if candidate.count > lowercasedTyped.count, candidate.hasPrefix(lowercasedTyped) {
                return candidate
            }
        }
        return nil
    }

    public static func completedText(typed: String, completion: String) -> String {
        typed + completion.dropFirst(typed.count)
    }
}
