import Foundation

public enum PlayerSlot {
    public enum Phase: Equatable, Sendable {
        case idle
        case docked
    }

    public enum Sidebar: Equatable, Sendable {
        case expanded
        case peeking
        case hidden
    }

    public enum Presentation: Equatable, Sendable {
        case page
        case row
        case slot
        case pictureInPicture
    }

    public static let homeURL = "https://www.youtube.com/"
    public static let aspectRatio: Double = 16.0 / 9.0

    public static func phase(afterLeavingWhilePlaying isPlaying: Bool) -> Phase {
        isPlaying ? .docked : .idle
    }

    public static func presentation(phase: Phase, isSelected: Bool, sidebar: Sidebar) -> Presentation {
        if isSelected { return .page }
        guard phase == .docked else { return .row }
        return sidebar == .hidden ? .pictureInPicture : .slot
    }

    public static func slotHeight(forWidth width: Double) -> Double {
        (width / aspectRatio).rounded()
    }

    public static func isYouTube(_ url: String) -> Bool {
        guard let host = host(of: url) else { return false }
        return host == "youtu.be" || host == "youtube.com" || host.hasSuffix(".youtube.com")
    }

    public static func isYouTubeVideo(_ url: String) -> Bool {
        guard let components = URLComponents(string: url), let host = host(of: url) else { return false }
        if host == "youtu.be" { return components.path.count > 1 }
        guard isYouTube(url) else { return false }
        if components.path == "/watch" { return components.queryItems?.contains { $0.name == "v" && !($0.value ?? "").isEmpty } ?? false }
        return ["/shorts/", "/live/", "/embed/"].contains { components.path.hasPrefix($0) && components.path.count > $0.count }
    }

    private static func host(of url: String) -> String? {
        guard let components = URLComponents(string: url), ["http", "https"].contains(components.scheme?.lowercased()),
              let host = components.host?.lowercased(), !host.isEmpty else { return nil }
        return host
    }
}
