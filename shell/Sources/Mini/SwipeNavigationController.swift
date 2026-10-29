import AppKit
import CMiniCore

struct HorizontalScrollRoom: Equatable {
    var canScrollLeft = false
    var canScrollRight = false
}

@MainActor
final class SwipeNavigationController {
    enum Direction {
        case back
        case forward
    }

    private struct Gesture {
        let tab: Tab
        var travel: CGFloat = 0
        var verticalTravel: CGFloat = 0
        var direction: Direction?
        var isRejected = false
        var threshold = ThresholdCrossing()

        var progress: CGFloat {
            switch direction {
            case .back: max(travel, 0) / SwipeNavigationController.commitDistance
            case .forward: max(-travel, 0) / SwipeNavigationController.commitDistance
            case nil: 0
            }
        }
    }

    private unowned let shell: ShellController
    private let webAreaView: WebAreaView
    private let indicator = SwipeIndicatorView()
    private var indicatorCenterX: NSLayoutConstraint?
    private var monitor: Any?
    private var gesture: Gesture?
    private var swallowsMomentum = false

    private static let decisionDistance: CGFloat = 12
    private nonisolated static let commitDistance: CGFloat = 140
    private static let indicatorSize: CGFloat = 44
    private static let indicatorTravel: CGFloat = 72

    init(shell: ShellController, windowController: MainWindowController) {
        self.shell = shell
        webAreaView = windowController.webAreaView
        indicator.translatesAutoresizingMaskIntoConstraints = false
        indicator.isHidden = true
        windowController.rootView.addSubview(indicator)
        NSLayoutConstraint.activate([
            indicator.widthAnchor.constraint(equalToConstant: Self.indicatorSize),
            indicator.heightAnchor.constraint(equalToConstant: Self.indicatorSize),
            indicator.centerYAnchor.constraint(equalTo: webAreaView.centerYAnchor),
        ])
        monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            let consumed = MainActor.assumeIsolated { self?.consumes(event) ?? false }
            return consumed ? nil : event
        }
    }

    private func consumes(_ event: NSEvent) -> Bool {
        guard locationInWindow(of: event) != nil, event.hasPreciseScrollingDeltas else { return false }
        if event.momentumPhase != [] {
            let swallows = swallowsMomentum
            if event.momentumPhase.contains(.ended) || event.momentumPhase.contains(.cancelled) {
                swallowsMomentum = false
            }
            return swallows
        }
        if event.phase.contains(.began) {
            swallowsMomentum = false
            gesture = swipeTab(under: event).map { Gesture(tab: $0) }
            return false
        }
        guard var current = gesture else { return false }
        if event.phase.contains(.ended) || event.phase.contains(.cancelled) {
            gesture = nil
            guard let direction = current.direction else { return false }
            let commits = event.phase.contains(.ended) && current.progress >= 1
            hideIndicator()
            swallowsMomentum = true
            if commits, current.tab.hasBrowser {
                switch direction {
                case .back: mini_browser_go_back(current.tab.id)
                case .forward: mini_browser_go_forward(current.tab.id)
                }
            }
            return true
        }
        guard event.phase.contains(.changed), !current.isRejected else { return false }
        let fingersRight = event.isDirectionInvertedFromDevice ? event.scrollingDeltaX : -event.scrollingDeltaX
        current.travel += fingersRight
        current.verticalTravel += abs(event.scrollingDeltaY)
        if current.direction == nil {
            if abs(current.travel) < Self.decisionDistance {
                gesture = current
                return false
            }
            let direction: Direction = current.travel > 0 ? .back : .forward
            let room = current.tab.horizontalScrollRoom
            let allowed = switch direction {
            case .back: current.tab.canGoBack && !room.canScrollLeft
            case .forward: current.tab.canGoForward && !room.canScrollRight
            }
            guard abs(current.travel) > current.verticalTravel * 2, allowed else {
                current.isRejected = true
                gesture = current
                return false
            }
            current.direction = direction
            current.travel = direction == .back ? 0.01 : -0.01
            showIndicator(direction)
        }
        if current.threshold.update(progress: current.progress) {
            Haptics.swipeNavigationCrossedThreshold()
        }
        gesture = current
        updateIndicator(current)
        return true
    }

    private func swipeTab(under event: NSEvent) -> Tab? {
        guard NSEvent.isSwipeTrackingFromScrollEventsEnabled, shell.window.attachedSheet == nil,
              let tab = shell.store.selectedTab, tab.hasBrowser else { return nil }
        guard let location = locationInWindow(of: event) else { return nil }
        let point = tab.hostView.convert(location, from: nil)
        guard tab.hostView.window != nil, !tab.hostView.isHiddenOrHasHiddenAncestor, tab.hostView.bounds.contains(point) else { return nil }
        return tab
    }

    private func locationInWindow(of event: NSEvent) -> NSPoint? {
        return event.window === shell.window ? event.locationInWindow : nil
    }

    private func showIndicator(_ direction: Direction) {
        indicatorCenterX?.isActive = false
        indicatorCenterX = direction == .back
            ? indicator.centerXAnchor.constraint(equalTo: webAreaView.leadingAnchor)
            : indicator.centerXAnchor.constraint(equalTo: webAreaView.trailingAnchor)
        indicatorCenterX?.isActive = true
        indicator.direction = direction
        indicator.alphaValue = 1
        indicator.isHidden = false
    }

    private func updateIndicator(_ gesture: Gesture) {
        guard let direction = gesture.direction else { return }
        let progress = gesture.progress
        let offset = -Self.indicatorSize / 2 + Self.indicatorTravel * min(progress, 1)
        indicatorCenterX?.constant = direction == .back ? offset : -offset
        indicator.isArmed = progress >= 1
        indicator.alphaValue = 0.4 + 0.6 * min(progress, 1)
    }

    private func hideIndicator() {
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.15
            indicator.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.gesture?.direction == nil else { return }
                self.indicator.isHidden = true
            }
        })
    }
}

final class SwipeIndicatorView: NSView {
    private let glassView = NSGlassEffectView()
    private let imageView = NSImageView()

    var direction: SwipeNavigationController.Direction = .back {
        didSet {
            let name = direction == .back ? "arrow.left" : "arrow.right"
            imageView.image = NSImage(systemSymbolName: name, accessibilityDescription: direction == .back ? "Back" : "Forward")
        }
    }

    var isArmed = false {
        didSet {
            guard isArmed != oldValue else { return }
            glassView.tintColor = isArmed ? .controlAccentColor : nil
            imageView.contentTintColor = isArmed ? .white : .labelColor
        }
    }

    override init(frame: NSRect) {
        super.init(frame: frame)
        imageView.symbolConfiguration = .init(pointSize: 18, weight: .semibold)
        imageView.contentTintColor = .labelColor
        imageView.translatesAutoresizingMaskIntoConstraints = false
        let content = NSView()
        content.addSubview(imageView)
        glassView.contentView = content
        glassView.cornerRadius = 22
        glassView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(glassView)
        NSLayoutConstraint.activate([
            glassView.leadingAnchor.constraint(equalTo: leadingAnchor),
            glassView.trailingAnchor.constraint(equalTo: trailingAnchor),
            glassView.topAnchor.constraint(equalTo: topAnchor),
            glassView.bottomAnchor.constraint(equalTo: bottomAnchor),
            imageView.centerXAnchor.constraint(equalTo: content.centerXAnchor),
            imageView.centerYAnchor.constraint(equalTo: content.centerYAnchor),
        ])
        direction = .back
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}
