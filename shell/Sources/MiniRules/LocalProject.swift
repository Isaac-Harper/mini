import Foundation

public struct LocalProject: Equatable, Sendable {
    public let name: String
    public let root: String
    public let branch: String?

    public init(name: String, root: String, branch: String?) {
        self.name = name
        self.root = root
        self.branch = branch
    }

    public func serverDescription(port: Int) -> String {
        branch.map { "\(name) on \($0), port \(String(port))" } ?? "\(name), port \(String(port))"
    }
}

public enum LocalFileKind: Sendable {
    case directory
    case file
}

public enum LocalProjectResolution {
    public static func project(workingDirectory: String, homeDirectory: String, kind: (String) -> LocalFileKind?,
                               read: (String) -> String?) -> LocalProject? {
        let directory = standardized(workingDirectory)
        guard let root = repositoryRoot(containing: directory, homeDirectory: homeDirectory, kind: kind) else {
            guard directory != "/", directory != standardized(homeDirectory) else { return nil }
            return LocalProject(name: lastComponent(of: directory), root: directory, branch: nil)
        }
        let gitPath = root + "/.git"
        let gitDirectory: String? = switch kind(gitPath) {
        case .directory: gitPath
        case .file: read(gitPath).flatMap { gitDirectory(fromGitFile: $0, in: root) }
        case nil: nil
        }
        let branch = gitDirectory.flatMap { read($0 + "/HEAD") }.flatMap(branch(fromHead:))
        let mainRepository = gitDirectory.flatMap { directory in
            read(directory + "/commondir").flatMap { mainRepositoryRoot(fromCommonDirectory: $0, gitDirectory: directory) }
        }
        return LocalProject(name: lastComponent(of: mainRepository ?? root), root: root, branch: branch)
    }

    public static func repositoryRoot(containing directory: String, homeDirectory: String, kind: (String) -> LocalFileKind?) -> String? {
        let home = standardized(homeDirectory)
        var current = standardized(directory)
        while current != "/", current != home {
            if kind(current + "/.git") != nil { return current }
            current = parent(of: current)
        }
        return nil
    }

    public static func branch(fromHead contents: String) -> String? {
        let head = contents.trimmingCharacters(in: .whitespacesAndNewlines)
        if head.hasPrefix("ref:") {
            let reference = head.dropFirst(4).trimmingCharacters(in: .whitespaces)
            let branch = reference.hasPrefix("refs/heads/") ? String(reference.dropFirst("refs/heads/".count)) : reference
            return branch.isEmpty ? nil : branch
        }
        guard head.count >= 7, head.allSatisfy(\.isHexDigit) else { return nil }
        return String(head.prefix(7))
    }

    public static func gitDirectory(fromGitFile contents: String, in directory: String) -> String? {
        guard let line = contents.split(whereSeparator: \.isNewline).first(where: { $0.hasPrefix("gitdir:") }) else { return nil }
        let path = line.dropFirst("gitdir:".count).trimmingCharacters(in: .whitespaces)
        guard !path.isEmpty else { return nil }
        return standardized(path.hasPrefix("/") ? path : directory + "/" + path)
    }

    private static func mainRepositoryRoot(fromCommonDirectory contents: String, gitDirectory: String) -> String? {
        let path = contents.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !path.isEmpty else { return nil }
        let commonDirectory = standardized(path.hasPrefix("/") ? path : gitDirectory + "/" + path)
        guard lastComponent(of: commonDirectory) == ".git" else { return nil }
        return parent(of: commonDirectory)
    }

    private static func standardized(_ path: String) -> String {
        let standardized = (path as NSString).standardizingPath
        return standardized.isEmpty ? "/" : standardized
    }

    private static func parent(of path: String) -> String {
        (path as NSString).deletingLastPathComponent
    }

    private static func lastComponent(of path: String) -> String {
        (path as NSString).lastPathComponent
    }
}
