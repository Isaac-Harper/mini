import Foundation

public enum DevBuildEvent: Equatable, Sendable {
    case rebuilding
    case ready(milliseconds: Double?)
    case compileErrorShown(detail: String)
    case compileErrorCleared
}

public struct DevBuildStatus: Equatable, Sendable {
    public static let rebuildTimeout: TimeInterval = 10
    public static let detailLimit = 80

    public private(set) var rebuildingSince: Date?
    public private(set) var compileError: String?

    public init() {}

    public var isRebuilding: Bool { rebuildingSince != nil }

    public var hasCompileError: Bool { compileError != nil }

    public var compileErrorDetail: String? {
        guard let compileError else { return nil }
        let line = PageHealth.singleLine(compileError)
        return line.isEmpty ? nil : PageHealth.tailTruncated(line, limit: Self.detailLimit)
    }

    public mutating func apply(_ event: DevBuildEvent, at date: Date) {
        switch event {
        case .rebuilding:
            rebuildingSince = date
        case .ready:
            rebuildingSince = nil
            compileError = nil
        case let .compileErrorShown(detail):
            rebuildingSince = nil
            compileError = detail
        case .compileErrorCleared:
            compileError = nil
        }
    }

    public func rebuildExpiry() -> Date? {
        rebuildingSince.map { $0.addingTimeInterval(Self.rebuildTimeout) }
    }

    public mutating func expireRebuild(at date: Date) {
        guard let expiry = rebuildExpiry(), date >= expiry else { return }
        rebuildingSince = nil
    }

    public static func refreshLabel(milliseconds: Double) -> String {
        "refresh \(DurationText.milliseconds(milliseconds))"
    }
}
