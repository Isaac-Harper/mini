import Darwin
import Foundation
import MiniRules

struct LocalServer: Identifiable, Equatable, Sendable {
    let port: Int
    let processName: String

    var id: Int { port }
    var address: String { "http://localhost:\(port)" }
    var title: String { processName.isEmpty ? "localhost \u{00B7} \(port)" : "\(processName) \u{00B7} \(port)" }
}

@MainActor
final class LocalServerScanner {
    private(set) var servers: [LocalServer] = []
    var onChange: (() -> Void)?
    private var scannedAt: Date?
    private var isScanning = false

    private static let cacheLifetime: TimeInterval = 5
    nonisolated private static let probeTimeout: TimeInterval = 0.6

    func refreshIfStale() {
        guard !isScanning, scannedAt.map({ Date().timeIntervalSince($0) > Self.cacheLifetime }) ?? true else { return }
        isScanning = true
        Task.detached(priority: .utility) {
            let listeners = Self.userListeners()
            let servers = await Self.httpServers(among: listeners)
            await MainActor.run { [weak self] in
                guard let self else { return }
                self.isScanning = false
                self.scannedAt = Date()
                guard servers != self.servers else { return }
                self.servers = servers
                self.onChange?()
            }
        }
    }

    nonisolated private static func userListeners() -> [LocalListener] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/lsof")
        process.arguments = ["-nP", "-a", "-iTCP", "-sTCP:LISTEN", "-u", String(getuid()), "-F", "pcn", "+c", "0"]
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            return []
        }
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        let ownIdentifier = getpid()
        return LocalDevelopment.listeners(fromLsofFields: String(decoding: data, as: UTF8.self)).filter { listener in
            listener.processIdentifier != ownIdentifier && isDevelopmentTool(executablePath(of: listener.processIdentifier))
        }
    }

    nonisolated private static func executablePath(of processIdentifier: Int32) -> String {
        var buffer = [CChar](repeating: 0, count: Int(MAXPATHLEN) * 4)
        let length = proc_pidpath(processIdentifier, &buffer, UInt32(buffer.count))
        guard length > 0 else { return "" }
        return String(decoding: buffer.prefix(Int(length)).map { UInt8(bitPattern: $0) }, as: UTF8.self)
    }

    nonisolated private static func isDevelopmentTool(_ path: String) -> Bool {
        guard !path.isEmpty, !["/System/", "/usr/libexec/", "/usr/sbin/", "/sbin/"].contains(where: path.hasPrefix) else { return false }
        let applicationFolders = ["/Applications/", FileManager.default.homeDirectoryForCurrentUser.path + "/Applications/"]
        guard let folder = applicationFolders.first(where: path.hasPrefix) else { return true }
        let isInstalledApp = path.dropFirst(folder.count).split(separator: "/").first?.hasSuffix(".app") == true
        return !isInstalledApp || path.contains(".app/Contents/Developer/")
    }

    nonisolated private static func httpServers(among listeners: [LocalListener]) async -> [LocalServer] {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = probeTimeout
        configuration.httpCookieStorage = nil
        configuration.urlCache = nil
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        return await withTaskGroup(of: LocalServer?.self) { group in
            for listener in listeners {
                group.addTask {
                    await answersHTTP(port: listener.port, session: session) ? LocalServer(port: listener.port, processName: listener.command) : nil
                }
            }
            var servers: [LocalServer] = []
            for await server in group {
                if let server { servers.append(server) }
            }
            return servers.sorted { $0.port < $1.port }
        }
    }

    nonisolated static func answersHTTP(port: Int, session: URLSession) async -> Bool {
        guard let url = URL(string: "http://localhost:\(port)/") else { return false }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: probeTimeout)
        request.httpMethod = "HEAD"
        guard let (_, response) = try? await session.data(for: request) else { return false }
        return response is HTTPURLResponse
    }
}
