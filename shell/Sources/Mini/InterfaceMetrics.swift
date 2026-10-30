import MiniRules
import SwiftUI

@Observable
final class InterfaceScale: @unchecked Sendable {
    static let shared = InterfaceScale()
    private static let levelKey = "interfaceSizeLevel"

    private(set) var level = InterfaceSize.level(stored: UserDefaults.standard.object(forKey: levelKey) as? Int)

    var factor: Double { InterfaceSize.scales[level] }

    static func scaled(_ value: CGFloat) -> CGFloat {
        CGFloat(InterfaceSize.scaled(Double(value), by: shared.factor))
    }

    func setLevel(_ newLevel: Int) {
        level = InterfaceSize.level(stored: newLevel)
        UserDefaults.standard.set(level, forKey: Self.levelKey)
    }
}

enum SidebarMetrics {
    static var rowHeight: CGFloat { InterfaceScale.scaled(28) }
    static var rowCornerRadius: CGFloat { InterfaceScale.scaled(8) }
    static var edgeInset: CGFloat { InterfaceScale.scaled(8) }
    static var indentation: CGFloat { InterfaceScale.scaled(16) }
    static var rowLeadingPadding: CGFloat { InterfaceScale.scaled(4) }
    static var rowTrailingPadding: CGFloat { InterfaceScale.scaled(8) }
    static var footerRowPadding: CGFloat { InterfaceScale.scaled(8) }
    static var disclosureSize: CGFloat { InterfaceScale.scaled(12) }
    static var iconSize: CGFloat { InterfaceScale.scaled(16) }
    static var iconSpacing: CGFloat { InterfaceScale.scaled(8) }
    static var accessorySize: CGFloat { InterfaceScale.scaled(16) }
    static var accessorySpacing: CGFloat { InterfaceScale.scaled(4) }
    static var titleFadeWidth: CGFloat { InterfaceScale.scaled(16) }
    static var topPadding: CGFloat { InterfaceScale.scaled(4) }
    static var sectionSpacing: CGFloat { InterfaceScale.scaled(12) }
    static var addressPillHeight: CGFloat { InterfaceScale.scaled(32) }
    static var addressPillTextInset: CGFloat { InterfaceScale.scaled(12) }
    static var addressPillButtonWidth: CGFloat { InterfaceScale.scaled(32) }
    static var addressPillChipHeight: CGFloat { InterfaceScale.scaled(16) }
    static var addressPillChipPadding: CGFloat { InterfaceScale.scaled(6) }
    static var addressPillChipMaximumTextWidth: CGFloat { InterfaceScale.scaled(92) }
    static var pinnedTileHeight: CGFloat { InterfaceScale.scaled(40) }
    static var pinnedTileSpacing: CGFloat { InterfaceScale.scaled(8) }
    static var pinnedTileCornerRadius: CGFloat { InterfaceScale.scaled(12) }
    static var pinnedTileMinimumWidth: CGFloat { InterfaceScale.scaled(44) }
    static var artworkSize: CGFloat { InterfaceScale.scaled(20) }
    static var rowBadgeHeight: CGFloat { InterfaceScale.scaled(12) }
    static var tileBadgeHeight: CGFloat { InterfaceScale.scaled(16) }
    static var badgeRingWidth: CGFloat { InterfaceScale.scaled(1.5) }
    static var sectionHeaderHeight: CGFloat { InterfaceScale.scaled(20) }
    static var sectionDividerHeight: CGFloat { InterfaceScale.scaled(12) }
    static var downloadVerticalPadding: CGFloat { InterfaceScale.scaled(4) }
    static var spaceButtonSize: CGSize { CGSize(width: InterfaceScale.scaled(28), height: InterfaceScale.scaled(24)) }
    static var spaceButtonSpacing: CGFloat { InterfaceScale.scaled(4) }
    static var spaceBarTopPadding: CGFloat { InterfaceScale.scaled(8) }
    static var playerControlSize: CGFloat { InterfaceScale.scaled(28) }
    static var playerPrimaryControlSize: CGFloat { InterfaceScale.scaled(36) }
    static var playerControlSpacing: CGFloat { InterfaceScale.scaled(8) }
    static var playerControlInset: CGFloat { InterfaceScale.scaled(8) }
    static var minimumWidth: CGFloat { InterfaceScale.scaled(200) }
    static var defaultWidth: CGFloat { InterfaceScale.scaled(240) }
    static var maximumWidth: CGFloat { InterfaceScale.scaled(400) }

