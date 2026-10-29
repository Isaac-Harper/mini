import AppKit
import CMiniCore
import MiniRules
import Observation
import SwiftUI

@MainActor
@Observable
final class PlayerDock {
    enum SidebarKind {
        case main
        case peek
    }

    private(set) var sidebar = PlayerSlot.Sidebar.expanded
    private(set) var dockedTab: Tab?
    var isHovered = false

    @ObservationIgnored private unowned let shell: ShellController
    @ObservationIgnored private var panel: PlayerDockPanel?
    @ObservationIgnored private var slotFrames: [SidebarKind: CGRect] = [:]
    @ObservationIgnored private var needsFlight = false
    @ObservationIgnored private(set) var isUndocking = false
    @ObservationIgnored private var pictureInPictureTab: Tab?

    static let flightDuration: TimeInterval = 0.3
    static let fadeDuration: TimeInterval = 0.2

    init(shell: ShellController) {
        self.shell = shell
    }

    func presentation(of tab: Tab, in store: TabStore) -> PlayerSlot.Presentation {
        PlayerSlot.presentation(phase: tab.playerPhase, isSelected: store.selectedTab === tab, sidebar: sidebar)
    }

    func showsSlot(for tab: Tab) -> Bool {
        tab === shell.store.playerTab && presentation(of: tab, in: shell.store) == .slot
    }

    func tabToDock(in store: TabStore) -> Tab? {
        guard let player = store.playerTab else { return nil }
        return [.slot, .pictureInPicture].contains(presentation(of: player, in: store)) ? player : nil
    }

    func reportSlotFrame(_ frame: CGRect?, in kind: SidebarKind) {
        slotFrames[kind] = frame
        applyFrame()
    }

    func sidebarChanged() {
        guard let windowController = shell.windowController else { return }
        let presence = windowController.sidebarPresence
        guard presence != sidebar else {
            applyFrame()
            return
        }
        sidebar = presence
        shell.refreshDisplayedTabs()
    }

