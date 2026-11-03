import AppKit
import CMiniCore
import MiniRules
import Observation

@MainActor
@Observable
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
    private var alwaysOpenedSchemes: [String: Set<String>]
    private let externalApplicationsFileURL: URL

    init(directory: URL) {
        externalApplicationsFileURL = directory.appendingPathComponent("external-apps.json")
        alwaysOpenedSchemes = Self.load([String: Set<String>].self, from: externalApplicationsFileURL) ?? [:]
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

    @ObservationIgnored var onNotificationsGranted: (() -> Void)?

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

    func alwaysOpens(scheme: String, origin: String) -> Bool {
        guard let key = ExternalApplicationLinks.rememberableOrigin(origin) else { return false }
        return alwaysOpenedSchemes[key]?.contains(scheme) == true
    }

    func rememberAlwaysOpens(scheme: String, origin: String) {
        guard let key = ExternalApplicationLinks.rememberableOrigin(origin) else { return }
        alwaysOpenedSchemes[key, default: []].insert(scheme)
        Self.save(alwaysOpenedSchemes, to: externalApplicationsFileURL)
    }

    func forgetExternalApplications(forSiteAt address: String) {
        guard let key = ExternalApplicationLinks.rememberableOrigin(address), alwaysOpenedSchemes.removeValue(forKey: key) != nil else { return }
        Self.save(alwaysOpenedSchemes, to: externalApplicationsFileURL)
    }

    static func application(forScheme scheme: String) -> URL? {
        guard let probe = URL(string: "\(scheme):") else { return nil }
        return NSWorkspace.shared.urlForApplication(toOpen: probe)
    }

    static func applicationName(at applicationURL: URL) -> String {
        ExternalApplicationLinks.applicationName(fromBundleFileName: FileManager.default.displayName(atPath: applicationURL.path))
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

    private static let permissionKinds = [
        SitePermissionKind(bit: MINI_PERMISSION_CAMERA.rawValue, name: "Camera"),
        SitePermissionKind(bit: MINI_PERMISSION_MICROPHONE.rawValue, name: "Microphone"),
        SitePermissionKind(bit: MINI_PERMISSION_SCREEN_CAPTURE.rawValue, name: "Screen sharing"),
        SitePermissionKind(bit: MINI_PERMISSION_GEOLOCATION.rawValue, name: "Location"),
        SitePermissionKind(bit: MINI_PERMISSION_NOTIFICATIONS.rawValue, name: "Notifications", isNotifications: true),
        SitePermissionKind(bit: MINI_PERMISSION_CLIPBOARD.rawValue, name: "Clipboard"),
        SitePermissionKind(bit: MINI_PERMISSION_MIDI.rawValue, name: "MIDI devices"),
        SitePermissionKind(bit: MINI_PERMISSION_STORAGE.rawValue, name: "Storage"),
        SitePermissionKind(bit: MINI_PERMISSION_WINDOW_MANAGEMENT.rawValue, name: "Window management"),
        SitePermissionKind(bit: MINI_PERMISSION_LOCAL_NETWORK.rawValue, name: "Local network"),
        SitePermissionKind(bit: MINI_PERMISSION_OTHER.rawValue, name: "Other features"),
    ]

    var storedSites: [StoredSite] {
        StoredSites.sites(
            permissionDecisions: permissionDecisions.mapValues { StoredPermissionDecision(allowed: $0.allowed, denied: $0.denied) },
            adBlockExemptHosts: adBlockExemptHosts,
            zoomLevels: zoomLevels,
            alwaysOpenedSchemes: alwaysOpenedSchemes,
            applicationNames: Dictionary(uniqueKeysWithValues: Set(alwaysOpenedSchemes.values.joined()).compactMap { scheme in
                Self.application(forScheme: scheme).map { (scheme, Self.applicationName(at: $0)) }
            }),
            kinds: Self.permissionKinds
        )
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
