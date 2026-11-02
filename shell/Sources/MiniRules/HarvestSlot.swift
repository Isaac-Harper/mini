import Foundation

public struct HarvestEntry: Decodable, Equatable, Sendable {
    public let id: UInt64
    public let project: String
    public let client: String
    public let task: String
    public let notes: String
    public let hours: Double
    public let timerStartedAt: String?
    public let updatedAt: String

    public init(id: UInt64, project: String, client: String, task: String, notes: String, hours: Double, timerStartedAt: String?, updatedAt: String) {
        self.id = id
        self.project = project
        self.client = client
        self.task = task
        self.notes = notes
        self.hours = hours
        self.timerStartedAt = timerStartedAt
        self.updatedAt = updatedAt
    }

    public var title: String { project.isEmpty ? notes : project }

    public var detail: String { task.isEmpty ? notes : task }
}

public struct HarvestTimesheet: Decodable, Equatable, Sendable {
    public let fetchedAt: Double
    public let signedIn: Bool
    public let entries: [HarvestEntry]

    public init(fetchedAt: Double, signedIn: Bool, entries: [HarvestEntry]) {
        self.fetchedAt = fetchedAt
        self.signedIn = signedIn
        self.entries = entries
    }

    public static func parse(_ report: String) -> HarvestTimesheet? {
        try? JSONDecoder().decode(HarvestTimesheet.self, from: Data(report.utf8))
    }

    public var fetchDate: Date { Date(timeIntervalSince1970: fetchedAt / 1000) }
}

public struct HarvestRunningTimer: Equatable, Sendable {
    public let entry: HarvestEntry
    public let startedAt: Date
    public let priorSeconds: Double

    public func elapsedSeconds(at now: Date) -> Double {
        priorSeconds + max(0, now.timeIntervalSince(startedAt))
    }
}

public enum HarvestSlot {
    public enum Presentation: Equatable, Sendable {
        case idle
        case signedOut
        case running(HarvestRunningTimer)
        case stopped(todaySeconds: Double, last: HarvestEntry?)
    }

    public static let homeURL = "https://harvestapp.com/time"

    public static func isHarvest(_ url: String) -> Bool {
        guard let host = host(of: url) else { return false }
        return host == "harvestapp.com" || host.hasSuffix(".harvestapp.com")
    }

    public static func isSignIn(_ url: String) -> Bool {
        guard let host = host(of: url) else { return false }
        return host == "getharvest.com" || host.hasSuffix(".getharvest.com")
    }

    public static func presentation(url: String, timesheet: HarvestTimesheet?) -> Presentation {
        if isSignIn(url) { return .signedOut }
        guard isHarvest(url), let timesheet else { return .idle }
        guard timesheet.signedIn else { return .signedOut }
        if let timer = runningTimer(in: timesheet) { return .running(timer) }
        let todaySeconds = timesheet.entries.reduce(0) { $0 + $1.hours * 3600 }
        return .stopped(todaySeconds: todaySeconds, last: lastEntry(in: timesheet.entries))
    }

    public static func runningTimer(in timesheet: HarvestTimesheet) -> HarvestRunningTimer? {
        for entry in timesheet.entries {
            guard let started = entry.timerStartedAt, let startedAt = try? Date(started, strategy: .iso8601) else { continue }
            let runSecondsAtFetch = max(0, timesheet.fetchDate.timeIntervalSince(startedAt))
            let priorSeconds = max(0, entry.hours * 3600 - runSecondsAtFetch)
            return HarvestRunningTimer(entry: entry, startedAt: startedAt, priorSeconds: priorSeconds)
        }
        return nil
    }

    public static func lastEntry(in entries: [HarvestEntry]) -> HarvestEntry? {
        entries.enumerated().max { first, second in
            first.element.updatedAt == second.element.updatedAt ? first.offset < second.offset : first.element.updatedAt < second.element.updatedAt
        }?.element
    }

    public static func clock(_ seconds: Double) -> String {
        let total = Int(max(0, seconds))
        return String(format: "%d:%02d:%02d", total / 3600, total / 60 % 60, total % 60)
    }

    public static func duration(_ seconds: Double) -> String {
        let minutes = Int((max(0, seconds) / 60).rounded())
        return String(format: "%d:%02d", minutes / 60, minutes % 60)
    }

    private static func host(of url: String) -> String? {
        guard let components = URLComponents(string: url), ["http", "https"].contains(components.scheme?.lowercased()),
              let host = components.host?.lowercased(), !host.isEmpty else { return nil }
        return host
    }
}
