import AVFoundation
import AVKit
import CMiniCore
import CoreAudio
import Observation
import SwiftUI

@MainActor
@Observable
final class AirPlayVideo: NSObject, @MainActor AVRoutePickerViewDelegate {
    private(set) var tab: Tab?
    private(set) var isPlaying = false

    @ObservationIgnored let player = AVPlayer()
    @ObservationIgnored var pickerTab: Tab?
    @ObservationIgnored private var preparedTab: Tab?
    @ObservationIgnored private var preparedURL = ""
    @ObservationIgnored private var observations: [NSKeyValueObservation] = []

    override init() {
        super.init()
        player.allowsExternalPlayback = true
        observations = [
            player.observe(\.isExternalPlaybackActive) { [weak self] _, _ in
                Task { @MainActor in self?.externalPlaybackChanged() }
            },
            player.observe(\.timeControlStatus) { [weak self] _, _ in
                Task { @MainActor in self?.timeControlStatusChanged() }
            },
        ]
    }

    func routePickerViewWillBeginPresentingRoutes(_ routePickerView: AVRoutePickerView) {
        guard let tab = pickerTab, tab !== self.tab, let url = URL(string: tab.mediaVideoURL) else { return }
        preparedTab = tab
        preparedURL = tab.mediaVideoURL
        player.replaceCurrentItem(with: AVPlayerItem(url: url))
    }

    func videoHandedOff(_ tab: Tab, url: String, position: Double) {
        guard tab === self.tab, url == preparedURL else { return }
        player.seek(to: CMTime(seconds: position, preferredTimescale: 600))
        player.play()
    }

    func togglePlayback() {
        if player.timeControlStatus == .paused {
            player.play()
        } else {
            player.pause()
        }
    }

    func end(takingBack takesBack: Bool) {
        guard let tab else { return }
        let position = player.currentTime().seconds
        let wasPlaying = player.timeControlStatus != .paused
        self.tab = nil
        preparedTab = nil
        player.pause()
        player.replaceCurrentItem(with: nil)
        if takesBack, tab.hasBrowser, position.isFinite, position >= 0 {
            tab.isPausedFromNowPlaying = !wasPlaying
            mini_browser_take_back_video(tab.id, preparedURL, position, wasPlaying)
        }
    }

    private func externalPlaybackChanged() {
        if player.isExternalPlaybackActive {
            guard tab == nil, let preparedTab, preparedTab.hasBrowser else { return }
            tab = preparedTab
            preparedTab.isPausedFromNowPlaying = true
            mini_browser_hand_off_video(preparedTab.id, preparedURL)
        } else {
            end(takingBack: true)
        }
    }

    private func timeControlStatusChanged() {
        isPlaying = player.timeControlStatus != .paused
    }
}

@MainActor
@Observable
final class SoundOutput {
    private(set) var airPlayDeviceName: String?

    private static let systemObject = AudioObjectID(kAudioObjectSystemObject)
    private static var defaultOutputAddress = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyDefaultOutputDevice,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain)

    init() {
        let status = AudioObjectAddPropertyListenerBlock(Self.systemObject, &Self.defaultOutputAddress, .main) { [weak self] _, _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        precondition(status == noErr, "Listening for the default output device failed: \(status)")
        refresh()
    }

    private func refresh() {
        var device = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(Self.systemObject, &Self.defaultOutputAddress, 0, nil, &size, &device) == noErr,
              Self.transportType(of: device) == kAudioDeviceTransportTypeAirPlay else {
            airPlayDeviceName = nil
            return
        }
        airPlayDeviceName = Self.name(of: device)
    }

    private static func transportType(of device: AudioObjectID) -> UInt32? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyTransportType, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var transport: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        return AudioObjectGetPropertyData(device, &address, 0, nil, &size, &transport) == noErr ? transport : nil
    }

    private static func name(of device: AudioObjectID) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioObjectPropertyName, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var name: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &name) == noErr, let name else { return nil }
        return name.takeRetainedValue() as String
    }
}

