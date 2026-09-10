// swift-tools-version: 6.1

import PackageDescription

let package = Package(
    name: "CustomStorageCLI",
    platforms: [.macOS(.v15)],
    dependencies: [.package(path: "../..", traits: [])],
    targets: [
        .executableTarget(
            name: "ExampleCache",
            dependencies: [
                .product(name: "X8CLI", package: "x8"),
                .product(name: "X8Storage", package: "x8"),
                .product(name: "X8Core", package: "x8"),
            ]
        ),
    ]
)
