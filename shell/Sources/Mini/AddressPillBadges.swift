import MiniRules
import SwiftUI

struct AddressPillChip: View {
    let text: String
    let help: String

    var body: some View {
        Text(text)
            .font(InterfaceFont.caption)
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .truncationMode(.tail)
            .frame(maxWidth: SidebarMetrics.addressPillChipMaximumTextWidth)
            .fixedSize()
            .padding(.horizontal, SidebarMetrics.addressPillChipPadding)
            .frame(height: SidebarMetrics.addressPillChipHeight)
            .background(Capsule().fill(.fill.tertiary))
            .glassTooltip(help)
    }
}

struct AddressPillBadges: View {
    let tab: Tab
    let resetAppearance: () -> Void

    var body: some View {
        HStack(spacing: SidebarMetrics.accessorySpacing) {
            if let chip = tab.pageAppearanceChip {
                Button(action: resetAppearance) {
                    AddressPillChip(text: chip.text, help: chip.help)
                }
                .buttonStyle(.plain)
                .focusable(false)
                .hapticFeedback(.press)
                .accessibilityLabel("\(chip.text), reset page appearance")
            }
            if let port = LocalDevelopment.port(ofLocalAddress: tab.url) {
                AddressPillChip(text: "dev :\(String(port))", help: "Local development server on port \(String(port))")
            } else if let host = URLInput.host(of: tab.url), let preview = PreviewDeployment.of(host: host) {
                AddressPillChip(text: preview.branch.map { "Preview \u{00B7} \($0)" } ?? "Preview",
                                help: preview.branch.map { "Preview deployment of \(preview.project), branch \($0)" } ?? "Preview deployment of \(preview.project)")
            }
            if tab.vitals.needsWarning {
                VitalsWarningDot()
            }
        }
    }
}
