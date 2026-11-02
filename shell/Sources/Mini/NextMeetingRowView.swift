import MiniRules
import SwiftUI

struct NextMeetingRowView: View {
    let shell: ShellController
    let row: NextMeetingRow

    var body: some View {
        HStack(spacing: SidebarMetrics.iconSpacing) {
            switch row {
            case .accessNeeded:
                Image(systemName: "calendar")
                    .font(InterfaceFont.rowSymbol)
                    .frame(width: SidebarMetrics.iconSize)
                Text("Allow Calendar Access")
                    .lineLimit(1)
                Spacer(minLength: 0)
            case .meeting(let event, let calendarColor):
                Circle()
                    .fill(Color(nsColor: calendarColor))
                    .frame(width: SidebarMetrics.calendarDotSize, height: SidebarMetrics.calendarDotSize)
                    .frame(width: SidebarMetrics.iconSize)
                Text(event.title)
                    .foregroundStyle(.primary)
                    .fadingTruncation()
                Spacer(minLength: 0)
                TimelineView(.everyMinute) { context in
                    Text(NextMeeting.timeText(for: event, now: context.date))
                        .monospacedDigit()
                        .lineLimit(1)
                        .fixedSize()
                        .foregroundStyle(NextMeeting.isEmphasized(event, now: context.date) ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                }
                if let link = event.conferenceLink {
                    joinButton(link)
                }
            }
        }
        .foregroundStyle(.secondary)
        .padding(.horizontal, SidebarMetrics.footerRowPadding)
        .frame(height: SidebarMetrics.rowHeight)
        .hoverHighlight()
        .contentShape(Rectangle())
        .glassTooltip(tooltip)
        .onTapGesture {
            Haptics.controlActivated(.press)
            switch row {
            case .accessNeeded: shell.nextMeeting.openPrivacySettings()
            case .meeting(let event, _): shell.nextMeeting.showInCalendar(event)
            }
        }
        .transition(.opacity)
    }

    private var tooltip: String {
        switch row {
        case .accessNeeded:
            return "Open Privacy & Security to let Mini read your calendars"
        case .meeting(let event, _):
            let start = event.start.formatted(date: .omitted, time: .shortened)
            let end = event.end.formatted(date: .omitted, time: .shortened)
            return "\(start) to \(end), \(event.calendarTitle)"
        }
    }

    private func joinButton(_ link: URL) -> some View {
        Button {
            shell.openExternalURL(link)
        } label: {
            Image(systemName: "video.fill")
                .font(InterfaceFont.accessorySymbol)
                .foregroundStyle(.secondary)
                .frame(width: SidebarMetrics.accessorySize, height: SidebarMetrics.accessorySize)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focusable(false)
        .hapticFeedback(.press)
        .glassTooltip("Join Call")
    }
}
