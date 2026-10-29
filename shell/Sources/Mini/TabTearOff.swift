import AppKit
import CMiniCore
import SwiftUI

extension ShellController {
    func canTearOff(_ tab: Tab) -> Bool {
        !tab.isPinned && !tab.url.isEmpty && store.tab(withIdentifier: tab.id) === tab && groupTabs(including: tab) == nil
    }

    func tearOff(_ tab: Tab, at screenPoint: NSPoint) {
        guard canTearOff(tab) else { return }
        let store = self.store
        let before = TabArrangementSnapshot(of: store)
        let frame = LittleWindowController.frame(hangingFrom: screenPoint)
        moveIntoLittleWindow(tab, from: store, frame: frame)
        Haptics.tabTornOff()
        registerWindowTransfer("Tear Off Tab", tab: tab, store: store, undoMovesIntoWindow: false, arrangement: before, frame: frame)
    }

    func dock(_ littleWindow: LittleWindowController, at target: SidebarDragModel.Target?) {
        guard littleWindows[littleWindow.tab.id] === littleWindow, let window = littleWindow.window else { return }
        let frame = window.frame
        let tab = littleWindow.tab
        let store = littleWindow.space.store
        moveIntoMainWindow(littleWindow)
        if let target {
            place(tab, at: target, in: store)
        }
        store.select(tab)
        Haptics.littleWindowDocked()
        registerWindowTransfer("Dock Tab", tab: tab, store: store, undoMovesIntoWindow: true, arrangement: TabArrangementSnapshot(of: store), frame: frame)
    }

    func moveIntoLittleWindow(_ tab: Tab, from store: TabStore, frame: NSRect) {
        transferringTabs.insert(tab.id)
        store.release(tab)
        transferringTabs.remove(tab.id)
        let space = space(of: store)
        tab.hostView.removeFromSuperview()
        tab.hostView.isHidden = false
        let littleWindow = LittleWindowController(tab: tab, space: space, shell: self, cascadeIndex: littleWindows.count)
        littleWindows[tab.id] = littleWindow
        littleWindow.window?.setFrame(frame, display: false)
        tab.hostView.onWebViewAttached = { [weak littleWindow] in
            guard let littleWindow, littleWindow.window?.isKeyWindow == true else { return }
            littleWindow.focusWebContent()
        }
        presentLittleWindow(littleWindow)
        switch tab.browserState {
        case .created:
            mini_browser_set_hidden(tab.id, false)
        case .none:
            tab.browserState = .created
            let hostViewPointer = Unmanaged.passUnretained(tab.hostView).toOpaque()
            tab.url.withCString { url in space.id.withCString { mini_browser_create(tab.id, hostViewPointer, url, $0) } }
        case .pendingPopup:
            break
        }
    }

    func moveIntoMainWindow(_ littleWindow: LittleWindowController) {
        let tab = littleWindow.tab
        littleWindows[tab.id] = nil
        tab.hostView.onWebViewAttached = nil
        littleWindow.detachHostViewForPromotion()
        switchToSpace(littleWindow.space)
        store.adopt(tab, after: store.selectedTab.map(store.rootAncestor))
    }

    func presentLittleWindow(_ littleWindow: LittleWindowController) {
        littleWindow.showWindow(nil)
        littleWindow.window?.makeKeyAndOrderFront(nil)
    }

    private func place(_ tab: Tab, at target: SidebarDragModel.Target, in store: TabStore) {
        switch target {
        case let .row(identifier, position):
            guard let other = store.tab(withIdentifier: identifier), store.canMove(tab, relativeTo: other) else { return }
            store.move(tab, relativeTo: other, position: position)
        case .end:
            store.moveToEnd(tab)
        case .savedEnd:
            store.save(tab)
        case let .pinned(index):
            store.pin(tab, at: index)
        }
    }

    func sidebarTarget(atScreenPoint point: NSPoint) -> SidebarDragModel.Target? {
        guard window.isVisible, !window.isMiniaturized, windowController.isSidebarVisible else { return nil }
        let sidebar = windowController.sidebarHostingView
        let local = sidebar.convert(window.convertPoint(fromScreen: point), from: nil)
        guard sidebar.bounds.contains(local) else { return nil }
        for row in store.visibleTabs {
            let identifier = row.split?.leading.id ?? row.tab.id
            guard let frame = sidebarDrag.rowFrames[identifier], frame.contains(local) else { continue }
            let fraction = (local.y - frame.minY) / max(frame.height, 1)
            return .row(identifier, fraction < 0.25 ? .before : fraction > 0.75 ? .after : .inside)
        }
        return .end
    }
}

@MainActor
final class TabTearOffTracker {
    static let threshold: CGFloat = 40

    private unowned let shell: ShellController
    private let preview = TearOffPreviewPanel()
    private(set) var isPastThreshold = false

    init(shell: ShellController) {
        self.shell = shell
    }

