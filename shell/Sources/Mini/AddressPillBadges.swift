import MiniRules
import SwiftUI

struct AddressPillChip: View {
    let text: String?
    let symbol: String?
    let help: String

    init(text: String?, symbol: String? = nil, help: String) {
        self.text = text
        self.symbol = symbol
        self.help = help
    }

    var body: some View {
        HStack(spacing: SidebarMetrics.accessorySpacing) {
            if let text {
                Text(text)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: SidebarMetrics.addressPillChipMaximumTextWidth)
            }
            if let symbol {
                Image(systemName: symbol)
                    .font(InterfaceFont.accessorySymbol)
            }
        }
        .font(InterfaceFont.caption)
        .foregroundStyle(.secondary)
        .fixedSize()
        .padding(.horizontal, SidebarMetrics.addressPillChipPadding)
        .frame(height: SidebarMetrics.addressPillChipHeight)
        .background(Capsule().fill(.fill.tertiary))
        .glassTooltip(help)
    }
}

struct EnvironmentChip: View {
    let shell: ShellController
    let tab: Tab
    let text: String
    let description: String

    @State private var anchor = PillAnchor()

    var body: some View {
        Button {
            guard let view = anchor.view else { return }
            shell.showEnvironmentMenu(for: tab, under: view)
        } label: {
            AddressPillChip(text: text, help: "Switch environment")
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .focusable(false)
        .hoverHighlight(cornerRadius: SidebarMetrics.addressPillChipHeight / 2)
        .hapticFeedback(.press)
        .background { PillAnchorRepresentable(anchor: anchor) }
        .accessibilityLabel(description)
    }
}

struct AddressPillBadges: View {
    let shell: ShellController
    let tab: Tab

    var body: some View {
        HStack(spacing: SidebarMetrics.accessorySpacing) {
            if let chip = tab.pageAppearanceChip {
                Button { shell.resetPageAppearance(of: tab) } label: {
                    AddressPillChip(text: chip.text, symbol: chip.showsMotionSymbol ? "figure.walk.motion" : nil, help: chip.help)
                }
                .buttonStyle(.plain)
                .focusable(false)
                .hapticFeedback(.press)
                .accessibilityLabel(chip.help)
            }
            if let port = LocalDevelopment.port(ofLocalAddress: tab.url) {
                EnvironmentChip(shell: shell, tab: tab, text: "dev :\(String(port))", description: "Local development server on port \(String(port))")
            } else if let host = URLInput.host(of: tab.url), let preview = PreviewDeployment.of(host: host) {
                EnvironmentChip(shell: shell, tab: tab, text: preview.branch.map { "Preview \u{00B7} \($0)" } ?? "Preview",
                                description: preview.branch.map { "Preview deployment of \(preview.project), branch \($0)" } ?? "Preview deployment of \(preview.project)")
            }
            if let tooltip = PageHealth.warningTooltip(health: tab.health, slowVitals: tab.vitals.needsWarning) {
                VitalsWarningDot(tooltip: tooltip)
            }
        }
    }
}
