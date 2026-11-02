import Foundation

public enum CallCapture {
    public struct Devices: Equatable, Sendable {
        public var camera: Bool
        public var microphone: Bool

        public init(camera: Bool, microphone: Bool) {
            self.camera = camera
            self.microphone = microphone
        }

        public static let none = Devices(camera: false, microphone: false)

        public var isCapturing: Bool { camera || microphone }
    }

    public enum DockOwner: Equatable, Sendable {
        case call
        case player
    }

    public static func phase(afterLeaving devices: Devices) -> PlayerSlot.Phase {
        devices.camera ? .docked : .idle
    }

    public static func phase(_ phase: PlayerSlot.Phase, afterCaptureChange devices: Devices) -> PlayerSlot.Phase {
        devices.camera ? phase : .idle
    }

    public static func microphoneMuted(_ muted: Bool, afterCaptureChange devices: Devices) -> Bool {
        devices.microphone && muted
    }

    public static func presentation(phase: PlayerSlot.Phase, devices: Devices, isShown: Bool, sidebar: PlayerSlot.Sidebar) -> PlayerSlot.Presentation {
        guard devices.camera else { return isShown ? .page : .row }
        return PlayerSlot.presentation(phase: phase, isSelected: isShown, sidebar: sidebar)
    }

    public static func dockOwner(call: PlayerSlot.Presentation?, player: PlayerSlot.Presentation?) -> DockOwner? {
        if let call, isDocked(call) { return .call }
        if let player, isDocked(player) { return .player }
        return nil
    }

    public static func playerPresentation(_ presentation: PlayerSlot.Presentation, whileCallDocked callDocked: Bool) -> PlayerSlot.Presentation {
        callDocked && isDocked(presentation) ? .row : presentation
    }

    public static func isDocked(_ presentation: PlayerSlot.Presentation) -> Bool {
        presentation == .slot || presentation == .pictureInPicture
    }
}
