import AppKit
import CMiniCore
import SwiftUI

@MainActor
final class CrashOverlayController {
    private unowned let shell: ShellController
    private let hostingView: NSHostingView<CrashOverlayView>

    init(shell: ShellController, windowController: MainWindowController) {
        self.shell = shell
        hostingView = NSHostingView(rootView: CrashOverlayView { [weak shell] in shell?.reloadCrashedTab() })
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
        let shouldShow = shell.store.selectedTab?.hasCrashed ?? false
        guard shouldShow == hostingView.isHidden else { return }
        hostingView.isHidden = !shouldShow
        if shouldShow {
            OverlayAnimation.appear(hostingView)
        }
    }
}

struct CrashOverlayView: View {
    let reload: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 28, weight: .regular))
                .foregroundStyle(.secondary)
            Text("This page crashed")
                .font(.system(size: 15, weight: .semibold))
            Button("Reload", action: reload)
                .buttonStyle(.glassProminent)
                .controlSize(.large)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}
