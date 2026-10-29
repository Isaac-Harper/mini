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
        .target(name: "MiniRules", path: "Sources/MiniRules", swiftSettings: [.swiftLanguageMode(.v6)]),
        .executableTarget(
            name: "Mini",
            dependencies: ["CMiniCore", "MiniRules"],
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
        .testTarget(
            name: "MiniRulesTests",
            dependencies: ["MiniRules"],
            path: "Tests/MiniRulesTests",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
    ]
)