    func undock(_ tab: Tab, animated: Bool, then completion: @escaping @MainActor () -> Void) -> Bool {
        guard tab === dockedTab, let panel else { return false }
        if isUndocking { return true }
        run(PlayerScripts.undockStyle, in: tab)
        exitPictureInPictureIfNeeded()
        needsFlight = false
        let cardFrame = shell.windowController.webAreaScreenFrame
        guard animated, panel.isVisible, panel.alphaValue > 0, let cardFrame else {
            finishUndocking()
            return false
        }
        isUndocking = true
        let finish: @MainActor () -> Void = { [weak self] in
            guard let self, self.isUndocking else { return }
            self.isUndocking = false
            self.finishUndocking()
            completion()
        }
        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = Self.fadeDuration
                panel.animator().alphaValue = 0
            }, completionHandler: { MainActor.assumeIsolated { finish() } })
            return true
        }
        panel.dockView.animateCornerRadius(to: WebContentViewController.cardCornerRadius, duration: Self.flightDuration)
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = Self.flightDuration
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            panel.animator().setFrame(cardFrame, display: true)
        }, completionHandler: { MainActor.assumeIsolated { finish() } })
        return true
    }

    func update(animated: Bool) {
        sidebar = shell.windowController.sidebarPresence
        guard !isUndocking else { return }
        let target = tabToDock(in: shell.store)
        if let dockedTab, dockedTab !== target {
            release(dockedTab)
        }
        if let target, dockedTab == nil {
            dock(target, animated: animated)
        }
        applyFrame()
    }

    func pageFinishedLoading(_ tab: Tab) {
        guard tab === dockedTab, !isUndocking else { return }
        run(PlayerScripts.dockStyle, in: tab)
    }

    func togglePlayback() {
        guard let dockedTab else { return }
        run(PlayerScripts.togglePlayback, in: dockedTab)
    }

    func skip(by seconds: Int) {
        guard let dockedTab else { return }
        run(PlayerScripts.skip(by: seconds), in: dockedTab)
    }

    func popOut() {
        guard let dockedTab else { return }
        run(PlayerScripts.enterPictureInPicture, in: dockedTab)
    }

    func closeVideo() {
        guard let dockedTab else { return }
        run(PlayerScripts.pause, in: dockedTab)
        dockedTab.playerPhase = .idle
        shell.refreshDisplayedTabs()
    }

    private func dock(_ tab: Tab, animated: Bool) {
        let panel = self.panel ?? makePanel()
        let hostView = tab.hostView
        let startFrame = hostView.window === shell.window && !hostView.isHidden ? hostView.window?.convertToScreen(hostView.convert(hostView.bounds, to: nil)) : nil
        panel.dockView.embed(hostView)
        hostView.isHidden = false
        dockedTab = tab
        isHovered = false
        if tab.hasBrowser {
            mini_browser_set_focus(tab.id, false)
            mini_browser_set_hidden(tab.id, false)
            run(PlayerScripts.dockStyle, in: tab)
        } else {
            shell.createBrowser(for: tab)
        }
        if animated, let startFrame {
            panel.alphaValue = 1
            panel.setFrame(startFrame, display: true)
            panel.dockView.setCornerRadius(WebContentViewController.cardCornerRadius)
            needsFlight = true
        } else {
            panel.alphaValue = 0
            needsFlight = false
        }
        if panel.parent == nil {
            shell.window.addChildWindow(panel, ordered: .above)
        }
        panel.orderFront(nil)
    }

    private func release(_ tab: Tab) {
        exitPictureInPictureIfNeeded()
        dockedTab = nil
        needsFlight = false
        panel?.orderOut(nil)
        let hostView = tab.hostView
        hostView.isHidden = true
        shell.windowController.webAreaView.addSubview(hostView, positioned: .below, relativeTo: nil)
        guard tab.hasBrowser, shell.space(containing: tab.id)?.store.tab(withIdentifier: tab.id) === tab else { return }
        run(PlayerScripts.undockStyle, in: tab)
        mini_browser_set_hidden(tab.id, true)
    }

    private func finishUndocking() {
        dockedTab = nil
        isHovered = false
        panel?.orderOut(nil)
        panel?.alphaValue = 1
    }

    private func applyFrame() {
        guard let dockedTab, let panel, !isUndocking else { return }
        if presentation(of: dockedTab, in: shell.store) == .pictureInPicture {
            panel.ignoresMouseEvents = true
            panel.alphaValue = 0
            needsFlight = false
            if pictureInPictureTab == nil, dockedTab.isPlayingAudio {
                pictureInPictureTab = dockedTab
                run(PlayerScripts.enterPictureInPicture, in: dockedTab)
            }
            return
        }
        exitPictureInPictureIfNeeded()
        guard let frame = slotScreenFrame() else { return }
        panel.ignoresMouseEvents = false
        let radius = CornerMetrics.playerSlot
        guard needsFlight else {
            if panel.frame != frame { panel.setFrame(frame, display: true) }
            panel.dockView.setCornerRadius(radius)
            if panel.alphaValue < 1 {
                NSAnimationContext.runAnimationGroup { context in
                    context.duration = Self.fadeDuration
                    panel.animator().alphaValue = 1
                }
            }
            return
        }
        needsFlight = false
        panel.alphaValue = 1
        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            panel.alphaValue = 0
            panel.setFrame(frame, display: true)
            panel.dockView.setCornerRadius(radius)
            NSAnimationContext.runAnimationGroup { context in
                context.duration = Self.fadeDuration
                panel.animator().alphaValue = 1
            }
            return
        }
        panel.dockView.animateCornerRadius(to: radius, duration: Self.flightDuration)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = Self.flightDuration
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            panel.animator().setFrame(frame, display: true)
        }
    }

    private func exitPictureInPictureIfNeeded() {
        guard let tab = pictureInPictureTab else { return }
        pictureInPictureTab = nil
        if tab.hasBrowser { run(PlayerScripts.exitPictureInPicture, in: tab) }
    }

    private func slotScreenFrame() -> NSRect? {
        let kind: SidebarKind = sidebar == .peeking ? .peek : .main
        guard let frame = slotFrames[kind], frame.width > 0, let hostingView = shell.windowController.sidebarHostingView(for: kind),
              let window = hostingView.window, window.isVisible, let contentView = window.contentView else { return nil }
        return window.convertToScreen(NSRect(x: frame.minX, y: contentView.bounds.height - frame.maxY, width: frame.width, height: frame.height))
    }

    private func makePanel() -> PlayerDockPanel {
        let panel = PlayerDockPanel(dock: self, shell: shell)
        self.panel = panel
        return panel
    }

    private func run(_ script: String, in tab: Tab) {
        guard tab.hasBrowser else { return }
        script.withCString { mini_browser_load_url(tab.id, $0) }
    }
}

final class PlayerDockPanel: NSPanel {
    let dockView: PlayerDockView

    @MainActor
    init(dock: PlayerDock, shell: ShellController) {
        dockView = PlayerDockView(controls: PlayerDockControls(shell: shell, dock: dock), dock: dock)
        super.init(contentRect: NSRect(x: 0, y: 0, width: 224, height: 126), styleMask: [.borderless], backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        isReleasedWhenClosed = false
        animationBehavior = .none
        contentView = dockView
    }

    override var canBecomeKey: Bool { false }

    override var canBecomeMain: Bool { false }
}

final class PlayerDockView: NSView {
    private let glassView = NSGlassEffectView()
    private let videoView = NSView()
    private let controlsView: PlayerControlsHostingView
    private weak var dock: PlayerDock?

    private static let edgeWidth: CGFloat = 1.5

