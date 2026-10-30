import AppKit
import CMiniCore
import MiniRules
import SwiftUI

@MainActor
final class VitalsPopoverPresenter {
    private var popover: NSPopover?
    private var isOverPill = false
    private var isOverPopover = false
    private var generation = 0

    private static let openDelay: TimeInterval = 0.5
    private static let closeGrace: TimeInterval = 0.15

    func pillHoverChanged(_ inside: Bool, anchor: NSView, tab: Tab) {
        isOverPill = inside
        generation += 1
        let current = generation
        guard inside else {
            scheduleCloseCheck()
            return
        }
        guard popover == nil, tab.hasBrowser, tab.url.hasPrefix("http") else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.openDelay) { [weak self, weak anchor, weak tab] in
            MainActor.assumeIsolated {
                guard let self, let anchor, let tab, self.generation == current, self.isOverPill, self.popover == nil, anchor.window != nil else { return }
                self.show(tab, from: anchor)
            }
        }
    }

    func close() {
        generation += 1
        popover?.performClose(nil)
        popover = nil
        isOverPopover = false
    }

    private func show(_ tab: Tab, from anchor: NSView) {
        let popover = NSPopover()
        popover.behavior = .applicationDefined
        popover.animates = !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        popover.contentViewController = NSHostingController(rootView: VitalsPeekView(tab: tab, onHover: { [weak self] inside in
            self?.popoverHoverChanged(inside)
        }, onOpenDeveloperTools: { [weak self, weak tab] in
            guard let tab, tab.hasBrowser else { return }
            mini_browser_show_dev_tools(tab.id)
            self?.close()
        }))
        popover.show(relativeTo: anchor.bounds, of: anchor, preferredEdge: .maxX)
        self.popover = popover
    }

    private func popoverHoverChanged(_ inside: Bool) {
        isOverPopover = inside
        generation += 1
        if !inside { scheduleCloseCheck() }
    }

    private func scheduleCloseCheck() {
        let current = generation
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.closeGrace) { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.generation == current, !self.isOverPill, !self.isOverPopover else { return }
                self.close()
            }
        }
    }
}

struct VitalsPeekView: View {
    let tab: Tab
    let onHover: (Bool) -> Void
    let onOpenDeveloperTools: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 6) {
                GridRow {
                    VitalsValue(metric: .largestContentfulPaint, value: tab.vitals.largestContentfulPaint)
                    VitalsValue(metric: .interactionToNextPaint, value: tab.vitals.interactionToNextPaint)
                }
                GridRow {
                    VitalsValue(metric: .cumulativeLayoutShift, value: tab.vitals.cumulativeLayoutShift)
                    VitalsValue(metric: .timeToFirstByte, value: tab.vitals.timeToFirstByte)
                }
            }
            if let edge = tab.edge {
                Text(edge.text)
                    .font(InterfaceFont.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .padding(.horizontal, SidebarMetrics.addressPillChipPadding)
                    .frame(height: SidebarMetrics.addressPillChipHeight + 4)
                    .background(Capsule().fill(.fill.tertiary))
                    .accessibilityLabel("Served by \(edge.text)")
            }
            if let errorLine = tab.health.errorLine {
                PageHealthLine(text: errorLine, truncation: .tail, action: onOpenDeveloperTools)
            }
            if let failedRequestLine = tab.health.failedRequestLine(onPage: tab.url) {
                PageHealthLine(text: failedRequestLine, truncation: .middle, action: onOpenDeveloperTools)
            }
        }
        .padding(12)
        .background(Color(nsColor: .windowBackgroundColor).opacity(0.75))
        .onHover(perform: onHover)
    }
}

private struct PageHealthLine: View {
    let text: String
    let truncation: Text.TruncationMode
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Circle()
                    .fill(Color.orange.opacity(0.7))
                    .frame(width: 5, height: 5)
                Text(text)
                    .font(InterfaceFont.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(truncation)
            }
            .frame(maxWidth: 280, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focusable(false)
        .hapticFeedback(.press)
        .glassTooltip("Open Developer Tools")
        .accessibilityHint("Opens Developer Tools")
    }
}

private struct VitalsValue: View {
    let metric: WebVitalsMetric
    let value: Double?

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(color)
                .frame(width: 7, height: 7)
            Text(metric.rawValue)
                .font(InterfaceFont.caption)
                .foregroundStyle(.secondary)
                .frame(width: 32, alignment: .leading)
            Text(WebVitals.formatted(metric, value: value))
                .font(InterfaceFont.body.monospacedDigit())
                .frame(minWidth: 48, alignment: .trailing)
        }
        .accessibilityElement(children: .combine)
    }

    private var color: Color {
        guard let value else { return Color(nsColor: .quaternaryLabelColor) }
        switch WebVitals.rating(of: metric, value: value) {
        case .good: return .green
        case .needsImprovement: return .orange
        case .poor: return .red
        }
    }
}

struct VitalsWarningDot: View {
    let tooltip: String

    var body: some View {
        Circle()
            .fill(Color.orange.opacity(0.7))
            .frame(width: 5, height: 5)
            .glassTooltip(tooltip)
    }
}

@MainActor
final class PillAnchor {
    weak var view: NSView?
}

struct PillAnchorRepresentable: NSViewRepresentable {
    let anchor: PillAnchor

    func makeNSView(context: Context) -> PillAnchorView {
        let view = PillAnchorView()
        anchor.view = view
        return view
    }

    func updateNSView(_ nsView: PillAnchorView, context: Context) {
        anchor.view = nsView
    }
}

final class PillAnchorView: NSView {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}
