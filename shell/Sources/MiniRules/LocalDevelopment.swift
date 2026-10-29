import Foundation

public struct LocalListener: Equatable, Sendable {
    public let processIdentifier: Int32
    public let command: String
    public let port: Int

    public init(processIdentifier: Int32, command: String, port: Int) {
        self.processIdentifier = processIdentifier
        self.command = command
        self.port = port
    }
}

public enum LocalDevelopment {
    public static let connectionRefusedError: Int32 = -102

    public static func isLocalHost(_ rawHost: String) -> Bool {
        let host = rawHost.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
        return host == "localhost" || host.hasSuffix(".localhost") || host == "::1" || isLoopbackAddress(host)
    }

    public static func port(ofLocalAddress address: String) -> Int? {
        guard let components = URLComponents(string: address), let scheme = components.scheme?.lowercased(), ["http", "https"].contains(scheme),
              let host = components.host, isLocalHost(host) else { return nil }
        return components.port ?? (scheme == "https" ? 443 : 80)
    }

    public static func listeners(fromLsofFields output: String) -> [LocalListener] {
        var listeners: [LocalListener] = []
        var processIdentifier: Int32?
        var command = ""
        for line in output.split(separator: "\n") {
            guard let field = line.first else { continue }
            let value = String(line.dropFirst())
            switch field {
            case "p":
                processIdentifier = Int32(value)
                command = ""
            case "c":
                command = value
            case "n":
                guard let processIdentifier, let separator = value.lastIndex(of: ":"), let port = Int(value[value.index(after: separator)...]),
                      (1...65_535).contains(port), isReachableFromLoopback(String(value[..<separator])),
                      !listeners.contains(where: { $0.port == port }) else { continue }
                listeners.append(LocalListener(processIdentifier: processIdentifier, command: command, port: port))
            default:
                continue
            }
        }
        return listeners.sorted { $0.port < $1.port }
    }

    public static func portShortcut(_ rawQuery: String, listeningPorts: Set<Int>) -> Int? {
        let query = rawQuery.trimmingCharacters(in: .whitespaces)
        if query.hasPrefix(":"), let port = Int(query.dropFirst()), (1...65_535).contains(port), query.dropFirst().allSatisfy(\.isNumber) {
            return port
        }
        guard query.allSatisfy(\.isNumber), let port = Int(query), listeningPorts.contains(port) else { return nil }
        return port
    }

    public static func retryDelays(totalSeconds: Double) -> [Double] {
        var delays: [Double] = []
        var next = 0.25
        var elapsed = 0.0
        while elapsed + next <= totalSeconds {
            delays.append(next)
            elapsed += next
            next = min(next * 2, 4)
        }
        return delays
    }

    private static func isLoopbackAddress(_ host: String) -> Bool {
        let parts = host.split(separator: ".", omittingEmptySubsequences: false)
        return parts.count == 4 && parts[0] == "127" && parts.allSatisfy { part in Int(part).map { (0...255).contains($0) } ?? false }
    }

    private static func isReachableFromLoopback(_ address: String) -> Bool {
        let host = address.trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
        return host == "*" || host == "0.0.0.0" || host == "::" || host == "::1" || host == "localhost" || isLoopbackAddress(host)
    }
}
