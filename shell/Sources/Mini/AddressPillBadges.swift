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
            .padding(.horizontal, SidebarMetrics.addressPillChipPadding)
            .frame(height: SidebarMetrics.addressPillChipHeight)
            .frame(maxWidth: SidebarMetrics.addressPillChipMaximumWidth)
            .background(Capsule().fill(.fill.tertiary))
            .layoutPriority(1)
            .help(help)
    }
}

struct AddressPillBadges: View {
    let tab: Tab

    var body: some View {
        if let host = URLInput.host(of: tab.url), let preview = PreviewDeployment.of(host: host) {
            AddressPillChip(text: preview.branch.map { "Preview \u{00B7} \($0)" } ?? "Preview",
                            help: preview.branch.map { "Preview deployment of \(preview.project), branch \($0)" } ?? "Preview deployment of \(preview.project)")
        }
    }
}
