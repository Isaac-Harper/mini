import Testing
import MiniRules

struct LocalProjectTests {
    private struct FileTree {
        var directories: Set<String> = []
        var files: [String: String] = [:]

        func kind(_ path: String) -> LocalFileKind? {
            if directories.contains(path) { return .directory }
            return files[path] == nil ? nil : .file
        }

        func project(workingDirectory: String) -> LocalProject? {
            LocalProjectResolution.project(workingDirectory: workingDirectory, homeDirectory: "/Users/me", kind: kind, read: { files[$0] })
        }
    }

    @Test func headNamesTheBranchOrTheShortHash() {
        #expect(LocalProjectResolution.branch(fromHead: "ref: refs/heads/main\n") == "main")
        #expect(LocalProjectResolution.branch(fromHead: "ref: refs/heads/feat/nav\n") == "feat/nav")
        #expect(LocalProjectResolution.branch(fromHead: "ref: refs/remotes/origin/main") == "refs/remotes/origin/main")
        #expect(LocalProjectResolution.branch(fromHead: "6a1fd78c0a9e2b4d5f6a7b8c9d0e1f2a3b4c5d6e\n") == "6a1fd78")
        #expect(LocalProjectResolution.branch(fromHead: "ref: ") == nil)
        #expect(LocalProjectResolution.branch(fromHead: "") == nil)
        #expect(LocalProjectResolution.branch(fromHead: "not a head") == nil)
    }

    @Test func gitFilePointsAtAbsoluteOrRelativeGitDirectory() {
        #expect(LocalProjectResolution.gitDirectory(fromGitFile: "gitdir: /Users/me/mini/.git/worktrees/nav\n", in: "/Users/me/nav")
            == "/Users/me/mini/.git/worktrees/nav")
        #expect(LocalProjectResolution.gitDirectory(fromGitFile: "gitdir: ../.git/modules/ui\n", in: "/Users/me/mini/ui")
            == "/Users/me/mini/.git/modules/ui")
        #expect(LocalProjectResolution.gitDirectory(fromGitFile: "nothing here", in: "/Users/me/mini") == nil)
        #expect(LocalProjectResolution.gitDirectory(fromGitFile: "gitdir:   ", in: "/Users/me/mini") == nil)
    }

    @Test func rootWalkStopsAtTheFirstGitAndNeverAtHomeOrSlash() {
        let tree = FileTree(directories: ["/Users/me/mini/.git", "/Users/me/.git", "/.git"])
        #expect(LocalProjectResolution.repositoryRoot(containing: "/Users/me/mini/web/src", homeDirectory: "/Users/me", kind: tree.kind) == "/Users/me/mini")
        #expect(LocalProjectResolution.repositoryRoot(containing: "/Users/me/mini", homeDirectory: "/Users/me", kind: tree.kind) == "/Users/me/mini")
        #expect(LocalProjectResolution.repositoryRoot(containing: "/Users/me/scratch", homeDirectory: "/Users/me", kind: tree.kind) == nil)
        #expect(LocalProjectResolution.repositoryRoot(containing: "/tmp/site", homeDirectory: "/Users/me", kind: tree.kind) == nil)
    }

    @Test func repositoryGivesItsFolderNameAndBranch() {
        let tree = FileTree(directories: ["/Users/me/mini/.git"], files: ["/Users/me/mini/.git/HEAD": "ref: refs/heads/feat/nav\n"])
        #expect(tree.project(workingDirectory: "/Users/me/mini/web") == LocalProject(name: "mini", root: "/Users/me/mini", branch: "feat/nav"))
    }

    @Test func worktreeReadsItsOwnHeadAndTakesTheMainRepositoryName() {
        let tree = FileTree(files: [
            "/Users/me/work/nav/.git": "gitdir: /Users/me/mini/.git/worktrees/nav\n",
            "/Users/me/mini/.git/worktrees/nav/HEAD": "ref: refs/heads/feat/nav\n",
            "/Users/me/mini/.git/worktrees/nav/commondir": "../..\n",
        ])
        #expect(tree.project(workingDirectory: "/Users/me/work/nav") == LocalProject(name: "mini", root: "/Users/me/work/nav", branch: "feat/nav"))
    }

    @Test func submoduleKeepsItsOwnFolderName() {
        let tree = FileTree(files: [
            "/Users/me/mini/ui/.git": "gitdir: ../.git/modules/ui\n",
            "/Users/me/mini/.git/modules/ui/HEAD": "0123456789abcdef0123456789abcdef01234567\n",
        ])
        #expect(tree.project(workingDirectory: "/Users/me/mini/ui") == LocalProject(name: "ui", root: "/Users/me/mini/ui", branch: "0123456"))
    }

    @Test func unreadableHeadLeavesTheBranchUnknown() {
        let tree = FileTree(directories: ["/Users/me/mini/.git"])
        #expect(tree.project(workingDirectory: "/Users/me/mini") == LocalProject(name: "mini", root: "/Users/me/mini", branch: nil))
    }

    @Test func outsideGitTheWorkingFolderNamesTheProjectExceptHomeAndSlash() {
        let tree = FileTree()
        #expect(tree.project(workingDirectory: "/tmp/site/") == LocalProject(name: "site", root: "/tmp/site", branch: nil))
        #expect(tree.project(workingDirectory: "/Users/me") == nil)
        #expect(tree.project(workingDirectory: "/") == nil)
    }

    @Test func privacyProtectedFoldersAreNeverInspected() {
        var tree = FileTree()
        tree.directories = ["/Users/me/Documents/site/.git"]
        tree.files = ["/Users/me/Documents/site/.git/HEAD": "ref: refs/heads/main\n"]
        #expect(tree.project(workingDirectory: "/Users/me/Documents/site") == nil)
        #expect(tree.project(workingDirectory: "/Users/me/Downloads") == nil)
        #expect(LocalProjectResolution.isPrivacyProtected("/Users/me/Desktop/a", homeDirectory: "/Users/me"))
        #expect(!LocalProjectResolution.isPrivacyProtected("/Users/me/Development/a", homeDirectory: "/Users/me"))
        #expect(!LocalProjectResolution.isPrivacyProtected("/Users/me/DocumentsArchive", homeDirectory: "/Users/me"))
    }

    @Test func serverDescriptionNamesBranchWhenKnown() {
        #expect(LocalProject(name: "mini", root: "/a/mini", branch: "main").serverDescription(port: 3000) == "mini on main, port 3000")
        #expect(LocalProject(name: "site", root: "/tmp/site", branch: nil).serverDescription(port: 8000) == "site, port 8000")
    }
}
