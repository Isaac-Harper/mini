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
        case running(HarvestRunningTimer, todaySeconds: Double)
        case stopped(last: HarvestEntry?, lastSeconds: Double, todaySeconds: Double)
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

    public static func presentation(url: String, timesheet: HarvestTimesheet?, shownSeconds: [UInt64: Double] = [:]) -> Presentation {
        if isSignIn(url) { return .signedOut }
        guard isHarvest(url), let timesheet else { return .idle }
        guard timesheet.signedIn else { return .signedOut }
        let todaySeconds = timesheet.entries.reduce(0) { $0 + $1.hours * 3600 }
        if let timer = runningTimer(in: timesheet, shownSeconds: shownSeconds) { return .running(timer, todaySeconds: todaySeconds) }
        let last = lastEntry(in: timesheet.entries)
        let lastSeconds = last.map { reconciled(reported: $0.hours * 3600, shown: shownSeconds[$0.id]) } ?? 0
        return .stopped(last: last, lastSeconds: lastSeconds, todaySeconds: todaySeconds)
    }

    public static func runningTimer(in timesheet: HarvestTimesheet, shownSeconds: [UInt64: Double] = [:]) -> HarvestRunningTimer? {
        for entry in timesheet.entries {
            guard let started = entry.timerStartedAt, let startedAt = try? Date(started, strategy: .iso8601) else { continue }
            let runSecondsAtFetch = max(0, timesheet.fetchDate.timeIntervalSince(startedAt))
            let reportedPrior = max(0, entry.hours * 3600 - runSecondsAtFetch)
            let shownPrior = shownSeconds[entry.id].map { $0 - runSecondsAtFetch }
            return HarvestRunningTimer(entry: entry, startedAt: startedAt, priorSeconds: reconciled(reported: reportedPrior, shown: shownPrior))
        }
        return nil
    }

    public static func seconds(of entry: HarvestEntry, in timesheet: HarvestTimesheet, shownSeconds: [UInt64: Double], at date: Date) -> Double {
        if let timer = runningTimer(in: timesheet, shownSeconds: shownSeconds), timer.entry.id == entry.id {
            return timer.elapsedSeconds(at: date)
        }
        return reconciled(reported: entry.hours * 3600, shown: shownSeconds[entry.id])
    }

    public static let reportedRounding: Double = 36

    public static func reconciled(reported: Double, shown: Double?) -> Double {
        guard let shown, abs(reported - shown) <= reportedRounding else { return reported }
        return max(0, shown)
    }

    public static func carriedSeconds(from previous: HarvestTimesheet?, shownSeconds: [UInt64: Double], into next: HarvestTimesheet) -> [UInt64: Double] {
        guard let previous else { return [:] }
        let nextIdentifiers = Set(next.entries.map(\.id))
        var carried: [UInt64: Double] = [:]
        for entry in previous.entries where nextIdentifiers.contains(entry.id) {
            carried[entry.id] = seconds(of: entry, in: previous, shownSeconds: shownSeconds, at: next.fetchDate)
        }
        return carried
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
