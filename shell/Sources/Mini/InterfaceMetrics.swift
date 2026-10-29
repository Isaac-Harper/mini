import SwiftUI

enum SidebarMetrics {
    static let rowHeight: CGFloat = 28
    static let rowCornerRadius: CGFloat = 8
    static let edgeInset: CGFloat = 8
    static let indentation: CGFloat = 16
    static let rowLeadingPadding: CGFloat = 4
    static let rowTrailingPadding: CGFloat = 8
    static let footerRowPadding: CGFloat = 8
    static let disclosureSize: CGFloat = 12
    static let iconSize: CGFloat = 16
    static let iconSpacing: CGFloat = 8
    static let accessorySize: CGFloat = 16
    static let accessorySpacing: CGFloat = 4
    static let titleFadeWidth: CGFloat = 16
    static let topPadding: CGFloat = 4
    static let sectionSpacing: CGFloat = 12
    static let addressPillHeight: CGFloat = 32
    static let addressPillTextInset: CGFloat = 12
    static let addressPillButtonWidth: CGFloat = 32
    static let addressPillChipHeight: CGFloat = 16
    static let addressPillChipPadding: CGFloat = 6
    static let addressPillChipMaximumWidth: CGFloat = 104
    static let pinnedTileHeight: CGFloat = 40
    static let pinnedTileSpacing: CGFloat = 8
    static let pinnedTileCornerRadius: CGFloat = 12
    static let pinnedTileMinimumWidth: CGFloat = 44
    static let artworkSize: CGFloat = 20
    static let rowBadgeHeight: CGFloat = 12
    static let tileBadgeHeight: CGFloat = 16
    static let badgeRingWidth: CGFloat = 1.5
    static let sectionHeaderHeight: CGFloat = 20
    static let sectionDividerHeight: CGFloat = 12
    static let downloadVerticalPadding: CGFloat = 4
    static let spaceButtonSize = CGSize(width: 28, height: 24)
    static let spaceButtonSpacing: CGFloat = 4
    static let spaceBarTopPadding: CGFloat = 8

    static func indent(depth: Int) -> CGFloat {
        rowLeadingPadding + CGFloat(depth) * indentation
    }
}

enum CommandBarMetrics {
    static let cornerRadius: CGFloat = 20
    static let contentInset: CGFloat = 8
    static let fieldInset: CGFloat = 20
    static let fieldTopInset: CGFloat = 16
    static let fieldIconWidth: CGFloat = 20
    static let fieldIconSpacing: CGFloat = 12
    static let fieldIconPointSize: CGFloat = 16
    static let suggestionsTopSpacing: CGFloat = 12
    static let suggestionsBottomInset: CGFloat = 4
    static let rowHeight: CGFloat = 36
    static let rowPadding: CGFloat = 12
    static let rowIconSize: CGFloat = 16
    static let rowIconSpacing: CGFloat = 12
    static let previewRowHeight: CGFloat = 24
    static let previewIconSize: CGFloat = 16
    static let previewIconSpacing: CGFloat = 8
}

enum InterfaceFont {
    static let body = Font.system(size: 13)
    static let caption = Font.system(size: 11)
    static let sectionHeader = Font.system(size: 11, weight: .semibold)
    static let rowSymbol = Font.system(size: 13, weight: .regular)
    static let controlSymbol = Font.system(size: 12, weight: .medium)
    static let accessorySymbol = Font.system(size: 10, weight: .semibold)
}

enum CornerMetrics {
    static let window: CGFloat = 26
    static let sidebarGlass = concentric(outer: window, inset: SidebarMetrics.edgeInset)

    static func concentric(outer: CGFloat, inset: CGFloat) -> CGFloat {
        max(0, outer - inset)
    }
}
