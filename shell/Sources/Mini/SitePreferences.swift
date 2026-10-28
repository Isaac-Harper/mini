import CMiniCore
import Foundation

@MainActor
final class SitePreferences {
    struct PermissionDecision: Codable {
        var allowed: UInt32 = 0
        var denied: UInt32 = 0
    }

    private var permissionDecisions: [String: PermissionDecision]
    private var adBlockExemptHosts: Set<String>
    private var zoomLevels: [String: Double]
    private let zoomLevelsFileURL: URL
    private let permissionsFileURL: URL
    private let adBlockExemptionsFileURL: URL

    init(directory: URL) {
        permissionsFileURL = directory.appendingPathComponent("permissions.json")
        adBlockExemptionsFileURL = directory.appendingPathComponent("adblock-exempt.json")
        permissionDecisions = Self.load([String: PermissionDecision].self, from: permissionsFileURL) ?? [:]
        adBlockExemptHosts = Self.load(Set<String>.self, from: adBlockExemptionsFileURL) ?? []
        zoomLevelsFileURL = directory.appendingPathComponent("zoom-levels.json")
        zoomLevels = Self.load([String: Double].self, from: zoomLevelsFileURL) ?? [:]
    }

    static func origin(of address: String) -> String? {
        guard let components = URLComponents(string: address),
              let scheme = components.scheme?.lowercased(),
              let host = components.host?.lowercased(), !host.isEmpty
        else { return nil }
        let port = components.port.map { ":\($0)" } ?? ""
        return "\(scheme)://\(host)\(port)"
    }

    static func host(of address: String) -> String? {
        guard let host = URLComponents(string: address)?.host?.lowercased(), !host.isEmpty else { return nil }
        return host
    }

    func rememberedGrant(origin: String, permissions: UInt32) -> UInt32? {
        guard let key = Self.origin(of: origin), let decision = permissionDecisions[key],
              (decision.allowed | decision.denied) & permissions == permissions
        else { return nil }
        return decision.allowed & permissions
    }

    var onNotificationsGranted: (() -> Void)?

    private static let notificationsBit = MINI_PERMISSION_NOTIFICATIONS.rawValue

    func notificationPermission(forSiteAt address: String) -> MiniNotificationPermission {
        guard let key = Self.origin(of: address), let decision = permissionDecisions[key] else { return MINI_NOTIFICATION_DEFAULT }
        if decision.allowed & Self.notificationsBit != 0 { return MINI_NOTIFICATION_GRANTED }
        if decision.denied & Self.notificationsBit != 0 { return MINI_NOTIFICATION_DENIED }
        return MINI_NOTIFICATION_DEFAULT
    }

    func pushNotificationPermissions() {
        for key in permissionDecisions.keys {
            pushNotificationPermission(origin: key)
        }
    }

    private func pushNotificationPermission(origin key: String) {
        let state = notificationPermission(forSiteAt: key)
        key.withCString { mini_set_notification_permission($0, Int32(state.rawValue)) }
    }

    func remember(origin: String, permissions: UInt32, allowed: Bool) {
        guard let key = Self.origin(of: origin) else { return }
        defer {
            if permissions & Self.notificationsBit != 0 {
                pushNotificationPermission(origin: key)
                if allowed { onNotificationsGranted?() }
            }
        }
        var decision = permissionDecisions[key] ?? PermissionDecision()
        if allowed {
            decision.allowed |= permissions
            decision.denied &= ~permissions
        } else {
            decision.denied |= permissions
            decision.allowed &= ~permissions
        }
        permissionDecisions[key] = decision
        Self.save(permissionDecisions, to: permissionsFileURL)
    }

    func hasPermissionDecisions(forSiteAt address: String) -> Bool {
        Self.origin(of: address).map { permissionDecisions[$0] != nil } ?? false
    }

    func resetPermissions(forSiteAt address: String) {
        guard let key = Self.origin(of: address), permissionDecisions.removeValue(forKey: key) != nil else { return }
        Self.save(permissionDecisions, to: permissionsFileURL)
        pushNotificationPermission(origin: key)
    }

    func zoomLevel(host: String) -> Double {
        zoomLevels[host] ?? 0
    }

    func setZoomLevel(_ level: Double?, host: String) {
        if let level, level != 0 {
            zoomLevels[host] = level
        } else {
            zoomLevels.removeValue(forKey: host)
        }
        Self.save(zoomLevels, to: zoomLevelsFileURL)
    }

    func isAdBlockExempt(host: String) -> Bool {
        adBlockExemptHosts.contains(host)
    }

    func setAdBlockExempt(host: String, exempt: Bool) {
        if exempt {
            adBlockExemptHosts.insert(host)
        } else {
            adBlockExemptHosts.remove(host)
        }
        Self.save(adBlockExemptHosts.sorted(), to: adBlockExemptionsFileURL)
        host.withCString { mini_adblock_set_host_exempt($0, exempt) }
    }

    func pushAdBlockExemptions() {
        for host in adBlockExemptHosts {
            host.withCString { mini_adblock_set_host_exempt($0, true) }
        }
    }

    private static func load<Value: Decodable>(_ type: Value.Type, from fileURL: URL) -> Value? {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }
        do {
            return try JSONDecoder().decode(type, from: Data(contentsOf: fileURL))
        } catch {
            NSLog("Mini: ignoring unreadable %@: %@", fileURL.path, String(describing: error))
            return nil
        }
    }

    private static func save<Value: Encodable>(_ value: Value, to fileURL: URL) {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(value).write(to: fileURL, options: .atomic)
        } catch {
            fatalError("Could not write \(fileURL.path): \(error)")
        }
    }
}
