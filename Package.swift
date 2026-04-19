// swift-tools-version: 6.1

import PackageDescription

let package = Package(
    name: "WARDEN4LocalLLMLoaderRebuild",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .executable(
            name: "LoaderShell",
            targets: ["LoaderShell"]
        ),
    ],
    targets: [
        .executableTarget(
            name: "LoaderShell",
            path: "Sources/LoaderShell"
        ),
        .testTarget(
            name: "LoaderShellTests",
            dependencies: ["LoaderShell"],
            path: "Tests/LoaderShellTests"
        ),
    ]
)
