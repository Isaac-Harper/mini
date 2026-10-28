import SwiftUI

struct CommandSuggestionsView: View {
    let model: CommandBarModel
    let activate: (CommandSuggestion) -> Void

    var body: some View {
        if !model.suggestions.isEmpty {
            VStack(spacing: 0) {
                ForEach(Array(model.suggestions.enumerated()), id: \.element.id) { index, suggestion in
                    if suggestion.isArchived, index == 0 || !model.suggestions[index - 1].isArchived {
                        Text("Archived")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.tertiary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 12)
                            .padding(.top, 8)
                            .padding(.bottom, 4)
                    }
                    CommandSuggestionRow(suggestion: suggestion, isSelected: index == model.selectedIndex)
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

private struct CommandSuggestionRow: View {
    let suggestion: CommandSuggestion
    let isSelected: Bool

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
        case .archived:
            Image(systemName: "archivebox").foregroundStyle(.secondary)
        }
    }

    private var title: String {
        switch suggestion {
        case .switchToTab(let tab): tab.displayTitle
        case .open(.address(let address)): address
        case .open(.search(let query)): query
        case .archived(let entry): entry.title
        }
    }

    private var detail: String? {
        switch suggestion {
        case .switchToTab(let tab): URLInput.host(of: tab.url)
        case .open(.address): nil
        case .open(.search): "Search Google"
        case .archived(let entry): URLInput.host(of: entry.url)
        }
    }

    private var hint: String {
        switch suggestion {
        case .switchToTab: "Switch to Tab"
        case .open(.address): "Open"
        case .open(.search): "Search"
        case .archived: "Reopen"
        }
    }
}
