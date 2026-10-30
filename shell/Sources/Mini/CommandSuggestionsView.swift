import SwiftUI

struct CommandSuggestionsView: View {
    let model: CommandBarModel
    let faviconLookup: (String) -> NSImage?
    let activate: (CommandSuggestion) -> Void

    @Namespace private var selectionNamespace
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    static let maximumPreviewRows = 6

    static func contentHeight(of rows: [CommandRow]) -> CGFloat {
        guard !rows.isEmpty else { return 0 }
        return rows.reduce(CommandBarMetrics.contentInset) { height, row in
            let header = row.header == nil ? 0 : CommandBarMetrics.sectionHeaderHeight
            switch row.suggestion {
            case .notice:
                return height + header + CommandBarMetrics.noticeHeight
            case .openLinks(let links):
                let previewRows = min(links.count, maximumPreviewRows) + (links.count > maximumPreviewRows ? 1 : 0)
                return height + header + CommandBarMetrics.rowHeight + CGFloat(previewRows) * CommandBarMetrics.previewRowHeight + CommandBarMetrics.suggestionsBottomInset
            default:
                return height + header + CommandBarMetrics.rowHeight
            }
        }
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical) {
                VStack(spacing: 0) {
                    ForEach(Array(model.rows.enumerated()), id: \.element.id) { index, row in
                        if let header = row.header {
                            SuggestionSectionHeader(title: header)
                        }
                        rowView(row, at: index)
                    }
                }
                .padding(.horizontal, CommandBarMetrics.contentInset)
                .padding(.bottom, CommandBarMetrics.contentInset)
                .animation(reduceMotion ? nil : .spring(duration: 0.2, bounce: 0.1), value: model.selectedIndex)
            }
            .scrollIndicators(.automatic)
            .scrollBounceBehavior(.basedOnSize)
            .onChange(of: model.keyboardSelectionCount) {
                if let identifier = model.selectedSuggestion?.id { proxy.scrollTo(identifier) }
            }
            .onChange(of: model.sessionCount) {
                if let first = model.rows.first?.id { proxy.scrollTo(first, anchor: .top) }
            }
        }
    }

    @ViewBuilder
    private func rowView(_ row: CommandRow, at index: Int) -> some View {
        let suggestion = row.suggestion
        if case .notice(let text) = suggestion {
            Text(text)
                .font(InterfaceFont.caption)
                .foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, CommandBarMetrics.rowPadding + CommandBarMetrics.rowIconSize + CommandBarMetrics.rowIconSpacing)
                .frame(height: CommandBarMetrics.noticeHeight)
                .id(row.id)
        } else {
            CommandSuggestionRow(suggestion: suggestion, isSelected: index == model.selectedIndex, faviconLookup: faviconLookup,
                                 selectionNamespace: reduceMotion ? nil : selectionNamespace)
                .contentShape(Rectangle())
                .onContinuousHover { phase in
                    if case .active = phase { model.pointerMoved(to: NSEvent.mouseLocation, over: index) }
                }
                .onTapGesture {
                    if suggestion.isActivatable { Haptics.controlActivated(.press) }
                    activate(suggestion)
                }
                .accessibilityAction { activate(suggestion) }
                .id(row.id)
            if case .openLinks(let links) = suggestion {
                PastedLinkPreviews(links: links, faviconLookup: faviconLookup)
            }
        }
    }
}

private struct SuggestionSectionHeader: View {
    let title: String

    var body: some View {
        Text(title)
            .font(InterfaceFont.sectionHeader)
            .foregroundStyle(.tertiary)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
            .padding(.horizontal, CommandBarMetrics.rowPadding)
            .padding(.bottom, CommandBarMetrics.suggestionsBottomInset)
            .frame(height: CommandBarMetrics.sectionHeaderHeight)
            .accessibilityAddTraits(.isHeader)
    }
}

