import AppKit
import CMiniCore

let application = MiniApplication.shared
let applicationDelegate = AppDelegate()
application.delegate = applicationDelegate

let profileDirectory = AppDelegate.supportDirectory.appendingPathComponent("Profile")
let filterListsDirectory = AppDelegate.supportDirectory.appendingPathComponent("Filters")
for directory in [profileDirectory, filterListsDirectory] {
    do {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    } catch {
        fatalError("Could not create directory \(directory.path): \(error)")
    }
}

let initialized = profileDirectory.path.withCString { rootCachePath in
    filterListsDirectory.path.withCString { filterListsPath in
        mini_initialize(CommandLine.argc, CommandLine.unsafeArgv, rootCachePath, filterListsPath, BrowserEngine.callbacks)
    }
}
guard initialized else {
    fatalError("mini_initialize failed")
}

mini_run_message_loop()
mini_shutdown()
