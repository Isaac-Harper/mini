import Observation
import SwiftUI

@MainActor
@Observable
final class UndoToastModel {
    private(set) var message: String?
    @ObservationIgnored private var generation = 0

    static let visibleDuration: TimeInterval = 3

    func show(_ message: String) {
        generation += 1
        let shown = generation
        self.message = message
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.visibleDuration) { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.generation == shown else { return }
                self.message = nil
            }
        }
    }

    func hide() {
        generation += 1
        message = nil
    }

    static func message(forAction actionName: String, closedCount: Int) -> String? {
        guard closedCount > 0 else { return nil }
        switch actionName {
        case "Close Tab", "Close Tabs", "Delete Tab":
            return closedCount == 1 ? "Tab closed" : "\(closedCount) tabs closed"
        case "Archive Tab", "Archive Tabs":
            return closedCount == 1 ? "Tab archived" : "\(closedCount) tabs archived"
        default:
            return nil
        }
    }
}

struct UndoToastView: View {
    let shell: ShellController

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            if let message = shell.undoToast.message {
                HStack(spacing: SidebarMetrics.iconSpacing) {
                    Text(message)
                        .foregroundStyle(.primary)
                        .minimumScaleFactor(0.85)
                    Text("\u{00B7}")
                        .foregroundStyle(.tertiary)
                    Button("Undo") {
                        shell.undoToast.hide()
                        shell.tabUndoManager.undo()
                    }
                    .buttonStyle(.plain)
                    .focusable(false)
                    .foregroundStyle(.tint)
                    .fontWeight(.medium)
                    .hapticFeedback(.press)
                }
                .lineLimit(1)
                .padding(.horizontal, SidebarMetrics.addressPillTextInset)
                .frame(height: SidebarMetrics.addressPillHeight)
                .glassEffect(.regular, in: Capsule())
                .transition(reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.96, anchor: .bottom)))
            }
        }
        .animation(.easeOut(duration: 0.2), value: shell.undoToast.message)
    }
}