private struct CommandSuggestionRow: View {
    let suggestion: CommandSuggestion
    let isSelected: Bool
    let faviconLookup: (String) -> NSImage?
    let selectionNamespace: Namespace.ID?

    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        HStack(spacing: CommandBarMetrics.rowIconSpacing) {
            icon.frame(width: CommandBarMetrics.rowIconSize, height: CommandBarMetrics.rowIconSize)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: SidebarMetrics.accessorySpacing) {
                    Text(title)
                        .font(InterfaceFont.body)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    if case .switchToTab(let tab) = suggestion, tab.isSaved {
                        Image(systemName: "bookmark.fill")
                            .font(InterfaceFont.accessorySymbol)
                            .foregroundStyle(.secondary)
                            .accessibilityLabel("Saved")
                    }
                    if case .action(let action) = suggestion, action.isOn {
                        Image(systemName: "checkmark")
                            .font(InterfaceFont.accessorySymbol)
                            .foregroundStyle(.secondary)
                            .accessibilityLabel("On")
                    }
                }
                if let detail {
                    Text(detail)
                        .font(InterfaceFont.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            Spacer(minLength: CommandBarMetrics.rowPadding)
            Text(hint)
                .font(InterfaceFont.caption)
                .foregroundStyle(.tertiary)
                .lineLimit(1)
                .fixedSize()
        }
        .padding(.horizontal, CommandBarMetrics.rowPadding)
        .frame(height: CommandBarMetrics.rowHeight)
        .opacity(isDisabled ? 0.4 : 1)
        .background {
            if isSelected {
                let highlight = RoundedRectangle(cornerRadius: CornerMetrics.concentric(outer: CommandBarMetrics.cornerRadius, inset: CommandBarMetrics.contentInset), style: .continuous)
                    .fill(contrast == .increased ? AnyShapeStyle(FillShapeStyle()) : AnyShapeStyle(.fill.secondary))
                if let selectionNamespace {
                    highlight.matchedGeometryEffect(id: "commandSelection", in: selectionNamespace)
                } else {
                    highlight
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(suggestion.spokenDescription)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    private var isDisabled: Bool {
        if case .action(let action) = suggestion { return !action.isEnabled }
        return false
    }

    @ViewBuilder
    private var icon: some View {
        switch suggestion {
        case .switchToTab(let tab):
            FaviconView(image: tab.favicon, size: CommandBarMetrics.rowIconSize, tone: tab.faviconTone)
        case .open(.address):
            Image(systemName: "globe").foregroundStyle(.secondary)
        case .open(.search):
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
        case .searchSuggestion:
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
        case .history(let entry):
            if let favicon = faviconLookup(entry.url) {
                FaviconView(image: favicon, size: CommandBarMetrics.rowIconSize)
            } else {
                Image(systemName: "clock").foregroundStyle(.secondary)
            }
        case .archived(let entry):
            if let favicon = faviconLookup(entry.url) {
                FaviconView(image: favicon, size: CommandBarMetrics.rowIconSize)
            } else {
                Image(systemName: "archivebox").foregroundStyle(.secondary)
            }
        case .openLinks:
            Image(systemName: "square.stack").foregroundStyle(.secondary)
        case .localServer:
            Image(systemName: "server.rack").foregroundStyle(.secondary)
        case .action(let action):
            Group {
                if let image = action.image {
                    Image(nsImage: image).renderingMode(.template)
                } else {
                    Image(systemName: "command")
                }
            }
            .foregroundStyle(.secondary)
        case .notice:
            EmptyView()
        }
    }

    private var title: String { suggestion.title }

    private var detail: String? { suggestion.detail }

    private var hint: String { suggestion.hint }
}

@MainActor
extension CommandSuggestion {
    var title: String {
        switch self {
        case .switchToTab(let tab): tab.displayTitle
        case .open(.address(let address)): address
        case .open(.search(let query)): query
        case .searchSuggestion(let text): text
        case .archived(let entry): entry.title.isEmpty ? (URLInput.host(of: entry.url) ?? entry.url) : entry.title
        case .history(let entry): entry.displayTitle
        case .openLinks(let links): "Open \(links.count) Links"
        case .action(let action): action.title
        case .localServer(let server): server.title
        case .notice(let text): text
        }
    }

    var detail: String? {
        switch self {
        case .switchToTab(let tab): URLInput.host(of: tab.url)
        case .open(.address): nil
        case .open(.search): "Search Google"
        case .searchSuggestion: nil
        case .archived(let entry): URLInput.host(of: entry.url)
        case .history(let entry): URLInput.host(of: entry.url)
        case .openLinks: "Return opens them here, \u{2318}Return in the background, \u{2325}Return nested"
        case .action: nil
        case .localServer(let server): "localhost:\(String(server.port))"
        case .notice: nil
        }
    }

    var hint: String {
        switch self {
        case .switchToTab: "Switch to Tab"
        case .open(.address): "Open"
        case .open(.search): "Search"
        case .searchSuggestion: "Search"
        case .archived: "Reopen"
        case .history: "Open"
        case .openLinks: "Open All"
        case .action(let action): action.shortcut
        case .localServer: "Open"
        case .notice: ""
        }
    }

    var isActivatable: Bool {
        switch self {
        case .notice: false
        case .action(let action): action.isEnabled
        default: true
        }
    }

    var spokenDescription: String {
        let action = switch self {
        case .action(let action): action.isEnabled ? "" : "Dimmed"
        default: hint
        }
        return [title, detail ?? "", action].filter { !$0.isEmpty }.joined(separator: ", ")
    }
}

private struct PastedLinkPreviews: View {
    let links: [PastedLink]
    let faviconLookup: (String) -> NSImage?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(links.prefix(CommandSuggestionsView.maximumPreviewRows)) { link in
                HStack(spacing: CommandBarMetrics.previewIconSpacing) {
                    FaviconView(image: faviconLookup(link.url), size: CommandBarMetrics.previewIconSize)
                    Text(link.title ?? URLInput.host(of: link.url) ?? link.url)
                        .font(InterfaceFont.pastedLink)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Spacer(minLength: CommandBarMetrics.previewIconSpacing)
                    Text(URLInput.host(of: link.url) ?? "")
                        .font(InterfaceFont.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .frame(height: CommandBarMetrics.previewRowHeight)
            }
            if links.count > CommandSuggestionsView.maximumPreviewRows {
                Text("+\(links.count - CommandSuggestionsView.maximumPreviewRows) more")
                    .font(InterfaceFont.caption)
                    .foregroundStyle(.tertiary)
                    .frame(height: CommandBarMetrics.previewRowHeight)
            }
        }
        .padding(.leading, CommandBarMetrics.rowPadding + CommandBarMetrics.rowIconSize + CommandBarMetrics.rowIconSpacing)
        .padding(.trailing, CommandBarMetrics.rowPadding)
        .padding(.bottom, CommandBarMetrics.suggestionsBottomInset)
        .allowsHitTesting(false)
    }
}
