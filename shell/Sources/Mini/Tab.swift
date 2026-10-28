import AppKit
import CMiniCore
import Observation

@MainActor
@Observable
final class Tab: Identifiable {
    let id: MiniTabId
    var url: String
    var title: String
    var favicon: NSImage?
    var pinnedURL: String?
    var isLoading = false
    @ObservationIgnored var loadingProgress = 1.0
    var canGoBack = false
    var canGoForward = false
    var children: [Tab] = []
    var isCollapsed = false
    var hasLoginForm = false
    var isPlayingAudio = false
    var isAudioMuted = false
    var mediaTitle = ""
    var isPausedFromNowPlaying = false
    var themeColor: NSColor?
    @ObservationIgnored var horizontalScrollRoom = HorizontalScrollRoom()

    @ObservationIgnored weak var parent: Tab?
    @ObservationIgnored let hostView = BrowserHostView()
    @ObservationIgnored var browserState = BrowserState.none
    @ObservationIgnored var needsInitialFocus = false
    @ObservationIgnored var lastSelectedAt = Date()
    @ObservationIgnored var hasCrashed = false
    @ObservationIgnored var zoomedHost: String?

    init(id: MiniTabId, url: String, title: String) {
        self.id = id
        self.url = url
        self.title = title
    }

    enum BrowserState {
        case none
        case pendingPopup
        case created
    }

    var hasBrowser: Bool { browserState == .created }

    var isPinned: Bool { pinnedURL != nil }

    var displayTitle: String {
        if !title.isEmpty { return title }
        if let host = URLInput.host(of: url) { return host }
        return "New Tab"
    }

    var subtree: [Tab] {
        [self] + children.flatMap(\.subtree)
    }

    func isDescendant(of ancestor: Tab) -> Bool {
        var current = parent
        while let candidate = current {
            if candidate === ancestor { return true }
            current = candidate.parent
        }
        return false
    }
}
