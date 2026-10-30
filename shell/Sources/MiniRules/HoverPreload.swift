import Foundation

public enum HoverPreload {
    private static let actionWords = ["logout", "log-out", "log_out", "signout", "sign-out", "sign_out", "delete", "unsubscribe", "remove", "destroy"]

    public static func shouldPreload(_ target: String, from page: String, registrableDomain: (String) -> String?) -> Bool {
        guard let targetComponents = URLComponents(string: target), let pageComponents = URLComponents(string: page),
              let scheme = targetComponents.scheme?.lowercased(), ["http", "https"].contains(scheme),
              pageComponents.scheme?.lowercased() == scheme,
              let targetHost = targetComponents.host?.lowercased(), let pageHost = pageComponents.host?.lowercased(), !targetHost.isEmpty
        else { return false }
        guard (registrableDomain(targetHost) ?? targetHost) == (registrableDomain(pageHost) ?? pageHost) else { return false }
        guard !isSameDocument(targetComponents, pageComponents) else { return false }
        return !looksLikeAction(targetComponents)
    }

    public static func looksLikeAction(_ components: URLComponents) -> Bool {
        let path = components.percentEncodedPath.lowercased()
        if actionWords.contains(where: path.contains) { return true }
        for item in components.queryItems ?? [] {
            let name = item.name.lowercased()
            let value = (item.value ?? "").lowercased()
            if name == "action" || name == "do" || name == "method" { return true }
            if actionWords.contains(where: { name.contains($0) || value.contains($0) }) { return true }
        }
        return false
    }

    private static func isSameDocument(_ target: URLComponents, _ page: URLComponents) -> Bool {
        var targetWithoutFragment = target
        var pageWithoutFragment = page
        targetWithoutFragment.fragment = nil
        pageWithoutFragment.fragment = nil
        return targetWithoutFragment.string == pageWithoutFragment.string
    }
}
