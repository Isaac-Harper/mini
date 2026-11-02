import AppKit
import EventKit
import MiniRules
import Observation

enum NextMeetingRow: Equatable {
    case accessNeeded
    case meeting(MeetingEvent, calendarColor: NSColor)
}

@MainActor
@Observable
final class NextMeetingService {
    private(set) var row: NextMeetingRow?

    var isEnabled = UserDefaults.standard.bool(forKey: NextMeetingService.enabledKey) {
        didSet {
            UserDefaults.standard.set(isEnabled, forKey: Self.enabledKey)
            isEnabled ? start() : stop()
        }
    }

    @ObservationIgnored private let eventStore = EKEventStore()
    @ObservationIgnored private var refreshTimer: Timer?
    @ObservationIgnored private var observers: [NSObjectProtocol] = []

    private static let enabledKey = "ShowsNextMeeting"
    private static let fetchHorizon: TimeInterval = 24 * 60 * 60
    private static let longestRefreshWait: TimeInterval = 6 * 60 * 60
    private static let privacySettings = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars")!

    func startIfEnabled() {
        if isEnabled { start() }
    }

    func openPrivacySettings() {
        NSWorkspace.shared.open(Self.privacySettings)
    }

    func showInCalendar(_ event: MeetingEvent) {
        if let encoded = event.identifier.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
           let url = URL(string: "ical://ekevent/\(encoded)?method=show&options=more"),
           NSWorkspace.shared.open(url) {
            return
        }
        NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Calendar.app"))
    }

    private func start() {
        guard observers.isEmpty else { return }
        observers = [
            NotificationCenter.default.addObserver(forName: .EKEventStoreChanged, object: eventStore, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.refresh() }
            },
            NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.refresh() }
            },
            NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.refresh() }
            },
            NotificationCenter.default.addObserver(forName: .NSSystemClockDidChange, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.refresh() }
            },
        ]
        switch EKEventStore.authorizationStatus(for: .event) {
        case .notDetermined:
            eventStore.requestFullAccessToEvents { [weak self] _, _ in
                Task { @MainActor in
                    guard let self, self.isEnabled else { return }
                    self.refresh()
                }
            }
        default:
            refresh()
        }
    }

    private func stop() {
        for observer in observers {
            NotificationCenter.default.removeObserver(observer)
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
        observers = []
        refreshTimer?.invalidate()
        refreshTimer = nil
        row = nil
    }

    private func refresh() {
        refreshTimer?.invalidate()
        refreshTimer = nil
        guard isEnabled else { return }
        switch EKEventStore.authorizationStatus(for: .event) {
        case .fullAccess:
            break
        case .notDetermined:
            row = nil
            return
        default:
            row = .accessNeeded
            return
        }
        let now = Date()
        let predicate = eventStore.predicateForEvents(withStart: now.addingTimeInterval(-Self.fetchHorizon), end: now.addingTimeInterval(Self.fetchHorizon), calendars: nil)
        let events = eventStore.events(matching: predicate)
        let meetings = events.map(Self.meeting(from:))
        let colors = Dictionary(events.map { ($0.calendar.calendarIdentifier, $0.calendar.color ?? .secondaryLabelColor) }) { first, _ in first }
        if let meeting = NextMeeting.select(meetings, now: now) {
            row = .meeting(meeting, calendarColor: colors[meeting.calendarIdentifier] ?? .secondaryLabelColor)
        } else {
            row = nil
        }
        let nextRefresh = min(NextMeeting.nextChange(meetings, now: now) ?? .distantFuture, now.addingTimeInterval(Self.longestRefreshWait))
        let timer = Timer(fire: nextRefresh, interval: 0, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        timer.tolerance = 1
        RunLoop.main.add(timer, forMode: .common)
        refreshTimer = timer
    }

    private static func meeting(from event: EKEvent) -> MeetingEvent {
        let isDeclined = event.attendees?.contains { $0.isCurrentUser && $0.participantStatus == .declined } ?? false
        return MeetingEvent(
            identifier: event.eventIdentifier ?? "",
            title: event.title ?? "",
            calendarIdentifier: event.calendar.calendarIdentifier,
            calendarTitle: event.calendar.title,
            start: event.startDate,
            end: event.endDate,
            isAllDay: event.isAllDay,
            isDeclined: isDeclined,
            conferenceLink: NextMeeting.conferenceLink(url: event.url?.absoluteString, location: event.location, notes: event.notes)
        )
    }
}
