import SwiftUI

struct CommandSuggestionsView: View {
    let model: CommandBarModel
    let activate: (CommandSuggestion) -> Void

    var body: some View {
        VStack(spacing: 2) {
            ForEach(Array(model.suggestions.enumerated()), id: \.element.id) { index, suggestion in
                row(for: suggestion, isSelected: index == model.selectedIndex)
                    .contentShape(Rectangle())
                    .onTapGesture { activate(suggestion) }
            }
        }
        .font(.system(size: 13))
    }

    private func row(for suggestion: CommandSuggestion, isSelected: Bool) -> some View {
        HStack(spacing: 10) {
            Image(systemName: iconName(for: suggestion))
                .foregroundStyle(.secondary)
                .frame(width: 16)
            Text(title(for: suggestion))
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 8)
            if case .switchToTab = suggestion {
                Text("Switch to Tab").foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 34)
        .background {
            if isSelected {
                RoundedRectangle(cornerRadius: 10, style: .continuous).fill(.primary.opacity(0.08))
            }
        }
    }

    private func iconName(for suggestion: CommandSuggestion) -> String {
        switch suggestion {
        case .switchToTab: "square.on.square"
        case .open(.address): "globe"
        case .open(.search): "magnifyingglass"
        }
    }

    private func title(for suggestion: CommandSuggestion) -> String {
        switch suggestion {
        case .switchToTab(let tab): tab.displayTitle
        case .open(.address(let address)): "Open \(address)"
        case .open(.search(let query)): "Search Google for \u{201C}\(query)\u{201D}"
        }
    }
}
