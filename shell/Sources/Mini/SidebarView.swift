import CMiniCore
import SwiftUI

struct SidebarView: View {
    let shell: ShellController

    private var store: TabStore { shell.store }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            navigationRow
            addressPill
                .padding(.horizontal, 10)
                .padding(.bottom, 10)
            if !store.pinnedTabs.isEmpty {
                PinnedTabsView(shell: shell)
                    .padding(.horizontal, 10)
                    .padding(.bottom, 14)
            }
            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(store.visibleTabs) { visibleTab in
                        TabRowView(shell: shell, tab: visibleTab.tab, depth: visibleTab.depth)
                    }
                }
                .padding(.horizontal, 8)
            }
            .scrollIndicators(.never)
            Spacer(minLength: 0)
            footer
        }
        .font(.system(size: 13))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            Color.clear
                .contentShape(Rectangle())
                .gesture(WindowDragGesture())
        }
    }

    private var navigationRow: some View {
        let selected = store.selectedTab
        return HStack(spacing: 2) {
            Spacer()
            ChromeIconButton(systemName: "chevron.left", isEnabled: selected?.canGoBack ?? false) {
                shell.goBack()
            }
            ChromeIconButton(systemName: "chevron.right", isEnabled: selected?.canGoForward ?? false) {
                shell.goForward()
            }
            ChromeIconButton(systemName: "arrow.clockwise", isEnabled: !(selected?.url.isEmpty ?? true)) {
                shell.reloadSelected()
            }
        }
        .padding(.leading, 78)
        .padding(.trailing, 10)
        .frame(height: 40)
    }

    private var addressPill: some View {
        let host = store.selectedTab.flatMap { URLInput.host(of: $0.url) }
        return Button {
            shell.commandBar.open(mode: .editCurrent)
        } label: {
            Text(host ?? "Search or enter URL")
                .lineLimit(1)
                .truncationMode(.middle)
                .foregroundStyle(host == nil ? .tertiary : .secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 10)
                .frame(height: 30)
                .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focusable(false)
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let notice = shell.downloadNotice {
                Button {
                    shell.revealDownload(notice)
                } label: {
                    Label("Downloaded \(notice.fileName)", systemImage: "arrow.down.circle")
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 8)
                        .frame(height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .focusable(false)
                .transition(.opacity)
            }
            Button {
                shell.commandBar.open(mode: .newTab)
            } label: {
                Label("New Tab", systemImage: "plus")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 8)
                    .frame(height: 30)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .focusable(false)
        }
        .animation(.easeInOut(duration: 0.4), value: shell.downloadNotice)
        .padding(.horizontal, 8)
        .padding(.bottom, 10)
    }
}

struct ChromeIconButton: View {
    let systemName: String
    let isEnabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 26, height: 26)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focusable(false)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.4)
    }
}
