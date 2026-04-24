// swift-tools-version: 6.1

import PackageDescription

let package = Package(
    name: "WARDENModelLoader",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .executable(
            name: "WMLShell",
            targets: ["WMLShell"]
        ),
    ],
    targets: [
        .executableTarget(
            name: "WMLShell",
            path: "Sources/WMLShell"
        ),
        .testTarget(
            name: "WMLShellTests",
            dependencies: ["WMLShell"],
            path: "Tests/WMLShellTests"
        ),
    ]
)
