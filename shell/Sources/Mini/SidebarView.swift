import CMiniCore
import SwiftUI

enum SidebarMetrics {
    static let rowHeight: CGFloat = 28
    static let rowCornerRadius: CGFloat = 8
    static let edgeInset: CGFloat = 8
    static let indentation: CGFloat = 16
}

struct SidebarView: View {
    let shell: ShellController

    private var store: TabStore { shell.store }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var rowTransition: AnyTransition {
        reduceMotion ? .opacity : .asymmetric(insertion: .move(edge: .leading).combined(with: .opacity), removal: .opacity)
    }

    private var rowAnimation: Animation {
        return reduceMotion ? .easeInOut(duration: 0.15) : .spring(duration: 0.2)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            AddressPill(shell: shell)
                .padding(.horizontal, SidebarMetrics.edgeInset)
                .padding(.top, 4)
                .padding(.bottom, 12)
            if !store.pinnedTabs.isEmpty || shell.sidebarDrag.isDraggingUnpinnedTab {
                PinnedTabsView(shell: shell)
                    .padding(.horizontal, SidebarMetrics.edgeInset)
                    .padding(.bottom, 12)
            }
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 0) {
                        let rows = store.visibleTabs
                        let savedRows = rows.filter(\.isSaved)
                        let showsSaveDrop = shell.sidebarDrag.isDraggingUnsavedTab
                        if !savedRows.isEmpty {
                            SavedSectionHeader()
                        }
                        ForEach(savedRows) { visibleTab in
                            row(for: visibleTab)
                        }
                        if showsSaveDrop {
                            SaveDropRow(shell: shell)
                        }
                        if !savedRows.isEmpty || showsSaveDrop {
                            SavedSectionDivider()
                        }
                        ForEach(rows.filter { !$0.isSaved }) { visibleTab in
                            row(for: visibleTab)
                        }
                        Color.clear
                            .frame(height: SidebarMetrics.rowHeight * 2)
                            .overlay(alignment: .top) {
                                if shell.sidebarDrag.target == .end { InsertionLine(depth: 0) }
                            }
                            .contentShape(Rectangle())
                            .onDrop(of: SidebarDragModel.acceptedTypes, delegate: TabListEndDropDelegate(shell: shell))
                    }
                    .padding(.horizontal, SidebarMetrics.edgeInset)
                    .animation(rowAnimation, value: store.visibleTabs.map(\.id))
                }
                .scrollIndicators(.never)
                .background {
                    Color.clear
                        .contentShape(Rectangle())
                        .onTapGesture { shell.focusSidebarFromKeyboard() }
                }
                .onChange(of: shell.sidebarKeyboard.focusedTabIdentifier) { _, identifier in
                    if let identifier { proxy.scrollTo(identifier) }
                }
            }
            .id(shell.currentSpace.id)
            .transition(.opacity)
            Spacer(minLength: 0)
            footer
        }
        .font(.system(size: 13))
        .animation(.easeInOut(duration: 0.2), value: shell.currentSpace.id)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            Color.clear
                .contentShape(Rectangle())
                .gesture(WindowDragGesture())
                .simultaneousGesture(TapGesture().onEnded { shell.focusSidebarFromKeyboard() })
        }
        .background { SiteTintView(color: store.selectedTab?.themeColor) }
    }

    private func row(for visibleTab: VisibleTab) -> some View {
        Group {
            if let split = visibleTab.split {
                SplitTabRowView(shell: shell, split: split, depth: visibleTab.depth)
            } else {
                TabRowView(shell: shell, tab: visibleTab.tab, depth: visibleTab.depth)
            }
        }
        .transition(rowTransition)
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let tab = shell.nowPlayingTab {
                NowPlayingRowView(shell: shell, tab: tab)
            }
            if let reading = shell.weather.reading {
                WeatherRowView(reading: reading, presenter: shell.weatherPopover) { shell.openWeatherSearch() }
            }
            ForEach(shell.downloads.visibleDownloads) { download in
                DownloadRowView(download: download) { shell.downloads.activate(download) }
                    .transition(.opacity)
            }
            SidebarActionRow(title: "New Tab", systemImage: "plus") {
                shell.commandBar.open(mode: .newTab)
            }
            SpaceBar(shell: shell)
                .padding(.top, 6)
        }
        .animation(.easeInOut(duration: 0.3), value: shell.downloads.visibleDownloads.map(\.id))
        .padding(.horizontal, SidebarMetrics.edgeInset)
        .padding(.bottom, SidebarMetrics.edgeInset)
    }
}

