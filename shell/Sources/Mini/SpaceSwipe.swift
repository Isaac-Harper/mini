import AppKit
import SwiftUI

@MainActor
@Observable
final class SpaceSwipeModel {
    var offset: CGFloat = 0
    var neighbor: Space?
    var neighborEdge: CGFloat = 1
    var width: CGFloat = 1

    var progress: CGFloat {
        neighbor == nil ? 0 : min(abs(offset) / max(width, 1), 1)
    }
}

struct SpaceSwipeTravel {
    static let axisLockDistance: CGFloat = 6
    static let commitFraction: CGFloat = 0.35
    static let commitVelocity: CGFloat = 600

    enum Axis {
        case horizontal
        case vertical
    }

    static func axis(horizontal: CGFloat, vertical: CGFloat) -> Axis? {
        guard hypot(horizontal, vertical) >= axisLockDistance else { return nil }
        return abs(horizontal) > abs(vertical) ? .horizontal : .vertical
    }

    static func neighborIndex(of current: Int, count: Int, travel: CGFloat) -> Int? {
        let index = travel < 0 ? current + 1 : current - 1
        return (0..<count).contains(index) ? index : nil
    }

    static func offset(travel: CGFloat, width: CGFloat, hasNeighbor: Bool) -> CGFloat {
        guard !hasNeighbor else { return min(max(travel, -width), width) }
        let distance = abs(travel)
        let banded = (1 - 1 / (distance * 0.55 / max(width, 1) + 1)) * width
        return travel < 0 ? -banded : banded
    }

    static func commits(offset: CGFloat, velocity: CGFloat, width: CGFloat) -> Bool {
        guard offset != 0 else { return false }
        if abs(offset) >= width * commitFraction { return true }
        return velocity * offset > 0 && abs(velocity) >= commitVelocity
    }
}

struct SpaceSwipeStage: View {
    let shell: ShellController

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let swipe = shell.spaceSwipe
        GeometryReader { geometry in
            let width = geometry.size.width
            ZStack(alignment: .topLeading) {
                SpaceTabsView(shell: shell, space: shell.currentSpace)
                    .id(shell.currentSpace.id)
                    .transition(.opacity)
                    .offset(x: reduceMotion ? 0 : swipe.offset)
                    .opacity(reduceMotion ? 1 - swipe.progress : 1)
                if let neighbor = swipe.neighbor {
                    SpaceTabsView(shell: shell, space: neighbor)
                        .offset(x: reduceMotion ? 0 : swipe.offset + swipe.neighborEdge * width)
                        .opacity(reduceMotion ? swipe.progress : 1)
                        .allowsHitTesting(false)
                }
            }
            .frame(width: width, height: geometry.size.height, alignment: .topLeading)
        }
        .clipped()
    }
}

@MainActor
final class SpaceSwipeController {
    private struct Gesture {
        var travel: CGFloat = 0
        var verticalTravel: CGFloat = 0
        var axis: SpaceSwipeTravel.Axis?
        var threshold = ThresholdCrossing()
        var samples: [(time: TimeInterval, delta: CGFloat)] = []

        var velocity: CGFloat {
            guard let last = samples.last else { return 0 }
            let recent = samples.filter { last.time - $0.time <= 0.1 }
            guard let first = recent.first, last.time > first.time else { return 0 }
            return recent.dropFirst().map(\.delta).reduce(0, +) / CGFloat(last.time - first.time)
        }
    }

    private unowned let shell: ShellController
    private let sidebarView: NSView
    private var monitor: Any?
    private var gesture: Gesture?
    private var swallowsMomentum = false
    private var isSettling = false

