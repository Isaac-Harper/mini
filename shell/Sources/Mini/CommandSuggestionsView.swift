import SwiftUI

private struct SuggestionListEntry {
    let index: Int
    let suggestion: CommandSuggestion
    let previous: CommandSuggestion?

    static func entries(_ suggestions: [CommandSuggestion]) -> [SuggestionListEntry] {
        suggestions.indices.map { index in
            SuggestionListEntry(index: index, suggestion: suggestions[index], previous: index > 0 ? suggestions[index - 1] : nil)
        }
    }
}

struct CommandSuggestionsView: View {
    let model: CommandBarModel
    let faviconLookup: (String) -> NSImage?
    let activate: (CommandSuggestion) -> Void

    @Namespace private var selectionNamespace
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if !model.suggestions.isEmpty {
            VStack(spacing: 0) {
                ForEach(SuggestionListEntry.entries(model.suggestions), id: \.suggestion.id) { entry in
                    let index = entry.index
                    let suggestion = entry.suggestion
                    if suggestion.isLocalServer, entry.previous?.isLocalServer != true {
                        SuggestionSectionHeader(title: "Local Servers")
                    }
                    if suggestion.isHistory, entry.previous?.isHistory != true {
                        SuggestionSectionHeader(title: "History")
                    }
                    if suggestion.isArchived, entry.previous?.isArchived != true {
                        SuggestionSectionHeader(title: "Archived")
                    }
                    CommandSuggestionRow(suggestion: suggestion, isSelected: index == model.selectedIndex, faviconLookup: faviconLookup,
                                         selectionNamespace: reduceMotion ? nil : selectionNamespace)
                        .contentShape(Rectangle())
                        .onHover { isHovering in
                            if isHovering { model.selectedIndex = index }
                        }
                        .onTapGesture {
                            if case .action(let action) = suggestion, action.isEnabled { Haptics.controlActivated(.press) }
                            activate(suggestion)
                        }
                    if case .openLinks(let links) = suggestion {
                        PastedLinkPreviews(links: links, faviconLookup: faviconLookup)
                    }
                }
            }
            .padding(.horizontal, CommandBarMetrics.contentInset)
            .padding(.bottom, CommandBarMetrics.contentInset)
            .animation(reduceMotion ? nil : .spring(duration: 0.2, bounce: 0.1), value: model.selectedIndex)
        }
    }
}

private struct SuggestionSectionHeader: View {
    let title: String

    var body: some View {
        Text(title)
            .font(InterfaceFont.sectionHeader)
            .foregroundStyle(.tertiary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, CommandBarMetrics.rowPadding)
            .padding(.top, CommandBarMetrics.contentInset)
            .padding(.bottom, CommandBarMetrics.suggestionsBottomInset)
    }
}

private struct CommandSuggestionRow: View {
    let suggestion: CommandSuggestion
    let isSelected: Bool
    let faviconLookup: (String) -> NSImage?
    let selectionNamespace: Namespace.ID?

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
        }
        .padding(.horizontal, CommandBarMetrics.rowPadding)
        .frame(height: CommandBarMetrics.rowHeight)
        .opacity(isDisabled ? 0.4 : 1)
        .background {
            if isSelected {
                let highlight = RoundedRectangle(cornerRadius: CornerMetrics.concentric(outer: CommandBarMetrics.cornerRadius, inset: CommandBarMetrics.contentInset), style: .continuous)
                    .fill(.fill.secondary)
                if let selectionNamespace {
                    highlight.matchedGeometryEffect(id: "commandSelection", in: selectionNamespace)
                } else {
                    highlight
                }
            }
        }
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
        }
    }

    private var title: String {
        switch suggestion {
        case .switchToTab(let tab): tab.displayTitle
        case .open(.address(let address)): address
        case .open(.search(let query)): query
        case .searchSuggestion(let text): text
        case .archived(let entry): entry.title
        case .history(let entry): entry.displayTitle
        case .openLinks(let links): "Open \(links.count) Links"
        case .action(let action): action.title
        case .localServer(let server): server.title
        }
    }

    private var detail: String? {
        switch suggestion {
        case .switchToTab(let tab): URLInput.host(of: tab.url)
        case .open(.address): nil
        case .open(.search): "Search Google"
        case .searchSuggestion: nil
        case .archived(let entry): URLInput.host(of: entry.url)
        case .history(let entry): URLInput.host(of: entry.url)
        case .openLinks: "Return opens them here, \u{2318}Return in the background, \u{2325}Return nested"
        case .action: nil
        case .localServer(let server): "localhost:\(String(server.port))"
        }
    }

    private var hint: String {
        switch suggestion {
        case .switchToTab: "Switch to Tab"
        case .open(.address): "Open"
        case .open(.search): "Search"
        case .searchSuggestion: "Search"
        case .archived: "Reopen"
        case .history: "Open"
        case .openLinks: "Open All"
        case .action(let action): action.shortcut
        case .localServer: "Open"
        }
    }
}

private struct PastedLinkPreviews: View {
    let links: [PastedLink]
    let faviconLookup: (String) -> NSImage?

    private static let maximumRows = 6

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(links.prefix(Self.maximumRows)) { link in
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
            if links.count > Self.maximumRows {
                Text("+\(links.count - Self.maximumRows) more")
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
