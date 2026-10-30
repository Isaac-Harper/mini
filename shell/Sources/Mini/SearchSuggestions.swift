import Foundation

enum SearchSuggestions {
    static func parse(_ data: Data) -> [String]? {
        guard let response = try? JSONSerialization.jsonObject(with: data) as? [Any],
              response.count >= 2,
              let suggestions = response[1] as? [String]
        else { return nil }
        return suggestions
    }

    static func requestURL(for query: String) -> URL? {
        var components = URLComponents(string: "https://suggestqueries.google.com/complete/search")
        components?.queryItems = [
            URLQueryItem(name: "client", value: "firefox"),
            URLQueryItem(name: "ie", value: "utf-8"),
            URLQueryItem(name: "oe", value: "utf-8"),
            URLQueryItem(name: "q", value: query),
        ]
        return components?.url
    }
}

@MainActor
final class SearchSuggestionFetcher {
    private var pendingFetch: Task<Void, Never>?

    private static let debounce: Duration = .milliseconds(120)
    private static let maximumQueryLength = 200

    func fetch(_ query: String, deliver: @escaping @MainActor ([String], String) -> Void) {
        pendingFetch?.cancel()
        pendingFetch = nil
        guard !query.isEmpty, query.count <= Self.maximumQueryLength, case .search = URLInput.interpret(query),
              let url = SearchSuggestions.requestURL(for: query)
        else { return }
        pendingFetch = Task { @MainActor in
            do {
                try await Task.sleep(for: Self.debounce)
                let (data, _) = try await URLSession.shared.data(from: url)
                guard !Task.isCancelled, let suggestions = SearchSuggestions.parse(data) else { return }
                deliver(suggestions, query)
            } catch {
                return
            }
        }
    }

    func cancel() {
        pendingFetch?.cancel()
        pendingFetch = nil
    }
}
