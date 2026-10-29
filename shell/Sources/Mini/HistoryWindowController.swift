import AppKit
import Observation
import SwiftUI

@MainActor
@Observable
final class HistoryWindowModel {
    var query = "" {
        didSet { reload() }
    }
    private(set) var entries: [HistoryEntry] = []
    private(set) var spaceName = ""

    @ObservationIgnored private unowned let shell: ShellController

    private static let limit = 500

    init(shell: ShellController) {
        self.shell = shell
    }

    func reload() {
        spaceName = shell.currentSpace.name
        entries = shell.history.store(forSpace: shell.currentSpace.id).search(query, limit: Self.limit)
    }
}

@MainActor
final class HistoryWindowController: NSWindowController, NSWindowDelegate {
    private let model: HistoryWindowModel

    init(shell: ShellController) {
        model = HistoryWindowModel(shell: shell)
        let view = HistoryListView(model: model, shell: shell)
        let window = NSWindow(contentViewController: NSHostingController(rootView: view))
        window.title = "History"
        window.styleMask = [.titled, .closable, .resizable, .miniaturizable]
        window.setContentSize(NSSize(width: 560, height: 600))
        window.minSize = NSSize(width: 380, height: 300)
        window.setFrameAutosaveName("HistoryWindow")
        super.init(window: window)
        window.delegate = self
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    func reload() {
        model.reload()
        window?.title = "History: \(model.spaceName)"
    }

    func windowDidBecomeKey(_ notification: Notification) {
        reload()
    }
}

private struct HistoryListView: View {
    @Bindable var model: HistoryWindowModel
    let shell: ShellController

    var body: some View {
        VStack(spacing: 0) {
            TextField("Search History", text: $model.query)
                .textFieldStyle(.roundedBorder)
                .padding(12)
            if model.entries.isEmpty {
                Text(model.query.isEmpty ? "No History" : "No Matches")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(model.entries) { entry in
                    HistoryRowView(entry: entry, favicon: shell.faviconCache.image(forPageAt: entry.url)) {
                        shell.deleteHistoryEntry(entry)
                    }
                    .contentShape(Rectangle())
                    .onTapGesture(count: 2) { shell.openFromHistoryWindow(entry) }
                    .contextMenu {
                        Button("Open in New Tab") { shell.openFromHistoryWindow(entry) }
                        Button("Copy Link") {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(entry.url, forType: .string)
                        }
                        Divider()
                        Button("Delete") { shell.deleteHistoryEntry(entry) }
                    }
                }
                .listStyle(.inset)
            }
        }
        .frame(minWidth: 380, minHeight: 300)
    }
}

private struct HistoryRowView: View {
    let entry: HistoryEntry
    let favicon: NSImage?
    let delete: () -> Void

    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 10) {
            FaviconView(image: favicon, size: 16)
            VStack(alignment: .leading, spacing: 1) {
                Text(entry.displayTitle)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Text(URLInput.host(of: entry.url) ?? entry.url)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            Text(entry.lastVisit, format: .relative(presentation: .named))
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
            Button(action: delete) {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.secondary)
                    .frame(width: 16, height: 16)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .glassTooltip("Delete from History")
            .opacity(isHovered ? 1 : 0)
        }
        .padding(.vertical, 3)
        .onHover { isHovered = $0 }
    }
}
