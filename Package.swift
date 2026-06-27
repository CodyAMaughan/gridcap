// swift-tools-version: 5.7

import PackageDescription

let package = Package(
    name: "gridcap",
    platforms: [.macOS(.v13)],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.2.0"),
    ],
    targets: [
        .executableTarget(
            name: "gridcap",
            dependencies: [
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ],
            path: "Sources/GridCap"
        ),
        .testTarget(
            name: "gridcapTests",
            dependencies: ["gridcap"],
            path: "Tests/GridCapTests"
        ),
    ]
)
