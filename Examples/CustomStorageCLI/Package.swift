// swift-tools-version: 6.1

import PackageDescription

let package = Package(
    name: "CustomStorageCLI",
    // Must match the X8 package's deployment target; SwiftPM rejects a
    // dependent with a lower minimum than the products it links.
    platforms: [.macOS("26.0")],
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