    init(shell: ShellController, sidebarView: NSView) {
        self.shell = shell
        self.sidebarView = sidebarView
        monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            let consumed = MainActor.assumeIsolated { self?.consumes(event) ?? false }
            return consumed ? nil : event
        }
    }

    private var model: SpaceSwipeModel { shell.spaceSwipe }

    private func consumes(_ event: NSEvent) -> Bool {
        guard event.hasPreciseScrollingDeltas else { return false }
        if event.momentumPhase != [] {
            let swallows = swallowsMomentum
            if event.momentumPhase.contains(.ended) || event.momentumPhase.contains(.cancelled) {
                swallowsMomentum = false
            }
            return swallows
        }
        if event.phase.contains(.began) {
            swallowsMomentum = false
            gesture = canStart(at: event) ? Gesture() : nil
            return false
        }
        guard var current = gesture else { return false }
        if event.phase.contains(.ended) || event.phase.contains(.cancelled) {
            gesture = nil
            guard current.axis == .horizontal else { return false }
            swallowsMomentum = true
            finish(current, cancelled: event.phase.contains(.cancelled))
            return true
        }
        guard event.phase.contains(.changed) else { return false }
        let fingersRight = event.isDirectionInvertedFromDevice ? event.scrollingDeltaX : -event.scrollingDeltaX
        current.travel += fingersRight
        current.verticalTravel += event.isDirectionInvertedFromDevice ? event.scrollingDeltaY : -event.scrollingDeltaY
        if current.axis == nil {
            current.axis = SpaceSwipeTravel.axis(horizontal: current.travel, vertical: current.verticalTravel)
            if current.axis == .horizontal {
                model.width = sidebarView.bounds.width
            }
        }
        gesture = current
        guard current.axis == .horizontal else { return false }
        current.samples.append((ProcessInfo.processInfo.systemUptime, fingersRight))
        if current.samples.count > 12 { current.samples.removeFirst() }
        track(current)
        let progress = model.neighbor == nil ? 0 : abs(model.offset) / max(model.width * SpaceSwipeTravel.commitFraction, 1)
        if current.threshold.update(progress: progress) {
            Haptics.spaceSwipeCrossedThreshold()
        }
        gesture = current
        return true
    }

    private func canStart(at event: NSEvent) -> Bool {
        guard NSEvent.isSwipeTrackingFromScrollEventsEnabled, !isSettling, shell.spaces.count > 1,
              shell.window.attachedSheet == nil, shell.windowController.isSidebarVisible,
              let location = locationInWindow(of: event), sidebarView.window != nil, !sidebarView.isHiddenOrHasHiddenAncestor else { return false }
        return sidebarView.bounds.contains(sidebarView.convert(location, from: nil))
    }

    private func locationInWindow(of event: NSEvent) -> NSPoint? {
        return event.window === shell.window ? event.locationInWindow : nil
    }

    private func track(_ gesture: Gesture) {
        guard let currentIndex = shell.spaces.firstIndex(where: { $0 === shell.currentSpace }) else {
            preconditionFailure("Current space missing from the space list")
        }
        let neighborIndex = SpaceSwipeTravel.neighborIndex(of: currentIndex, count: shell.spaces.count, travel: gesture.travel)
        let neighbor = neighborIndex.map { shell.spaces[$0] }
        if model.neighbor !== neighbor {
            model.neighbor = neighbor
        }
        if let neighborIndex {
            model.neighborEdge = neighborIndex > currentIndex ? 1 : -1
        }
        model.offset = SpaceSwipeTravel.offset(travel: gesture.travel, width: model.width, hasNeighbor: neighbor != nil)
    }

    private func finish(_ gesture: Gesture, cancelled: Bool) {
        let commits = !cancelled && model.neighbor != nil
            && SpaceSwipeTravel.commits(offset: model.offset, velocity: gesture.velocity, width: model.width)
        isSettling = true
        if commits, let neighbor = model.neighbor {
            withAnimation(.spring(duration: 0.25, bounce: 0)) {
                model.offset = -model.neighborEdge * model.width
            } completion: { [weak self] in
                guard let self else { return }
                var transaction = Transaction()
                transaction.disablesAnimations = true
                withTransaction(transaction) {
                    self.shell.switchToSpace(neighbor)
                    self.model.offset = 0
                    self.model.neighbor = nil
                }
                self.isSettling = false
            }
        } else {
            withAnimation(.spring(duration: 0.3, bounce: 0.15)) {
                model.offset = 0
            } completion: { [weak self] in
                guard let self else { return }
                self.model.neighbor = nil
                self.isSettling = false
            }
        }
    }
}
