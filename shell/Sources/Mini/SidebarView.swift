import CMiniCore
import SwiftUI

extension EnvironmentValues {
    @Entry var sidebarStore: TabStore? = nil
}

struct SidebarView: View {
    let shell: ShellController
    var reportsRowFrames = false

    private var store: TabStore { shell.store }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            AddressPill(shell: shell)
                .padding(.horizontal, SidebarMetrics.edgeInset)
                .padding(.top, SidebarMetrics.topPadding)
                .padding(.bottom, SidebarMetrics.sectionSpacing)
            SpaceSwipeStage(shell: shell)
            Spacer(minLength: 0)
            footer
        }
        .font(InterfaceFont.body)
        .animation(.easeInOut(duration: 0.2), value: shell.currentSpace.id)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            Color.clear
                .contentShape(Rectangle())
                .gesture(WindowDragGesture())
                .simultaneousGesture(TapGesture().onEnded { shell.focusSidebarFromKeyboard() })
        }
        .background {
            SiteTintView(spaceColor: shell.currentSpace.color.accent, neighborColor: shell.spaceSwipe.neighbor?.color.accent,
                         swipeProgress: shell.spaceSwipe.progress, color: store.selectedTab?.themeColor, eveningStrength: shell.eveningTintStrength)
        }
        .overlay {
            if shell.sidebarDrag.isDockingWindow {
                RoundedRectangle(cornerRadius: CornerMetrics.concentric(outer: CornerMetrics.sidebarGlass, inset: SidebarMetrics.accessorySpacing), style: .continuous)
                    .fill(.tint.opacity(0.08))
                    .strokeBorder(.tint.opacity(0.5), lineWidth: 1.5)
                    .padding(SidebarMetrics.accessorySpacing)
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.15), value: shell.sidebarDrag.isDockingWindow)
        .environment(\.reportsSidebarRowFrames, reportsRowFrames)
        .tint(Color(nsColor: shell.currentSpace.color.accent))
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
                .padding(.top, SidebarMetrics.spaceBarTopPadding)
        }
        .animation(.easeInOut(duration: 0.3), value: shell.downloads.visibleDownloads.map(\.id))
        .padding(.horizontal, SidebarMetrics.edgeInset)
        .padding(.bottom, SidebarMetrics.edgeInset)
    }
}

struct SpaceTabsView: View {
    let shell: ShellController
    let space: Space

    private var store: TabStore { space.store }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var selectionNamespace

    private var rowTransition: AnyTransition {
        reduceMotion ? .opacity : .asymmetric(insertion: .move(edge: .leading).combined(with: .opacity), removal: .opacity)
    }

    private var rowAnimation: Animation {
        return reduceMotion ? .easeInOut(duration: 0.15) : .spring(duration: 0.2)
    }

    private var selectionAnimation: Animation {
        reduceMotion ? .easeInOut(duration: 0.12) : .spring(duration: 0.28, bounce: 0.12)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if !store.pinnedTabs.isEmpty || shell.sidebarDrag.isDraggingUnpinnedTab {
                PinnedTabsView(shell: shell)
                    .padding(.horizontal, SidebarMetrics.edgeInset)
                    .padding(.bottom, SidebarMetrics.sectionSpacing)
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
                    .animation(selectionAnimation, value: store.selectedTab?.id)
                    .animation(.easeOut(duration: 0.12), value: store.rowSelection)
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
        }
        .environment(\.sidebarStore, store)
        .environment(\.selectionNamespace, reduceMotion ? nil : selectionNamespace)
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
}

struct SelectionHighlight<HighlightShape: Shape>: View {
    let shape: HighlightShape

    var body: some View {
        shape.fill(.fill.tertiary)
            .overlay(shape.fill(.tint.opacity(0.2)))
    }
}

struct SidebarActionRow: View {
    let title: String
    let systemImage: String
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: SidebarMetrics.iconSpacing) {
                Image(systemName: systemImage)
                    .font(InterfaceFont.rowSymbol)
                    .frame(width: SidebarMetrics.iconSize)
                Text(title)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 0)
            }
            .foregroundStyle(.secondary)
            .padding(.horizontal, SidebarMetrics.footerRowPadding)
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
        GlassEffectContainer(spacing: SidebarMetrics.edgeInset) {
            HStack(spacing: 0) {
                if isInsecure {
                    Image(systemName: "lock.slash")
                        .font(InterfaceFont.controlSymbol)
                        .foregroundStyle(.secondary)
                        .frame(width: SidebarMetrics.iconSize, height: SidebarMetrics.addressPillHeight)
                        .padding(.leading, SidebarMetrics.addressPillTextInset)
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
                        .padding(.leading, isInsecure ? SidebarMetrics.accessorySpacing : SidebarMetrics.addressPillTextInset)
                        .frame(height: SidebarMetrics.addressPillHeight)
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
                            .font(InterfaceFont.controlSymbol)
                            .foregroundStyle(.secondary)
                            .frame(width: SidebarMetrics.addressPillButtonWidth, height: SidebarMetrics.addressPillHeight)
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
                            .font(InterfaceFont.controlSymbol)
                            .foregroundStyle(.secondary)
                            .frame(width: SidebarMetrics.addressPillButtonWidth, height: SidebarMetrics.addressPillHeight)
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
        HStack(spacing: SidebarMetrics.spaceButtonSpacing) {
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
        .tint(Color(nsColor: space.color.accent))
        .contextMenu {
            Button("Rename Space\u{2026}") {
                shell.switchToSpace(space)
                shell.renameCurrentSpace(nil)
            }
            Picker("Space Color", selection: Binding(get: { space.color }, set: { shell.setColor($0, of: space) })) {
                ForEach(SpaceColor.allCases) { color in
                    Label { Text(color.name) } icon: { Image(nsImage: color.swatch()) }
                        .tag(color)
                }
            }
            .pickerStyle(.menu)
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
                .font(InterfaceFont.controlSymbol)
                .foregroundStyle(isSelected ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                .frame(width: SidebarMetrics.spaceButtonSize.width, height: SidebarMetrics.spaceButtonSize.height)
                .background {
                    let shape = RoundedRectangle(cornerRadius: SidebarMetrics.rowCornerRadius, style: .continuous)
                    if isSelected {
                        SelectionHighlight(shape: shape)
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
