import AppKit
import CMiniCore
import Observation
import SwiftUI

struct DownloadProgress: Identifiable, Equatable {
    let id: UInt32
    var fileName: String
    var path: String
    var receivedBytes: Int64
    var totalBytes: Int64
    var isComplete: Bool
    var isCanceled: Bool
    var finishedAt: Date? = nil

    var isActive: Bool { !isComplete && !isCanceled }

    var fractionCompleted: Double? {
        guard totalBytes > 0 else { return nil }
        return min(Double(receivedBytes) / Double(totalBytes), 1)
    }
}

@MainActor
@Observable
final class DownloadsModel {
    private(set) var visibleDownloads: [DownloadProgress] = []

    private static let finishedVisibility: TimeInterval = 10

    func update(_ progress: DownloadProgress) {
        var progress = progress
        if let index = visibleDownloads.firstIndex(where: { $0.id == progress.id }) {
            let previous = visibleDownloads[index]
            progress.finishedAt = previous.finishedAt
            if progress.fileName.isEmpty { progress.fileName = previous.fileName }
            if progress.path.isEmpty { progress.path = previous.path }
            visibleDownloads[index] = progress
        } else {
            visibleDownloads.append(progress)
        }
        guard !progress.isActive, progress.finishedAt == nil else { return }
        let identifier = progress.id
        replace(identifier) { $0.finishedAt = Date() }
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.finishedVisibility) { [weak self] in
            MainActor.assumeIsolated {
                self?.visibleDownloads.removeAll { $0.id == identifier }
            }
        }
    }

    func activate(_ download: DownloadProgress) {
        if download.isActive {
            mini_download_cancel(download.id)
        } else if download.isComplete {
            NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: download.path)])
        }
    }

    private func replace(_ identifier: UInt32, _ change: (inout DownloadProgress) -> Void) {
        guard let index = visibleDownloads.firstIndex(where: { $0.id == identifier }) else { return }
        change(&visibleDownloads[index])
    }
}

struct DownloadRowView: View {
    let download: DownloadProgress
    let activate: () -> Void


    var body: some View {
        Button(action: activate) {
            HStack(spacing: SidebarMetrics.iconSpacing) {
                Image(systemName: symbolName)
                    .font(InterfaceFont.rowSymbol)
                    .frame(width: SidebarMetrics.iconSize)
                VStack(alignment: .leading, spacing: SidebarMetrics.accessorySpacing) {
                    Text(download.fileName)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    if download.isActive {
                        if let fraction = download.fractionCompleted {
                            ProgressView(value: fraction).progressViewStyle(.linear).controlSize(.mini)
                        } else {
                            ProgressView().progressViewStyle(.linear).controlSize(.mini)
                        }
                    }
                }
                Spacer(minLength: 0)
            }
            .foregroundStyle(.secondary)
            .padding(.horizontal, SidebarMetrics.footerRowPadding)
            .padding(.vertical, SidebarMetrics.downloadVerticalPadding)
            .frame(minHeight: SidebarMetrics.rowHeight)
            .hoverHighlight()
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focusable(false)
        .hapticFeedback(.press)
        .glassTooltip(helpText)
    }

    private var symbolName: String {
        if download.isCanceled { return "xmark.circle" }
        return download.isComplete ? "checkmark.circle" : "arrow.down.circle"
    }

    private var helpText: String {
        if download.isActive { return "Cancel Download" }
        return download.isComplete ? "Show in Finder" : "Download Canceled"
    }
}
