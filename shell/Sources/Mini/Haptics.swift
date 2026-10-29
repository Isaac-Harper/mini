import AppKit
import CMiniCore

enum HapticMoment: String {
    case sidebarCollapseSnap
    case sidebarWidthLimit
    case splitCenter
    case splitMinimum
    case tabDragTarget
    case peekSidebarOpened
    case tabDropChangedPlacement
    case swipeNavigationThreshold
    case spaceSwipeThreshold
    case tabTornOff
    case littleWindowDocked

    var pattern: NSHapticFeedbackManager.FeedbackPattern {
        switch self {
        case .sidebarWidthLimit, .splitCenter, .splitMinimum, .tabDragTarget, .peekSidebarOpened: .alignment
        case .sidebarCollapseSnap, .tabDropChangedPlacement, .swipeNavigationThreshold, .spaceSwipeThreshold, .tabTornOff, .littleWindowDocked: .levelChange
        }
    }

    var performanceTime: NSHapticFeedbackManager.PerformanceTime {
        self == .sidebarCollapseSnap ? .now : .drawCompleted
    }
}

struct HapticGate {
    static let minimumInterval: TimeInterval = 0.09

    private(set) var lastAdmitted: TimeInterval?

    mutating func admit(at time: TimeInterval, duringMomentum: Bool) -> Bool {
        guard !duringMomentum else { return false }
        if let lastAdmitted, time - lastAdmitted < Self.minimumInterval { return false }
        lastAdmitted = time
        return true
    }
}

struct ThresholdCrossing {
    static let rearmFraction: CGFloat = 0.9

    private(set) var isArmed = false

    mutating func update(progress: CGFloat) -> Bool {
        if !isArmed, progress >= 1 {
            isArmed = true
            return true
        }
        if isArmed, progress < Self.rearmFraction {
            isArmed = false
        }
        return false
    }
}

struct DetentEntry<Detent: Equatable> {
    private(set) var current: Detent?

    mutating func update(_ detent: Detent?) -> Bool {
        defer { current = detent }
        return detent != nil && detent != current
    }
}

struct DetentChange<Detent: Equatable> {
    private(set) var current: Detent?

    mutating func update(_ detent: Detent?) -> Bool {
        guard let detent else { return false }
        defer { current = detent }
        return current != nil && detent != current
    }

    mutating func reset() {
        current = nil
    }
}

enum TabDragDetent: Equatable {
    enum Section: Equatable {
        case saved
        case regular
    }

    case reorder(Section)
    case nest(Section)
    case pinnedArea
    case tearOff

    static func of(_ target: SidebarDragModel.Target?, isPastTearOff: Bool, savedRow: (MiniTabId) -> Bool) -> TabDragDetent? {
        if isPastTearOff { return .tearOff }
        switch target {
        case nil: return nil
        case .pinned: return .pinnedArea
        case .savedEnd: return .reorder(.saved)
        case .end: return .reorder(.regular)
        case let .row(identifier, position):
            let section: Section = savedRow(identifier) ? .saved : .regular
            return position == .inside ? .nest(section) : .reorder(section)
        }
    }
}

enum SidebarWidthEdge: Equatable {
    case minimum
    case maximum

    static func of(width: CGFloat, minimum: CGFloat, maximum: CGFloat) -> SidebarWidthEdge? {
        if width <= minimum + 0.5 { return .minimum }
        if width >= maximum - 0.5 { return .maximum }
        return nil
    }
}

enum SplitDividerDetent: Equatable {
    case center
    case minimum

    static let snapDistance: CGFloat = 8

    static func snappedLeadingWidth(_ width: CGFloat, contentWidth: CGFloat) -> CGFloat {
        abs(width - contentWidth / 2) <= snapDistance ? contentWidth / 2 : width
    }

    static func of(leadingWidth: CGFloat, contentWidth: CGFloat, minimum: CGFloat) -> SplitDividerDetent? {
        if leadingWidth == contentWidth / 2 { return .center }
        if leadingWidth <= minimum || leadingWidth >= contentWidth - minimum { return .minimum }
        return nil
    }
}

struct TabPlacement: Equatable {
    enum Kind: Equatable {
        case pinned
        case saved
        case regular
    }

    let kind: Kind
    let parentIdentifier: MiniTabId?

    @MainActor
    init(of tab: Tab) {
        kind = tab.isPinned ? .pinned : tab.isSaved ? .saved : .regular
        parentIdentifier = tab.parent?.id
    }
}

@MainActor
enum Haptics {
    private static var gate = HapticGate()

    static func sidebarSnappedCollapsed() { perform(.sidebarCollapseSnap) }
    static func sidebarReachedWidthLimit() { perform(.sidebarWidthLimit) }
    static func splitSnappedToCenter() { perform(.splitCenter) }
    static func splitReachedMinimum() { perform(.splitMinimum) }
    static func tabDragTargetChanged() { perform(.tabDragTarget) }
    static func peekSidebarOpened() { perform(.peekSidebarOpened) }
    static func tabDropChangedPlacement() { perform(.tabDropChangedPlacement) }
    static func swipeNavigationCrossedThreshold() { perform(.swipeNavigationThreshold) }
    static func spaceSwipeCrossedThreshold() { perform(.spaceSwipeThreshold) }
    static func tabTornOff() { perform(.tabTornOff) }
    static func littleWindowDocked() { perform(.littleWindowDocked) }

    private static func perform(_ moment: HapticMoment) {
        let duringMomentum = NSApp.currentEvent.map { $0.type == .scrollWheel && $0.momentumPhase != [] } ?? false
        let admitted = gate.admit(at: ProcessInfo.processInfo.systemUptime, duringMomentum: duringMomentum)
        guard admitted else { return }
        NSHapticFeedbackManager.defaultPerformer.perform(moment.pattern, performanceTime: moment.performanceTime)
    }
}
