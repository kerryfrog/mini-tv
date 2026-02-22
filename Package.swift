// swift-tools-version: 5.10
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "MiniTubePlayer",
    platforms: [
        .macOS(.v13),
    ],
    targets: [
        .executableTarget(
            name: "MiniTubePlayer",
            resources: [
                .process("Resources"),
            ],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("WebKit"),
            ]
        ),
    ]
)
