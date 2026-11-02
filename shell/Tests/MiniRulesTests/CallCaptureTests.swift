import Testing
import MiniRules

struct CallCaptureTests {
    private let video = CallCapture.Devices(camera: true, microphone: true)
    private let audio = CallCapture.Devices(camera: false, microphone: true)

    @Test func leavingAVideoCallDocksAndAnAudioCallDoesNot() {
        #expect(CallCapture.phase(afterLeaving: video) == .docked)
        #expect(CallCapture.phase(afterLeaving: audio) == .idle)
        #expect(CallCapture.phase(afterLeaving: .none) == .idle)
    }

    @Test func cameraEndingUndocks() {
        #expect(CallCapture.phase(.docked, afterCaptureChange: audio) == .idle)
        #expect(CallCapture.phase(.docked, afterCaptureChange: .none) == .idle)
        #expect(CallCapture.phase(.docked, afterCaptureChange: video) == .docked)
        #expect(CallCapture.phase(.idle, afterCaptureChange: video) == .idle)
    }

    @Test func microphoneMuteResetsWhenTheMicrophoneStops() {
        #expect(CallCapture.microphoneMuted(true, afterCaptureChange: video))
        #expect(CallCapture.microphoneMuted(true, afterCaptureChange: audio))
        #expect(!CallCapture.microphoneMuted(true, afterCaptureChange: CallCapture.Devices(camera: true, microphone: false)))
        #expect(!CallCapture.microphoneMuted(true, afterCaptureChange: .none))
        #expect(!CallCapture.microphoneMuted(false, afterCaptureChange: video))
    }

    @Test func callPresentationNeedsTheCamera() {
        #expect(CallCapture.presentation(phase: .docked, devices: video, isShown: false, sidebar: .expanded) == .slot)
        #expect(CallCapture.presentation(phase: .docked, devices: video, isShown: false, sidebar: .hidden) == .pictureInPicture)
        #expect(CallCapture.presentation(phase: .docked, devices: video, isShown: true, sidebar: .expanded) == .page)
        #expect(CallCapture.presentation(phase: .docked, devices: audio, isShown: false, sidebar: .expanded) == .row)
        #expect(CallCapture.presentation(phase: .idle, devices: video, isShown: false, sidebar: .expanded) == .row)
    }

    @Test func aDockedCallWinsOverThePlayer() {
        #expect(CallCapture.dockOwner(call: .slot, player: .slot) == .call)
        #expect(CallCapture.dockOwner(call: .pictureInPicture, player: .pictureInPicture) == .call)
        #expect(CallCapture.dockOwner(call: .row, player: .slot) == .player)
        #expect(CallCapture.dockOwner(call: .page, player: .slot) == .player)
        #expect(CallCapture.dockOwner(call: nil, player: .slot) == .player)
        #expect(CallCapture.dockOwner(call: .row, player: .row) == nil)
        #expect(CallCapture.dockOwner(call: nil, player: nil) == nil)
    }

    @Test func playerShowsItsRowWhileACallIsDockedAndRedocksAfter() {
        #expect(CallCapture.playerPresentation(.slot, whileCallDocked: true) == .row)
        #expect(CallCapture.playerPresentation(.pictureInPicture, whileCallDocked: true) == .row)
        #expect(CallCapture.playerPresentation(.page, whileCallDocked: true) == .page)
        #expect(CallCapture.playerPresentation(.slot, whileCallDocked: false) == .slot)
    }
}
