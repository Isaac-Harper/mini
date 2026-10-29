import SwiftUI

struct TabDragPreview: View {
    let tab: Tab
    let count: Int

    private static let width: CGFloat = 200
    private static let stackOffset: CGFloat = 4

    var body: some View {
        ZStack(alignment: .topLeading) {
            if count > 1 {
                backing.offset(x: Self.stackOffset * 2, y: Self.stackOffset * 2).opacity(0.5)
                backing.offset(x: Self.stackOffset, y: Self.stackOffset).opacity(0.8)
            }
            HStack(spacing: SidebarMetrics.iconSpacing) {
                FaviconView(image: tab.favicon, size: SidebarMetrics.iconSize, tone: tab.faviconTone)
                Text(count > 1 ? "\(count) tabs" : tab.displayTitle)
                    .font(InterfaceFont.body)
                    .fadingTruncation()
            }
            .padding(.horizontal, SidebarMetrics.addressPillTextInset)
            .frame(width: Self.width, height: SidebarMetrics.rowHeight)
            .background { backing }
        }
        .padding(count > 1 ? Self.stackOffset * 2 : 0)
    }

    private var backing: some View {
        Capsule()
            .fill(Color(nsColor: .windowBackgroundColor).opacity(0.85))
            .glassEffect(.regular, in: Capsule())
            .frame(width: Self.width, height: SidebarMetrics.rowHeight)
    }
}

struct PinnedTileDragPreview: View {
    let tab: Tab

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: SidebarMetrics.pinnedTileCornerRadius, style: .continuous)
        FaviconView(image: tab.favicon, size: SidebarMetrics.iconSize, tone: tab.faviconTone)
            .frame(width: SidebarMetrics.pinnedTileMinimumWidth + SidebarMetrics.pinnedTileSpacing * 2, height: SidebarMetrics.pinnedTileHeight)
            .background(shape.fill(Color(nsColor: .windowBackgroundColor).opacity(0.85)))
            .glassEffect(.regular, in: shape)
    }
}