struct SidebarActionRow: View {
    let title: String
    let systemImage: String
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: systemImage)
                    .font(.system(size: 13, weight: .regular))
                    .frame(width: 16)
                Text(title)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 0)
            }
            .foregroundStyle(.secondary)
            .padding(.horizontal, 8)
            .frame(height: SidebarMetrics.rowHeight)
            .background {
                if isHovered {
                    RoundedRectangle(cornerRadius: SidebarMetrics.rowCornerRadius, style: .continuous).fill(.fill.quaternary)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focusable(false)
        .onHover { isHovered = $0 }
    }
}

private struct AddressPill: View {
    let shell: ShellController

    @State private var isHovered = false

    var body: some View {
        let selected = shell.store.selectedTab
        let host = selected.flatMap { URLInput.host(of: $0.url) }
        let showsFullAddress = isHovered && host != nil
        let isInsecure = selected.map { URLInput.isInsecure($0.url) } ?? false
        GlassEffectContainer(spacing: 8) {
            HStack(spacing: 0) {
                if isInsecure {
                    Image(systemName: "lock.slash")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                        .padding(.leading, 12)
                        .padding(.trailing, -6)
                        .frame(height: 32)
                        .help("Not Secure: this page is not using HTTPS")
                        .accessibilityLabel("Not Secure")
                }
                Button {
                    shell.commandBar.open(mode: .editCurrent)
                } label: {
                    Text(showsFullAddress ? selected?.url ?? "" : host ?? "Search or enter address")
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .foregroundStyle(host == nil ? .tertiary : .secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.leading, 12)
                        .frame(height: 32)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .focusable(false)
                .help(selected?.url ?? "")
                .onHover { self.isHovered = $0 }
                if let selected, selected.hasLoginForm, selected.hasBrowser {
                    Button {
                        shell.fillPassword(nil)
                    } label: {
                        Image(systemName: "key.fill")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.secondary)
                            .frame(width: 28, height: 32)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .focusable(false)
                    .help("Fill Password")
                }
                if let selected, !selected.url.isEmpty {
                    Button {
                        if selected.isLoading {
                            shell.stopLoading(nil)
                        } else {
                            shell.reloadSelected()
                        }
                    } label: {
                        Image(systemName: selected.isLoading ? "xmark" : "arrow.clockwise")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.secondary)
                            .frame(width: 32, height: 32)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .focusable(false)
                    .help(selected.isLoading ? "Stop" : "Reload")
                }
            }
            .glassEffect(.regular.interactive(), in: Capsule())
        }
    }
}

private struct SpaceBar: View {
    let shell: ShellController

    var body: some View {
        HStack(spacing: 2) {
            ForEach(shell.spaces) { space in
                SpaceButton(shell: shell, space: space)
            }
            Spacer(minLength: 0)
            SpaceBarIconButton(systemImage: "plus", help: "New Space") { shell.newSpace(nil) }
        }
    }
}

private struct SpaceButton: View {
    let shell: ShellController
    let space: Space

    private var isCurrent: Bool { shell.currentSpace === space }

    var body: some View {
        SpaceBarIconButton(systemImage: space.symbol, help: space.name, isSelected: isCurrent) {
            shell.switchToSpace(space)
        }
        .contextMenu {
            Button("Rename Space\u{2026}") {
                shell.switchToSpace(space)
                shell.renameCurrentSpace(nil)
            }
            Button("Delete Space\u{2026}") { shell.confirmDeletion(of: space) }
                .disabled(!shell.canDelete(space))
        }
    }
}

private struct SpaceBarIconButton: View {
    let systemImage: String
    let help: String
    var isSelected = false
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(isSelected ? .primary : .secondary)
                .frame(width: 28, height: 24)
                .background {
                    let shape = RoundedRectangle(cornerRadius: 6, style: .continuous)
                    if isSelected {
                        shape.fill(.fill.secondary)
                    } else if isHovered {
                        shape.fill(.fill.quaternary)
                    }
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focusable(false)
        .help(help)
        .onHover { isHovered = $0 }
    }
}
