import MiniRules
import SwiftUI

struct HarvestSlotView: View {
    let shell: ShellController
    let tab: Tab

    @Environment(\.sidebarStore) private var sidebarStore
    @Environment(\.selectionNamespace) private var namespace

    private var store: TabStore { sidebarStore ?? shell.store }

    private var isSelected: Bool { store.selectedTab === tab }

    private var presentation: HarvestSlot.Presentation { HarvestSlot.presentation(url: tab.url, timesheet: tab.harvestTimesheet, shownSeconds: tab.harvestShownSeconds) }

    var body: some View {
        HStack(spacing: SidebarMetrics.iconSpacing) {
            TabIconView(tab: tab, size: SidebarMetrics.iconSize)
            content
        }
        .modifier(SlotRowChrome(isSelected: isSelected, namespace: namespace))
        .overlay { SidebarFocusRing(shell: shell, tab: tab, cornerRadius: SidebarMetrics.rowCornerRadius) }
        .onTapGesture {
            Haptics.controlActivated(.press)
            shell.clearRowSelection()
            shell.store.select(tab)
        }
        .contextMenu {
            Button("Remove Harvest Tab", systemImage: "rectangle.slash") { shell.removeHarvest() }
        }
        .transition(.opacity)
    }

    @ViewBuilder
    private var content: some View {
        switch presentation {
        case .idle:
            Text("Harvest")
                .lineLimit(1)
                .foregroundStyle(.primary)
            Spacer(minLength: 0)
        case .signedOut:
            Text("Sign in to Harvest")
                .lineLimit(1)
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
        case .running(let timer, let todaySeconds):
            entryText(timer.entry)
            Spacer(minLength: 0)
            TimelineView(.periodic(from: .now, by: 1)) { context in
                Text(HarvestSlot.clock(timer.elapsedSeconds(at: context.date)))
                    .monospacedDigit()
                    .foregroundStyle(.primary)
            }
            .glassTooltip("Today \(HarvestSlot.duration(todaySeconds))")
            timerButton("stop.fill", help: "Stop Timer") { shell.setHarvestTimer(of: timer.entry, running: false) }
        case .stopped(let last, let lastSeconds, let todaySeconds):
            if let last {
                entryText(last)
                Spacer(minLength: 0)
                Text(HarvestSlot.clock(lastSeconds))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .glassTooltip("Today \(HarvestSlot.duration(todaySeconds))")
                timerButton("play.fill", help: "Resume Timer") { shell.setHarvestTimer(of: last, running: true) }
            } else {
                Text("Harvest")
                    .lineLimit(1)
                    .foregroundStyle(.primary)
                Spacer(minLength: 0)
            }
        }
    }

    private func entryText(_ entry: HarvestEntry) -> some View {
        let tooltip = [entry.title, entry.detail, entry.notes == entry.detail ? "" : entry.notes].filter { !$0.isEmpty }.joined(separator: "\n")
        let detail = Text(entry.detail.isEmpty ? "" : "  \(entry.detail)").foregroundStyle(.secondary)
        return Text("\(Text(entry.title).foregroundStyle(.primary))\(detail)")
            .fadingTruncation(tooltip: tooltip)
    }

    private func timerButton(_ symbol: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(InterfaceFont.accessorySymbol)
                .foregroundStyle(.secondary)
                .frame(width: SidebarMetrics.accessorySize, height: SidebarMetrics.accessorySize)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focusable(false)
        .hapticFeedback(.toggle)
        .glassTooltip(help)
    }
}