struct AirPlayButton: View {
    let shell: ShellController
    let tab: Tab

    var body: some View {
        if !tab.mediaVideoURL.isEmpty || shell.airPlay.tab === tab {
            RoutePicker(airPlay: shell.airPlay, tab: tab, activeColor: shell.currentSpace.color.accent)
                .frame(width: SidebarMetrics.accessorySize, height: SidebarMetrics.accessorySize)
                .glassTooltip(shell.airPlay.tab === tab ? "Playing on AirPlay" : "AirPlay Video")
        } else {
            SoundOutputMenuButton(deviceName: shell.soundOutput.airPlayDeviceName, activeColor: shell.currentSpace.color.accent)
                .frame(width: SidebarMetrics.accessorySize, height: SidebarMetrics.accessorySize)
                .glassTooltip(shell.soundOutput.airPlayDeviceName.map { "Sound plays on \($0)" } ?? "AirPlay")
        }
    }
}

private struct SoundOutputMenuButton: NSViewRepresentable {
    let deviceName: String?
    let activeColor: NSColor

    private static let soundSettings = URL(string: "x-apple.systempreferences:com.apple.Sound-Settings.extension")!
    private static let displaySettings = URL(string: "x-apple.systempreferences:com.apple.Displays-Settings.extension")!

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSButton {
        guard let image = NSImage(systemSymbolName: "airplayaudio", accessibilityDescription: "AirPlay") else {
            preconditionFailure("The airplayaudio symbol is missing")
        }
        let button = NSButton(image: image, target: context.coordinator, action: #selector(Coordinator.showMenu(_:)))
        button.isBordered = false
        button.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 12, weight: .medium)
        button.refusesFirstResponder = true
        return button
    }

    func updateNSView(_ button: NSButton, context: Context) {
        context.coordinator.deviceName = deviceName
        button.contentTintColor = deviceName == nil ? .secondaryLabelColor : activeColor
    }

    @MainActor
    final class Coordinator: NSObject {
        var deviceName: String?

        @objc func showMenu(_ sender: NSButton) {
            let menu = NSMenu()
            menu.addItem(.sectionHeader(title: deviceName.map { "Sound plays on \($0)" } ?? "AirPlay the Mac’s sound or screen"))
            menu.addItem(withTitle: "Sound Output…", action: #selector(openSoundSettings), keyEquivalent: "").target = self
            menu.addItem(withTitle: "Mirror Display…", action: #selector(openDisplaySettings), keyEquivalent: "").target = self
            menu.popUp(positioning: nil, at: NSPoint(x: 0, y: sender.isFlipped ? sender.bounds.height + 4 : -4), in: sender)
        }

        @objc private func openSoundSettings() {
            NSWorkspace.shared.open(SoundOutputMenuButton.soundSettings)
        }

        @objc private func openDisplaySettings() {
            NSWorkspace.shared.open(SoundOutputMenuButton.displaySettings)
        }
    }
}

private struct RoutePicker: NSViewRepresentable {
    let airPlay: AirPlayVideo
    let tab: Tab
    let activeColor: NSColor

    func makeNSView(context: Context) -> AVRoutePickerView {
        let picker = AVRoutePickerView()
        picker.player = airPlay.player
        picker.delegate = airPlay
        picker.isRoutePickerButtonBordered = false
        picker.setRoutePickerButtonColor(.secondaryLabelColor, for: .normal)
        picker.setRoutePickerButtonColor(.labelColor, for: .normalHighlighted)
        return picker
    }

    func updateNSView(_ picker: AVRoutePickerView, context: Context) {
        airPlay.pickerTab = tab
        picker.setRoutePickerButtonColor(activeColor, for: .active)
        picker.setRoutePickerButtonColor(activeColor, for: .activeHighlighted)
    }
}
