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
        VStack(alignment: .leading, spacing: InterfaceScale.scaled(8)) {
            VStack(alignment: .leading, spacing: InterfaceScale.scaled(2)) {
                Text(host)
                    .font(InterfaceFont.body.weight(.semibold))
                    .lineLimit(1)
                    .truncationMode(.middle)
                if !attributes.isEmpty {
                    Text(attributes.joined(separator: " \u{00B7} "))
                        .font(InterfaceFont.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Divider()
            HStack(alignment: .top, spacing: 0) {
                ForEach(WebVitalsMetric.allCases, id: \.self) { metric in
                    VitalsValue(metric: metric, value: tab.vitals.value(of: metric))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            if PageHealth.isCollected(for: tab.url) {
                Divider()
                VStack(alignment: .leading, spacing: 0) {
                    if let title = tab.health.errorTitle {
                        PageHealthRow(title: title, detail: tab.health.errorDetail, detailTruncation: .tail, action: onOpenDeveloperTools)
                    }
                    if let title = tab.health.failedRequestTitle {
                        PageHealthRow(title: title, detail: tab.health.failedRequestDetail(onPage: tab.url), detailTruncation: .middle, action: onOpenDeveloperTools)
                    }
                    if !tab.health.hasProblems {
                        HStack(spacing: InterfaceScale.scaled(8)) {
                            PageStatusDot(color: .green)
                            Text("No errors or failed requests")
                                .font(InterfaceFont.caption)
                                .foregroundStyle(.secondary)
                        }
                        .frame(height: InterfaceScale.scaled(24))
                    }
                }
            }
        }
        .padding(InterfaceScale.scaled(12))
        .frame(width: InterfaceScale.scaled(272), alignment: .leading)
        .background(Color(nsColor: .windowBackgroundColor).opacity(0.75))
        .onHover(perform: onHover)
    }

    private var host: String {
        guard let components = URLComponents(string: tab.url), let host = components.host else { return tab.url }
        return components.port.map { "\(host):\(String($0))" } ?? host
    }

    private var attributes: [String] {
        var parts: [String] = []
        if let port = LocalDevelopment.port(ofLocalAddress: tab.url) {
            parts.append("Local server on port \(String(port))")
        } else if let host = URLInput.host(of: tab.url), let preview = PreviewDeployment.of(host: host) {
            parts.append(preview.branch.map { "Preview of \(preview.project), \($0)" } ?? "Preview of \(preview.project)")
        }
        if let edge = tab.edge {
            parts.append(edge.text)
        }
        if tab.pageColorScheme != .system {
            parts.append("Shown \(tab.pageColorScheme.name.lowercased())")
        }
        if tab.pageReducesMotion {
            parts.append("Reduced motion")
        }
        if let width = tab.pageWidth {
            parts.append("\(String(Int(width.rounded()))) wide")
        }
        return parts
    }
}

private struct PageStatusDot: View {
    let color: Color

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: InterfaceScale.scaled(6), height: InterfaceScale.scaled(6))
    }
}

private struct PageHealthRow: View {
    let title: String
    let detail: String?
    let detailTruncation: Text.TruncationMode
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: InterfaceScale.scaled(8)) {
                PageStatusDot(color: .orange)
                    .frame(height: InterfaceScale.scaled(16))
                VStack(alignment: .leading, spacing: InterfaceScale.scaled(2)) {
                    Text(title)
                        .font(InterfaceFont.body)
                    if let detail {
                        Text(detail)
                            .font(InterfaceFont.caption.monospaced())
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(detailTruncation)
                    }
                }
                Spacer(minLength: 0)
                Image(systemName: "arrow.up.forward")
                    .font(InterfaceFont.accessorySymbol)
                    .foregroundStyle(.tertiary)
                    .frame(height: InterfaceScale.scaled(16))
                    .opacity(isHovered ? 1 : 0)
            }
            .padding(.vertical, InterfaceScale.scaled(4))
            .padding(.horizontal, InterfaceScale.scaled(4))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focusable(false)
        .padding(.horizontal, InterfaceScale.scaled(-4))
        .hoverHighlight(cornerRadius: SidebarMetrics.rowCornerRadius, isHovered: $isHovered)
        .hapticFeedback(.press)
        .glassTooltip("Open Developer Tools")
        .accessibilityHint("Opens Developer Tools")
    }
}

private struct VitalsValue: View {
    let metric: WebVitalsMetric
    let value: Double?

    var body: some View {
        VStack(alignment: .leading, spacing: InterfaceScale.scaled(2)) {
            HStack(spacing: InterfaceScale.scaled(4)) {
                PageStatusDot(color: color)
                Text(metric.rawValue)
                    .font(InterfaceFont.caption)
                    .foregroundStyle(.secondary)
            }
            Text(WebVitals.formatted(metric, value: value))
                .font(InterfaceFont.body.monospacedDigit())
                .foregroundStyle(value == nil ? .tertiary : .primary)
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
