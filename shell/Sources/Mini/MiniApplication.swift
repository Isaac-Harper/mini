import AppKit
import CMiniCore

@MainActor
@objc(CrAppProtocol)
protocol CrAppProtocol: NSObjectProtocol {
    func isHandlingSendEvent() -> Bool
}

@MainActor
@objc(CrAppControlProtocol)
protocol CrAppControlProtocol: CrAppProtocol {
    func setHandlingSendEvent(_ handlingSendEvent: Bool)
}

@MainActor
@objc(CefAppProtocol)
protocol CefAppProtocol: CrAppControlProtocol {}

final class MiniApplication: NSApplication, CefAppProtocol {
    private var handlingSendEvent = false
    private var isTerminating = false

    func isHandlingSendEvent() -> Bool {
        handlingSendEvent
    }

    func setHandlingSendEvent(_ handlingSendEvent: Bool) {
        self.handlingSendEvent = handlingSendEvent
    }

    override func sendEvent(_ event: NSEvent) {
        let wasHandlingSendEvent = handlingSendEvent
        handlingSendEvent = true
        defer { handlingSendEvent = wasHandlingSendEvent }
        super.sendEvent(event)
    }

    override func terminate(_ sender: Any?) {
        guard !isTerminating else { return }
        isTerminating = true
        BrowserEngine.shared.shell?.prepareForTermination()
        mini_close_all_browsers()
    }
}
