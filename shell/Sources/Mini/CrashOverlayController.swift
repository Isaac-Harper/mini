import AppKit
import CMiniCore
import MiniRules
import SwiftUI

@MainActor
final class CrashOverlayController {
    private unowned let shell: ShellController
    private let hostingView: NSHostingView<CrashOverlayView>

    init(shell: ShellController, windowController: MainWindowController) {
        self.shell = shell
        hostingView = NSHostingView(rootView: CrashOverlayView(content: .crashed, reload: {}, retry: {}, goBack: {}))
        hostingView.sizingOptions = []
        hostingView.translatesAutoresizingMaskIntoConstraints = false
        hostingView.isHidden = true
        let webAreaView = windowController.webAreaView
        windowController.rootView.addSubview(hostingView)
        NSLayoutConstraint.activate([
            hostingView.leadingAnchor.constraint(equalTo: webAreaView.leadingAnchor),
            hostingView.trailingAnchor.constraint(equalTo: webAreaView.trailingAnchor),
            hostingView.topAnchor.constraint(equalTo: webAreaView.topAnchor),
            hostingView.bottomAnchor.constraint(equalTo: webAreaView.bottomAnchor),
        ])
    }

    func refresh() {
        let selected = shell.store.selectedTab
        let content: PageOverlayContent? = if selected?.hasCrashed == true {
            .crashed
        } else if let wait = selected?.devServerWait {
            .waitingForDevServer(port: wait.port, hasGivenUp: wait.hasGivenUp)
        } else if let selected, let page = selected.certificateErrorPage {
            .certificateError(page, canGoBack: selected.canGoBack)
        } else {
            nil
        }
        if let content {
            hostingView.rootView = CrashOverlayView(content: content, reload: { [weak shell] in shell?.reloadCrashedTab() },
                                                    retry: { [weak shell] in shell?.retryDevServer() },
                                                    goBack: { [weak shell] in shell?.goBackFromCertificateError() },
                                                    accent: shell.currentSpace.color.accent)
        }
        let shouldShow = content != nil
        guard shouldShow == hostingView.isHidden else { return }
        hostingView.isHidden = !shouldShow
        if shouldShow {
            OverlayAnimation.appear(hostingView)
        }
    }
}

enum PageOverlayContent: Equatable {
    case crashed
    case waitingForDevServer(port: Int, hasGivenUp: Bool)
    case certificateError(LoadErrorPage, canGoBack: Bool)
}

struct CrashOverlayView: View {
    let content: PageOverlayContent
    let reload: () -> Void
    let retry: () -> Void
    let goBack: () -> Void
    var accent: NSColor?

    var body: some View {
        VStack(spacing: 12) {
            switch content {
            case .crashed:
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 28, weight: .regular))
                    .foregroundStyle(.secondary)
                Text("This page crashed")
                    .font(.system(size: 15, weight: .semibold))
                Button("Reload", action: reload)
                    .buttonStyle(.glassProminent)
                    .controlSize(.large)
            case .waitingForDevServer(let port, false):
                ProgressView()
                    .controlSize(.small)
                Text("Waiting for localhost:\(String(port))")
                    .font(.system(size: 15, weight: .semibold))
                Text("The page reloads when the server answers.")
                    .font(InterfaceFont.body)
                    .foregroundStyle(.secondary)
            case .waitingForDevServer(let port, true):
                Image(systemName: "powerplug")
                    .font(.system(size: 28, weight: .regular))
                    .foregroundStyle(.secondary)
                Text("localhost:\(String(port)) is not answering")
                    .font(.system(size: 15, weight: .semibold))
                Button("Try Again", action: retry)
                    .buttonStyle(.glassProminent)
                    .controlSize(.large)
            case .certificateError(let page, let canGoBack):
                Image(systemName: page.symbolName)
                    .font(.system(size: 28, weight: .regular))
                    .foregroundStyle(.tint)
                Text(page.title)
                    .font(.system(size: 15, weight: .semibold))
                Text(page.detail)
                    .font(InterfaceFont.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 400)
                HStack(spacing: 8) {
                    if canGoBack {
                        Button("Go Back", action: goBack)
                            .buttonStyle(.glassProminent)
                        Button("Try Again", action: reload)
                            .buttonStyle(.glass)
                    } else {
                        Button("Try Again", action: reload)
                            .buttonStyle(.glassProminent)
                    }
                }
                .controlSize(.large)
            }
        }
        .tint(accent.map { Color(nsColor: $0) })
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}