    static func indent(depth: Int) -> CGFloat {
        rowLeadingPadding + CGFloat(depth) * indentation
    }
}

enum CommandBarMetrics {
    static var width: CGFloat { InterfaceScale.scaled(760) }
    static var cornerRadius: CGFloat { InterfaceScale.scaled(20) }
    static var contentInset: CGFloat { InterfaceScale.scaled(8) }
    static var fieldInset: CGFloat { InterfaceScale.scaled(20) }
    static var fieldTopInset: CGFloat { InterfaceScale.scaled(16) }
    static var fieldIconWidth: CGFloat { InterfaceScale.scaled(20) }
    static var fieldIconSpacing: CGFloat { InterfaceScale.scaled(12) }
    static var fieldIconPointSize: CGFloat { InterfaceScale.scaled(16) }
    static var suggestionsTopSpacing: CGFloat { InterfaceScale.scaled(12) }
    static var suggestionsBottomInset: CGFloat { InterfaceScale.scaled(4) }
    static var rowHeight: CGFloat { InterfaceScale.scaled(36) }
    static var sectionHeaderHeight: CGFloat { InterfaceScale.scaled(28) }
    static var noticeHeight: CGFloat { InterfaceScale.scaled(32) }
    static var bottomMargin: CGFloat { InterfaceScale.scaled(24) }
    static var rowPadding: CGFloat { InterfaceScale.scaled(12) }
    static var rowIconSize: CGFloat { InterfaceScale.scaled(16) }
    static var rowIconSpacing: CGFloat { InterfaceScale.scaled(12) }
    static var previewRowHeight: CGFloat { InterfaceScale.scaled(24) }
    static var previewIconSize: CGFloat { InterfaceScale.scaled(16) }
    static var previewIconSpacing: CGFloat { InterfaceScale.scaled(8) }
}

enum InterfaceFont {
    static var body: Font { .system(size: InterfaceScale.scaled(13)) }
    static var caption: Font { .system(size: InterfaceScale.scaled(11)) }
    static var sectionHeader: Font { .system(size: InterfaceScale.scaled(11), weight: .semibold) }
    static var rowSymbol: Font { .system(size: InterfaceScale.scaled(13), weight: .regular) }
    static var controlSymbol: Font { .system(size: InterfaceScale.scaled(12), weight: .medium) }
    static var accessorySymbol: Font { .system(size: InterfaceScale.scaled(10), weight: .semibold) }
    static var pastedLink: Font { .system(size: InterfaceScale.scaled(12)) }
    static var commandField: NSFont { .systemFont(ofSize: InterfaceScale.scaled(20)) }
    static var toast: NSFont { .systemFont(ofSize: InterfaceScale.scaled(13), weight: .medium) }
    static var tooltip: NSFont { .systemFont(ofSize: InterfaceScale.scaled(11)) }
    static var littleWindowAddress: NSFont { .systemFont(ofSize: InterfaceScale.scaled(13), weight: .medium) }

    static func unreadBadge(onTile: Bool) -> Font {
        .system(size: InterfaceScale.scaled(onTile ? 10 : 9), weight: .bold, design: .rounded)
    }
}

enum OverlayMetrics {
    static var toastHeight: CGFloat { InterfaceScale.scaled(32) }
    static var toastPadding: CGFloat { InterfaceScale.scaled(16) }
    static var tooltipHeight: CGFloat { InterfaceScale.scaled(24) }
    static var tooltipPadding: CGFloat { InterfaceScale.scaled(8) }
}

enum CornerMetrics {
    static let window: CGFloat = 26
    static let windowInset: CGFloat = 8
    static let sidebarGlass = concentric(outer: window, inset: windowInset)
    static var playerSlot: CGFloat { concentric(outer: sidebarGlass, inset: SidebarMetrics.edgeInset) }

    static func concentric(outer: CGFloat, inset: CGFloat) -> CGFloat {
        max(0, outer - inset)
    }
}
