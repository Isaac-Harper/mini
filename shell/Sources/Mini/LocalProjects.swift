import AppKit
import Darwin
import Foundation
import MiniRules

struct LocalProjectBinding: Equatable {
    let port: Int
    let project: LocalProject
}

struct LocalProjectServer {
    let listener: LocalListener
    let project: LocalProject?
}

struct ProjectEditor {
    let name: String
    let bundleIdentifier: String

    static let preferred = [
        ProjectEditor(name: "Zed", bundleIdentifier: "dev.zed.Zed"),
        ProjectEditor(name: "Cursor", bundleIdentifier: "com.todesktop.230313mzl4w4u92"),
        ProjectEditor(name: "Visual Studio Code", bundleIdentifier: "com.microsoft.VSCode"),
        ProjectEditor(name: "Sublime Text", bundleIdentifier: "com.sublimetext.4"),
        ProjectEditor(name: "Xcode", bundleIdentifier: "com.apple.dt.Xcode"),
    ]

    static func firstInstalled() -> (editor: ProjectEditor, application: URL)? {
        for editor in preferred {
            if let application = NSWorkspace.shared.urlForApplication(withBundleIdentifier: editor.bundleIdentifier) {
                return (editor, application)
            }
        }
        return nil
    }
}

@MainActor
final class LocalProjectResolver {
    private struct CachedProject {
        let project: LocalProject?
        let resolvedAt: Date
    }

    private var cache: [Int32: CachedProject] = [:]
    private static let cacheLifetime: TimeInterval = 5

    func servers() async -> [LocalProjectServer] {
        let listeners = await Task.detached(priority: .utility) { LocalServerScanner.userListeners() }.value
        var servers: [LocalProjectServer] = []
        for listener in listeners {
            servers.append(LocalProjectServer(listener: listener, project: await project(ofProcess: listener.processIdentifier)))
        }
        cache = cache.filter { entry in listeners.contains { $0.processIdentifier == entry.key } }
        return servers
    }

    private func project(ofProcess processIdentifier: Int32) async -> LocalProject? {
        if let cached = cache[processIdentifier], Date().timeIntervalSince(cached.resolvedAt) < Self.cacheLifetime {
            return cached.project
        }
        let project = await Task.detached(priority: .utility) { Self.resolveProject(ofProcess: processIdentifier) }.value
        cache[processIdentifier] = CachedProject(project: project, resolvedAt: Date())
        return project
    }

    nonisolated private static func resolveProject(ofProcess processIdentifier: Int32) -> LocalProject? {
        guard let workingDirectory = workingDirectory(ofProcess: processIdentifier) else { return nil }
        let fileManager = FileManager.default
        return LocalProjectResolution.project(
            workingDirectory: workingDirectory,
            homeDirectory: fileManager.homeDirectoryForCurrentUser.path,
            kind: { path in
                var isDirectory: ObjCBool = false
                guard fileManager.fileExists(atPath: path, isDirectory: &isDirectory) else { return nil }
                return isDirectory.boolValue ? .directory : .file
            },
            read: { path in try? String(contentsOfFile: path, encoding: .utf8) }
        )
    }

    nonisolated private static func workingDirectory(ofProcess processIdentifier: Int32) -> String? {
        var information = proc_vnodepathinfo()
        let size = Int32(MemoryLayout<proc_vnodepathinfo>.size)
        guard proc_pidinfo(processIdentifier, PROC_PIDVNODEPATHINFO, 0, &information, size) == size else { return nil }
        let path = withUnsafeBytes(of: information.pvi_cdir.vip_path) { buffer in
            String(decoding: buffer.prefix { $0 != 0 }, as: UTF8.self)
        }
        return path.isEmpty ? nil : path
    }
}

extension Tab {
    func localProject(onPort port: Int) -> LocalProject? {
        localProject.flatMap { $0.port == port ? $0.project : nil }
    }
}

extension ShellController {
    func refreshLocalProject(of tab: Tab) {
        guard let port = LocalDevelopment.port(ofLocalAddress: tab.url) else {
            if tab.localProject != nil { tab.localProject = nil }
            return
        }
        Task { [weak self, weak tab] in
            guard let servers = await self?.localProjects.servers(), let tab, LocalDevelopment.port(ofLocalAddress: tab.url) == port else { return }
            guard let server = servers.first(where: { $0.listener.port == port }) else {
                if tab.localProject?.port != port { tab.localProject = nil }
                return
            }
            let binding = server.project.map { LocalProjectBinding(port: port, project: $0) }
            if tab.localProject != binding { tab.localProject = binding }
        }
    }

    func movedServerPort(ofProjectAt root: String, from port: Int, session: URLSession) async -> Int? {
        let candidates = await localProjects.servers().filter { $0.listener.port != port && $0.project?.root == root }
        for candidate in candidates where await LocalServerScanner.answersHTTP(port: candidate.listener.port, session: session) {
            return candidate.listener.port
        }
        return nil
    }

    @objc func revealLocalProject(_ sender: NSMenuItem) {
        guard let root = sender.representedObject as? String else { return }
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: root, isDirectory: true)])
    }

    @objc func openLocalProjectInEditor(_ sender: NSMenuItem) {
        guard let root = sender.representedObject as? String, let (_, application) = ProjectEditor.firstInstalled() else { return }
        NSWorkspace.shared.open([URL(fileURLWithPath: root, isDirectory: true)], withApplicationAt: application, configuration: NSWorkspace.OpenConfiguration())
    }
}