    @MainActor
    init(controls: PlayerDockControls, dock: PlayerDock) {
        controlsView = PlayerControlsHostingView(rootView: controls)
        self.dock = dock
        super.init(frame: NSRect(x: 0, y: 0, width: 224, height: 126))
        wantsLayer = true
        glassView.frame = bounds
        glassView.autoresizingMask = [.width, .height]
        addSubview(glassView)
        videoView.wantsLayer = true
        videoView.layer?.masksToBounds = true
        videoView.layer?.cornerCurve = .continuous
        videoView.layer?.backgroundColor = NSColor.black.cgColor
        videoView.frame = bounds.insetBy(dx: Self.edgeWidth, dy: Self.edgeWidth)
        videoView.autoresizingMask = [.width, .height]
        addSubview(videoView)
        controlsView.sizingOptions = []
        controlsView.frame = bounds
        controlsView.autoresizingMask = [.width, .height]
        addSubview(controlsView)
        setCornerRadius(CornerMetrics.playerSlot)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    func embed(_ hostView: BrowserHostView) {
        hostView.frame = videoView.bounds
        hostView.autoresizingMask = [.width, .height]
        videoView.addSubview(hostView)
    }

    func setCornerRadius(_ radius: CGFloat) {
        glassView.cornerRadius = radius
        videoView.layer?.removeAnimation(forKey: "cornerRadius")
        videoView.layer?.cornerRadius = max(0, radius - Self.edgeWidth)
    }

    func animateCornerRadius(to radius: CGFloat, duration: TimeInterval) {
        guard let layer = videoView.layer else { return }
        let animation = CABasicAnimation(keyPath: "cornerRadius")
        animation.fromValue = layer.presentation()?.cornerRadius ?? layer.cornerRadius
        animation.toValue = max(0, radius - Self.edgeWidth)
        animation.duration = duration
        animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        layer.cornerRadius = max(0, radius - Self.edgeWidth)
        layer.add(animation, forKey: "cornerRadius")
        glassView.cornerRadius = radius
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas { removeTrackingArea(area) }
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self))
    }

    override func mouseEntered(with event: NSEvent) {
        dock?.isHovered = true
    }

    override func mouseExited(with event: NSEvent) {
        dock?.isHovered = false
    }
}

final class PlayerControlsHostingView: NSHostingView<PlayerDockControls> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

enum PlayerScripts {
    private static let pick = "function pick(){var marked=document.querySelector('video[data-mini-player]');if(marked)return marked;var videos=Array.prototype.slice.call(document.querySelectorAll('video'));var playing=videos.filter(function(video){return !video.paused&&!video.ended;});var pool=playing.length?playing:videos.filter(function(video){return video.currentTime>0;});if(!pool.length)pool=videos;return pool.sort(function(first,second){return second.clientWidth*second.clientHeight-first.clientWidth*first.clientHeight;})[0];}"

    private static func wrap(_ body: String) -> String {
        "javascript:void((function(){" + pick + body + "})())"
    }

    static let dockStyle = wrap("var video=pick();if(!video)return;Array.prototype.forEach.call(document.querySelectorAll('[data-mini-player],[data-mini-player-path]'),function(element){element.removeAttribute('data-mini-player');element.removeAttribute('data-mini-player-path');});video.setAttribute('data-mini-player','');for(var node=video.parentElement;node;node=node.parentElement)node.setAttribute('data-mini-player-path','');var style=document.getElementById('mini-player-dock');if(!style){style=document.createElement('style');style.id='mini-player-dock';document.documentElement.appendChild(style);}style.textContent='html,body{overflow:hidden!important;background:black!important}body *{visibility:hidden!important;pointer-events:none!important}[data-mini-player-path]{transform:none!important;filter:none!important;contain:none!important;will-change:auto!important;backdrop-filter:none!important}video[data-mini-player]{visibility:visible!important;position:fixed!important;inset:0!important;width:100vw!important;height:100vh!important;max-width:none!important;max-height:none!important;margin:0!important;object-fit:contain!important;transform:none!important;z-index:2147483647!important;background:black!important}';")

    static let undockStyle = wrap("var style=document.getElementById('mini-player-dock');if(style)style.remove();Array.prototype.forEach.call(document.querySelectorAll('[data-mini-player],[data-mini-player-path]'),function(element){element.removeAttribute('data-mini-player');element.removeAttribute('data-mini-player-path');});window.dispatchEvent(new Event('resize'));")

    static let togglePlayback = wrap("var video=pick();if(!video)return;if(video.paused)video.play().catch(function(){});else video.pause();")

    static let pause = wrap("Array.prototype.forEach.call(document.querySelectorAll('video,audio'),function(element){element.pause();});")

    static let enterPictureInPicture = wrap("var video=pick();if(video&&!document.pictureInPictureElement)video.requestPictureInPicture().catch(function(){});")

    static let exitPictureInPicture = wrap("if(document.pictureInPictureElement)document.exitPictureInPicture().catch(function(){});")

    static func skip(by seconds: Int) -> String {
        wrap("var video=pick();if(!video)return;var target=video.currentTime+(\(seconds));video.currentTime=Math.max(0,isFinite(video.duration)?Math.min(video.duration,target):target);")
    }
}
