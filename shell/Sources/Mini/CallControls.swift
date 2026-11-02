import CMiniCore
import MiniRules
import SwiftUI

extension ShellController {
    func mediaCaptureChanged(_ identifier: MiniTabId, devices: CallCapture.Devices) {
        guard let tab = liveTab(identifier) else { return }
        applyMediaCapture(devices, to: tab)
    }

    func applyMediaCapture(_ devices: CallCapture.Devices, to tab: Tab) {
        tab.mediaCapture = devices
        if CallCapture.microphoneMuted(tab.isMicrophoneMuted, afterCaptureChange: devices) != tab.isMicrophoneMuted {
            setMicrophoneMuted(false, for: tab)
        }
        let phase = CallCapture.phase(tab.callPhase, afterCaptureChange: devices)
        guard phase != tab.callPhase else { return }
        tab.callPhase = phase
        if store.tab(withIdentifier: tab.id) === tab {
            refreshDisplayedTabs()
        }
    }

    func leaveCall(_ tab: Tab, in store: TabStore) {
        let phase = CallCapture.phase(afterLeaving: tab.mediaCapture)
        if phase == .docked {
            for other in store.allTabs where other !== tab {
                other.callPhase = .idle
            }
        }
        tab.callPhase = phase
    }

    func setMicrophoneMuted(_ muted: Bool, for tab: Tab) {
        guard tab.hasBrowser else { return }
        tab.isMicrophoneMuted = muted
        mini_browser_set_microphone_muted(tab.id, muted)
    }
}

struct CallCaptureControls: View {
    let shell: ShellController
    let tab: Tab

    var body: some View {
        if tab.mediaCapture.isCapturing {
            HStack(spacing: 0) {
                RecordingDot(tab: tab)
                    .frame(width: SidebarMetrics.accessorySize, height: SidebarMetrics.accessorySize)
                MicrophoneToggleButton(shell: shell, tab: tab)
            }
        }
    }
}

struct RecordingDot: View {
    let tab: Tab

    private var captureDescription: String {
        switch (tab.mediaCapture.camera, tab.mediaCapture.microphone) {
        case (true, true): "Using Camera and Microphone"
        case (true, false): "Using Camera"
        default: "Using Microphone"
        }
    }

    var body: some View {
        if tab.mediaCapture.isCapturing {
            Circle()
                .fill(.red)
                .frame(width: SidebarMetrics.recordingDotSize, height: SidebarMetrics.recordingDotSize)
                .glassTooltip(captureDescription)
        }
    }
}

struct MicrophoneToggleButton: View {
    let shell: ShellController
    let tab: Tab

    var body: some View {
        if tab.mediaCapture.microphone {
            button
        }
    }

    private var button: some View {
        Button {
            shell.setMicrophoneMuted(!tab.isMicrophoneMuted, for: tab)
        } label: {
            Image(systemName: tab.isMicrophoneMuted ? "mic.slash.fill" : "mic.fill")
                .font(InterfaceFont.accessorySymbol)
                .foregroundStyle(.secondary)
                .frame(width: SidebarMetrics.accessorySize, height: SidebarMetrics.accessorySize)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focusable(false)
        .hapticFeedback(.toggle)
        .glassTooltip(tab.isMicrophoneMuted ? "Unmute Microphone" : "Mute Microphone")
    }
}

struct DockedCallSlotView: View {
    let shell: ShellController
    let tab: Tab

    var body: some View {
        DockSlotPlaceholder(shell: shell, tab: tab)
            .contextMenu { DockedCallMenu(shell: shell, tab: tab) }
    }
}

struct DockedCallMenu: View {
    let shell: ShellController
    let tab: Tab

    var body: some View {
        if tab.mediaCapture.microphone {
            Button(tab.isMicrophoneMuted ? "Unmute Microphone" : "Mute Microphone", systemImage: tab.isMicrophoneMuted ? "mic" : "mic.slash") {
                shell.setMicrophoneMuted(!tab.isMicrophoneMuted, for: tab)
            }
        }
        Button("Return to Tab", systemImage: "arrow.up.left.and.arrow.down.right") {
            shell.clearRowSelection()
            shell.store.select(tab)
        }
    }
}
