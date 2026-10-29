import CMiniCore
import MiniRules
import SwiftUI

enum RegularSidebarItem: Identifiable {
    case tab(VisibleTab)
    case dayFold(DayFoldGroup)

    enum Identifier: Hashable {
        case tab(MiniTabId)
        case dayFold(Date)
    }

    var id: Identifier {
        switch self {
        case .tab(let visibleTab): .tab(visibleTab.id)
        case .dayFold(let group): .dayFold(group.day)
        }
    }

    static func items(regularRows rows: [VisibleTab], groups: [DayFoldGroup]) -> [RegularSidebarItem] {
        rows.filter { $0.foldDay == nil }.map(RegularSidebarItem.tab)
            + groups.flatMap { group in [.dayFold(group)] + rows.filter { $0.foldDay == group.day }.map(RegularSidebarItem.tab) }
    }
}

struct DayFoldRow: View {
    let shell: ShellController
    let group: DayFoldGroup

    @Environment(\.sidebarStore) private var sidebarStore

    private var store: TabStore { sidebarStore ?? shell.store }

    var body: some View {
        HStack(spacing: SidebarMetrics.accessorySpacing) {
            Image(systemName: "chevron.right")
                .font(InterfaceFont.accessorySymbol)
                .foregroundStyle(.tertiary)
                .rotationEffect(.degrees(group.isExpanded ? 90 : 0))
                .animation(.easeOut(duration: 0.15), value: group.isExpanded)
                .frame(width: SidebarMetrics.disclosureSize, height: SidebarMetrics.disclosureSize)
            Image(systemName: "moon.zzz")
                .font(InterfaceFont.rowSymbol)
                .foregroundStyle(.secondary)
                .frame(width: SidebarMetrics.iconSize, height: SidebarMetrics.iconSize)
                .padding(.trailing, SidebarMetrics.iconSpacing - SidebarMetrics.accessorySpacing)
            Text(DayClosing.groupTitle(label: shell.foldLabel(for: group.day), tabCount: group.tabCount))
                .fadingTruncation()
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
            accessory("arrow.uturn.backward", help: "Restore Tabs") { shell.restoreFold(group) }
            accessory("xmark", help: "Archive Tabs") { shell.archiveFold(group) }
        }
        .padding(.leading, SidebarMetrics.indent(depth: 0))
        .padding(.trailing, SidebarMetrics.rowTrailingPadding)
        .frame(height: SidebarMetrics.rowHeight)
        .hoverHighlight()
        .contentShape(Rectangle())
        .onTapGesture {
            Haptics.controlActivated(.press)
            store.setFold(day: group.day, expanded: !group.isExpanded)
        }
        .contextMenu {
            Button(group.isExpanded ? "Collapse" : "Expand", systemImage: group.isExpanded ? "chevron.down" : "chevron.right") { store.setFold(day: group.day, expanded: !group.isExpanded) }
            Button("Restore Tabs", systemImage: "arrow.uturn.backward") { shell.restoreFold(group) }
            Divider()
            Button("Archive Tabs") { shell.archiveFold(group) }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(DayClosing.groupTitle(label: shell.foldLabel(for: group.day), tabCount: group.tabCount))
    }

    private func accessory(_ systemImage: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(InterfaceFont.accessorySymbol)
                .foregroundStyle(.secondary)
                .frame(width: SidebarMetrics.accessorySize, height: SidebarMetrics.accessorySize)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focusable(false)
        .hapticFeedback(.press)
        .help(help)
    }
}
