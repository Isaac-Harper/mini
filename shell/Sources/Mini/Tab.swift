import AppKit
import CMiniCore
import MiniRules
import Observation

@MainActor
@Observable
final class Tab: Identifiable {
    let id: MiniTabId
    var url: String
    var title: String {
        didSet {
            if title != oldValue { refreshUnread() }
        }
    }
    private(set) var unread: UnreadTitle?
    var unreadPulses = 0
    @ObservationIgnored private var unreadTracker = UnreadBadgeTracker()
    var favicon: NSImage? {
        didSet {
            if favicon !== oldValue { faviconTone = favicon.map(FaviconTone.of) }
        }
    }
    private(set) var faviconTone: FaviconTone?
    @ObservationIgnored var faviconArrivedLive = false
    var pinnedURL: String?
    var savedURL: String?
    @ObservationIgnored var savedTitle = ""
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
    var mediaVideoURL = ""
    var mediaArtwork: NSImage? {
        didSet { mediaArtworkTint = mediaArtwork.flatMap(DominantColor.of) }
    }
    @ObservationIgnored private(set) var mediaArtworkTint: NSColor?
    var isPausedFromNowPlaying = false
    var playerPhase = PlayerSlot.Phase.idle
    var themeColor: NSColor?
    var vitals = WebVitals()
    var edge: EdgeSummary?
    var reloadDurationText: String?
    @ObservationIgnored var reloadDurationGeneration = 0
    @ObservationIgnored var awaitsReloadTiming = false
    var idleFade = 1.0
    var dayFold: DayFold?
    @ObservationIgnored var horizontalScrollRoom = HorizontalScrollRoom()

    @ObservationIgnored weak var parent: Tab?
    @ObservationIgnored let hostView = BrowserHostView()
    @ObservationIgnored var browserState = BrowserState.none
    @ObservationIgnored var needsInitialFocus = false
    @ObservationIgnored var refocusesOnCommit = false
    @ObservationIgnored var lastSelectedAt = Date()
    @ObservationIgnored var hasCrashed = false
    @ObservationIgnored var zoomedHost: String?
    @ObservationIgnored var devServerWait: DevServerWait?

    init(id: MiniTabId, url: String, title: String) {
        self.id = id
        self.url = url
        self.title = title
        refreshUnread()
    }

    private func refreshUnread() {
        let address = URL(string: url)
        unread = unreadTracker.update(title: title, host: address?.host()?.lowercased(), path: address?.path() ?? "")
    }

    enum BrowserState {
        case none
        case pendingPopup
        case created
    }

    var hasBrowser: Bool { browserState == .created }

    var isPinned: Bool { pinnedURL != nil }

    var isSaved: Bool { savedURL != nil }

    var hasLeftSavedURL: Bool {
        guard let savedURL else { return false }
        return !url.isEmpty && url != savedURL
    }

    var displayTitle: String {
        let title = unread?.title ?? title
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
