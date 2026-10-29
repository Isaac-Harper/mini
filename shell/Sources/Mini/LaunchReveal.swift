import AppKit
import Observation
import SwiftUI

@MainActor
@Observable
final class LaunchReveal {
    enum Phase {
        case waiting
        case revealing
        case done
    }

    private(set) var phase: Phase = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? .done : .waiting

    static let rise: CGFloat = 4
    static let stagger: TimeInterval = 0.02
    static let staggeredRows = 12
    static let rowDuration: TimeInterval = 0.3
    static let cardDuration: TimeInterval = 0.35

    func play(revealingCard reveal: (TimeInterval) -> Void) {
        guard phase == .waiting else { return }
        phase = .revealing
        reveal(Self.cardDuration)
        let total = Self.rowDuration + Self.stagger * Double(Self.staggeredRows)
        DispatchQueue.main.asyncAfter(deadline: .now() + total) { [weak self] in
            MainActor.assumeIsolated { self?.phase = .done }
        }
    }

    static func delay(forRow index: Int) -> TimeInterval {
        stagger * Double(min(index, staggeredRows))
    }
}

private struct LaunchRevealRow: ViewModifier {
    let reveal: LaunchReveal
    let index: Int

    func body(content: Content) -> some View {
        let isHidden = reveal.phase == .waiting
        content
            .opacity(isHidden ? 0 : 1)
            .offset(y: isHidden ? LaunchReveal.rise : 0)
            .animation(reveal.phase == .revealing ? .easeOut(duration: LaunchReveal.rowDuration).delay(LaunchReveal.delay(forRow: index)) : nil,
                       value: isHidden)
    }
}

extension View {
    func launchReveal(_ reveal: LaunchReveal, index: Int) -> some View {
        modifier(LaunchRevealRow(reveal: reveal, index: index))
    }
}