    func update(_ tab: Tab, at point: NSPoint) {
        let isPast = shell.canTearOff(tab) && isBeyondSidebar(point)
        isPastThreshold = isPast
        if isPast, shell.sidebarDrag.target != nil {
            shell.sidebarDrag.target = nil
        }
        if shell.sidebarDrag.isPastTearOff != isPast {
            shell.sidebarDrag.isPastTearOff = isPast
        }
        if isPast {
            preview.show(for: tab, hangingFrom: point)
        } else {
            preview.hide()
        }
    }

    func release(_ tab: Tab, at point: NSPoint) {
        let tearsOff = isPastThreshold
        reset()
        if tearsOff {
            shell.tearOff(tab, at: point)
        }
    }

    func reset() {
        isPastThreshold = false
        if shell.sidebarDrag.isPastTearOff {
            shell.sidebarDrag.isPastTearOff = false
        }
        preview.hide()
    }

    private func isBeyondSidebar(_ point: NSPoint) -> Bool {
        let window = shell.window
        guard window.frame.contains(point) else { return true }
        guard shell.windowController.isSidebarVisible else { return false }
        let sidebar = shell.windowController.sidebarHostingView
        let sidebarFrame = window.convertToScreen(sidebar.convert(sidebar.bounds, to: nil))
        return point.x > sidebarFrame.maxX + Self.threshold
    }
}

@MainActor
final class LittleWindowDockTracker {
    private unowned let shell: ShellController
    private var timer: Timer?
    private weak var littleWindow: LittleWindowController?

    init(shell: ShellController) {
        self.shell = shell
    }

    func begin(_ littleWindow: LittleWindowController) {
        self.littleWindow = littleWindow
        timer?.invalidate()
        let timer = Timer(timeInterval: 1.0 / 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, let littleWindow = self.littleWindow else {
                    self?.stop()
                    return
                }
                let point = NSEvent.mouseLocation
                if NSEvent.pressedMouseButtons & 1 == 0 {
                    self.release(littleWindow, at: point)
                } else {
                    self.update(littleWindow, at: point)
                }
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func update(_ littleWindow: LittleWindowController, at point: NSPoint) {
        let target = littleWindow.space === shell.currentSpace ? shell.sidebarTarget(atScreenPoint: point) : nil
        shell.sidebarDrag.isDockingWindow = target != nil
        shell.sidebarDrag.target = target
    }

    func release(_ littleWindow: LittleWindowController, at point: NSPoint) {
        update(littleWindow, at: point)
        let target = shell.sidebarDrag.target
        let docks = shell.sidebarDrag.isDockingWindow
        stop()
        if docks {
            shell.dock(littleWindow, at: target)
        }
    }

    private func stop() {
        timer?.invalidate()
        timer = nil
        littleWindow = nil
        shell.sidebarDrag.isDockingWindow = false
        shell.sidebarDrag.target = nil
    }
}

@MainActor
final class TearOffPreviewPanel {
    private static let size = NSSize(width: 240, height: 170)

    private let panel: NSPanel
    private let hostingView = NSHostingView(rootView: TearOffPreviewView(title: "", favicon: nil))
    private var isShown = false

    init() {
        panel = NSPanel(contentRect: NSRect(origin: .zero, size: Self.size), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.ignoresMouseEvents = true
        panel.level = .floating
        panel.isReleasedWhenClosed = false
        panel.alphaValue = 0.85
        hostingView.sizingOptions = []
        hostingView.frame = NSRect(origin: .zero, size: Self.size)
        panel.contentView = hostingView
    }

    var window: NSWindow { panel }

    func show(for tab: Tab, hangingFrom point: NSPoint) {
        panel.setFrameOrigin(NSPoint(x: point.x - Self.size.width / 2, y: point.y - Self.size.height - 10))
        guard !isShown else { return }
        isShown = true
        hostingView.rootView = TearOffPreviewView(title: tab.displayTitle, favicon: tab.favicon)
        present()
    }

    func hide() {
        guard isShown else { return }
        isShown = false
        panel.orderOut(nil)
    }

    private func present() {
        panel.orderFront(nil)
    }
}

private struct TearOffPreviewView: View {
    let title: String
    let favicon: NSImage?

    private static let cornerRadius: CGFloat = 16
    private static let pageInset: CGFloat = 4
    private static let pageCornerRadius = CornerMetrics.concentric(outer: cornerRadius, inset: pageInset)

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous)
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                FaviconView(image: favicon, size: 14)
                Text(title)
                    .font(.system(size: 11, weight: .medium))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, minHeight: 28)
            Rectangle()
                .fill(.background.opacity(0.6))
                .clipShape(UnevenRoundedRectangle(bottomLeadingRadius: Self.pageCornerRadius, bottomTrailingRadius: Self.pageCornerRadius, style: .continuous))
                .padding([.horizontal, .bottom], Self.pageInset)
        }
        .glassEffect(.regular, in: shape)
        .padding(1)
    }
}
