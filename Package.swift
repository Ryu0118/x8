// swift-tools-version: 6.1

import PackageDescription

let package = Package(
    name: "X8",
    platforms: [
        .macOS("26.0"),
    ],
    products: [
        .executable(name: "x8", targets: ["x8"]),
        .library(name: "X8Core", targets: ["X8Core"]),
        .library(name: "X8Storage", targets: ["X8Storage"]),
        .library(name: "X8S3", targets: ["X8S3"]),
        .library(name: "X8Config", targets: ["X8Config"]),
        .library(name: "X8Kit", targets: ["X8Kit"]),
        .library(name: "X8CLI", targets: ["X8CLI"]),
    ],
    traits: [
        .trait(
            name: "S3",
            description: "Enable the S3-compatible storage backend."
        ),
    ],
    dependencies: [
        .package(
            url: "https://github.com/apple/swift-argument-parser.git",
            from: "1.8.2"
        ),
        .package(
            url: "https://github.com/apple/swift-log.git",
            from: "1.10.1"
        ),
        .package(
            url: "https://github.com/swiftlang/swift-subprocess.git",
            .upToNextMinor(from: "0.4.0")
        ),
        .package(
            url: "https://github.com/Ryu0118/FileManagerProtocol.git",
            from: "0.1.0"
        ),
        .package(
            url: "https://github.com/jpsim/Yams.git",
            from: "6.2.2"
        ),
        .package(
            url: "https://github.com/soto-project/soto.git",
            from: "7.15.0"
        ),
        .package(
            url: "https://github.com/swift-server/async-http-client.git",
            from: "1.30.0"
        ),
        .package(
            url: "https://github.com/grpc/grpc-swift-2.git",
            from: "2.0.0"
        ),
        .package(
            url: "https://github.com/grpc/grpc-swift-nio-transport.git",
            from: "2.0.0"
        ),
        .package(
            url: "https://github.com/apple/swift-nio.git",
            from: "2.101.3"
        ),
        .package(
            url: "https://github.com/grpc/grpc-swift-protobuf.git",
            from: "2.4.0"
        ),
        .package(
            url: "https://github.com/apple/swift-protobuf.git",
            from: "1.38.0",
            traits: []
        ),
        .package(
            url: "https://github.com/swiftlang/swift-docc-plugin",
            from: "1.1.0"
        ),
        .package(
            url: "https://github.com/mtj0928/swift-async-operations",
            from: "0.5.0"
        ),
    ],
    targets: [
        .executableTarget(
            name: "x8",
            dependencies: [
                "X8CLI",
                "X8Config",
                .target(
                    name: "X8S3",
                    condition: .when(traits: ["S3"])
                ),
            ],
            swiftSettings: [
                .define("X8_S3", .when(traits: ["S3"])),
            ]
        ),
        .target(name: "X8Core"),
        .target(
            name: "X8CLI",
            dependencies: [
                "X8Kit",
                "X8Storage",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
                .product(name: "Logging", package: "swift-log"),
                .product(name: "Subprocess", package: "swift-subprocess"),
            ]
        ),
        .target(
            name: "X8Storage",
            dependencies: [
                "X8Core",
                .product(
                    name: "FileManagerProtocol",
                    package: "FileManagerProtocol"
                ),
                .product(
                    name: "AsyncOperations",
                    package: "swift-async-operations"
                ),
            ]
        ),
        .target(
            name: "X8S3",
            dependencies: [
                "X8Core",
                "X8Storage",
                "X8Config",
                .product(
                    name: "FileManagerProtocol",
                    package: "FileManagerProtocol"
                ),
                .product(
                    name: "SotoS3",
                    package: "soto",
                    condition: .when(traits: ["S3"])
                ),
                .product(
                    name: "AsyncHTTPClient",
                    package: "async-http-client",
                    condition: .when(traits: ["S3"])
                ),
                .product(
                    name: "AsyncOperations",
                    package: "swift-async-operations"
                ),
            ],
            swiftSettings: [
                .define("X8_S3", .when(traits: ["S3"])),
            ]
        ),
        .target(
            name: "X8Config",
            dependencies: [
                "X8Core",
                "X8Storage",
                .product(
                    name: "Yams",
                    package: "Yams"
                ),
            ]
        ),
        .target(
            name: "X8Kit",
            dependencies: [
                "X8Core",
                "X8Storage",
                .product(
                    name: "FileManagerProtocol",
                    package: "FileManagerProtocol"
                ),
                .product(
                    name: "GRPCCore",
                    package: "grpc-swift-2"
                ),
                .product(
                    name: "GRPCNIOTransportHTTP2",
                    package: "grpc-swift-nio-transport"
                ),
                .product(
                    name: "GRPCProtobuf",
                    package: "grpc-swift-protobuf"
                ),
                .product(
                    name: "SwiftProtobuf",
                    package: "swift-protobuf"
                ),
                .product(
                    name: "AsyncOperations",
                    package: "swift-async-operations"
                ),
                .product(
                    name: "NIOCore",
                    package: "swift-nio"
                ),
                .product(
                    name: "NIOPosix",
                    package: "swift-nio"
                ),
            ]
        ),
        .executableTarget(
            name: "X8S3ProcessIntegrationWorker",
            dependencies: [
                "X8Core",
                "X8Storage",
                .target(
                    name: "X8S3",
                    condition: .when(traits: ["S3"])
                ),
            ],
            swiftSettings: [
                .define("X8_S3", .when(traits: ["S3"])),
            ]
        ),
        .testTarget(
            name: "X8CoreTests",
            dependencies: ["X8Core"]
        ),
        .testTarget(
            name: "X8StorageTests",
            dependencies: [
                "X8Core",
                "X8Storage",
                .product(
                    name: "AsyncOperations",
                    package: "swift-async-operations"
                ),
            ]
        ),
        .testTarget(
            name: "X8S3Tests",
            dependencies: [
                "X8Core",
                "X8Storage",
                .target(
                    name: "X8S3",
                    condition: .when(traits: ["S3"])
                ),
                .product(
                    name: "Subprocess",
                    package: "swift-subprocess"
                ),
                .product(
                    name: "AsyncOperations",
                    package: "swift-async-operations"
                ),
            ],
            swiftSettings: [
                .define("X8_S3", .when(traits: ["S3"])),
            ]
        ),
        .testTarget(
            name: "X8KitTests",
            dependencies: [
                "X8Core",
                "X8Kit",
                "X8Storage",
                .product(
                    name: "GRPCCore",
                    package: "grpc-swift-2"
                ),
            ]
        ),
        .testTarget(
            name: "X8KitIntegrationTests",
            dependencies: [
                "X8Core",
                "X8Kit",
                "X8Storage",
                .product(
                    name: "GRPCCore",
                    package: "grpc-swift-2"
                ),
                .product(
                    name: "GRPCNIOTransportHTTP2",
                    package: "grpc-swift-nio-transport"
                ),
                .product(
                    name: "Subprocess",
                    package: "swift-subprocess"
                ),
                .product(
                    name: "NIOCore",
                    package: "swift-nio"
                ),
                .product(
                    name: "NIOPosix",
                    package: "swift-nio"
                ),
            ]
        ),
        .testTarget(
            name: "X8ConfigTests",
            dependencies: ["X8Config"]
        ),
        .testTarget(
            name: "X8CLITests",
            dependencies: ["X8CLI", "X8Config", "X8Storage", "X8Core"]
        ),
        .testTarget(
            name: "X8CLIIntegrationTests",
            dependencies: ["X8CLI", "X8Storage"]
        ),
    ]
)
