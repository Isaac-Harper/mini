import SwiftUI

struct CommandSuggestionsView: View {
    let model: CommandBarModel
    let faviconLookup: (String) -> NSImage?
    let activate: (CommandSuggestion) -> Void

    var body: some View {
        if !model.suggestions.isEmpty {
            VStack(spacing: 0) {
                ForEach(Array(model.suggestions.enumerated()), id: \.element.id) { index, suggestion in
                    if suggestion.isHistory, index == 0 || !model.suggestions[index - 1].isHistory {
                        SuggestionSectionHeader(title: "History")
                    }
                    if suggestion.isArchived, index == 0 || !model.suggestions[index - 1].isArchived {
                        SuggestionSectionHeader(title: "Archived")
                    }
                    CommandSuggestionRow(suggestion: suggestion, isSelected: index == model.selectedIndex, faviconLookup: faviconLookup)
                        .contentShape(Rectangle())
                        .onHover { isHovering in
                            if isHovering { model.selectedIndex = index }
                        }
                        .onTapGesture { activate(suggestion) }
                }
            }
            .padding(.horizontal, 8)
            .padding(.bottom, 8)
        }
    }
}

private struct SuggestionSectionHeader: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.tertiary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.top, 8)
            .padding(.bottom, 4)
    }
}

private struct CommandSuggestionRow: View {
    let suggestion: CommandSuggestion
    let isSelected: Bool
    let faviconLookup: (String) -> NSImage?

    var body: some View {
        HStack(spacing: 12) {
            icon.frame(width: 18, height: 18)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 13))
                    .lineLimit(1)
                    .truncationMode(.tail)
                if let detail {
                    Text(detail)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            Spacer(minLength: 12)
            Text(hint)
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 12)
        .frame(height: 36)
        .background {
            if isSelected {
                RoundedRectangle(cornerRadius: 12, style: .continuous).fill(.fill.secondary)
            }
        }
    }

    @ViewBuilder
    private var icon: some View {
        switch suggestion {
        case .switchToTab(let tab):
            FaviconView(image: tab.favicon, size: 16)
        case .open(.address):
            Image(systemName: "globe").foregroundStyle(.secondary)
        case .open(.search):
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
        case .searchSuggestion:
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
        case .history(let entry):
            if let favicon = faviconLookup(entry.url) {
                FaviconView(image: favicon, size: 16)
            } else {
                Image(systemName: "clock").foregroundStyle(.secondary)
            }
        case .archived(let entry):
            if let favicon = faviconLookup(entry.url) {
                FaviconView(image: favicon, size: 16)
            } else {
                Image(systemName: "archivebox").foregroundStyle(.secondary)
            }
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
        }
    }
}
