// swift-tools-version: 6.2
import Foundation
import PackageDescription

let coreTargetDirectory = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .appendingPathComponent("../core/target")
    .standardizedFileURL
    .path

let package = Package(
    name: "Mini",
    platforms: [.macOS(.v26)],
    products: [
        .executable(name: "Mini", targets: ["Mini"])
    ],
    targets: [
        .systemLibrary(name: "CMiniCore", path: "Sources/CMiniCore"),
        .executableTarget(
            name: "Mini",
            dependencies: ["CMiniCore"],
            path: "Sources/Mini",
            swiftSettings: [.swiftLanguageMode(.v6)],
            linkerSettings: [
                .unsafeFlags(["-L\(coreTargetDirectory)/release"], .when(configuration: .release)),
                .unsafeFlags(["-L\(coreTargetDirectory)/debug"], .when(configuration: .debug)),
                .unsafeFlags(["-Xlinker", "-dead_strip", "-lmini_core", "-lc++", "-lobjc", "-liconv"]),
                .linkedFramework("AppKit"),
                .linkedFramework("Foundation"),
                .linkedFramework("CoreFoundation"),
            ]
        ),
    ]
)
