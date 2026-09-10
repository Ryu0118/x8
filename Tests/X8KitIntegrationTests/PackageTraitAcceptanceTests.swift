import Foundation
import Subprocess
import Testing

@Suite("SwiftPM trait acceptance")
struct PackageTraitAcceptanceTests {
    @Test(
        "foo builds without Soto by default and with Soto when S3 is enabled",
        .enabled(if: Runtime.shouldRun)
    )
    func defaultAndS3GraphsAreIndependent() async throws {
        let root = packageRoot
        let defaultConsumer = try ConsumerFixture(
            root: root,
            traits: [],
            product: "X8Kit",
            importModule: "X8Kit"
        )
        let s3Consumer = try ConsumerFixture(
            root: root,
            traits: ["S3"],
            product: "X8S3",
            importModule: "X8S3"
        )

        defer {
            defaultConsumer.remove()
            s3Consumer.remove()
        }

        try await defaultConsumer.build()
        #expect(defaultConsumer.containsCheckout(named: "soto") == false)
        #expect(defaultConsumer.containsCompiledModule(named: "X8S3") == false)

        try await s3Consumer.build()
        #expect(s3Consumer.containsCheckout(named: "soto"))
        #expect(s3Consumer.containsCompiledModule(named: "X8S3"))
    }

    private var packageRoot: URL {
        URL(filePath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}

private enum Runtime {
    static let shouldRun = ProcessInfo.processInfo.environment[
        "X8_RUN_PACKAGE_ACCEPTANCE"
    ] == "1"
}

private struct ConsumerFixture: Sendable {
    private let directory: URL

    init(
        root: URL,
        traits: [String],
        product: String,
        importModule: String
    ) throws {
        directory = FileManager.default.temporaryDirectory
            .appending(path: "x8-package-acceptance-\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: directory.appending(path: "Sources/Foo"),
            withIntermediateDirectories: true
        )

        let traitSyntax = traits.map { "\"\($0)\"" }.joined(separator: ", ")
        let manifest = """
        // swift-tools-version: 6.1

        import PackageDescription

        let package = Package(
            name: "Foo",
            platforms: [.macOS(.v15)],
            dependencies: [
                .package(path: "\(root.path)", traits: [\(traitSyntax)])
            ],
            targets: [
                .executableTarget(
                    name: "Foo",
                    dependencies: [
                        .product(name: "\(product)", package: "x8")
                    ]
                )
            ]
        )
        """
        try manifest.write(
            to: directory.appending(path: "Package.swift"),
            atomically: true,
            encoding: .utf8
        )
        try "import \(importModule)\nprint(\"foo\")\n".write(
            to: directory.appending(path: "Sources/Foo/main.swift"),
            atomically: true,
            encoding: .utf8
        )
    }

    func build() async throws {
        let result = try await Subprocess.run(
            .name("swift"),
            arguments: Arguments([
                "build",
                "--package-path",
                directory.path,
                "--experimental-prune-unused-dependencies",
            ]),
            output: .string(limit: 2_000_000),
            error: .string(limit: 2_000_000)
        )
        guard case .exited(0) = result.terminationStatus else {
            throw AcceptanceError.buildFailed(
                stdout: result.standardOutput ?? "",
                stderr: result.standardError ?? ""
            )
        }
    }

    func containsCheckout(named name: String) -> Bool {
        FileManager.default.fileExists(
            atPath: directory.appending(path: ".build/checkouts/\(name)").path
        )
    }

    func containsCompiledModule(named name: String) -> Bool {
        let buildDirectory = directory.appending(path: ".build")
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: buildDirectory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else {
            return false
        }
        return entries.contains { buildRoot in
            FileManager.default.fileExists(
                atPath: buildRoot
                    .appending(path: "debug/Modules/\(name).swiftmodule")
                    .path
            )
        }
    }

    func remove() {
        try? FileManager.default.removeItem(at: directory)
    }
}

private enum AcceptanceError: Error, CustomStringConvertible {
    case buildFailed(stdout: String, stderr: String)

    var description: String {
        switch self {
        case let .buildFailed(stdout, stderr):
            "SwiftPM consumer build failed. stdout: \(stdout) stderr: \(stderr)"
        }
    }
}
