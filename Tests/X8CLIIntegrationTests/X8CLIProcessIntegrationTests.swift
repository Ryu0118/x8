import Foundation
import Testing
import X8CLI
import X8Storage

@Suite("The shared CLI preserves child status and drains before client cleanup")
struct X8CLIProcessIntegrationTests {
    @Test(arguments: [0, 7, 143])
    func forwardsSettingsAndPreservesTermination(status: Int32) async throws {
        let fixture = try ChildFixture(status: status)
        defer { fixture.remove() }
        let cleanup = CleanupProbe()
        let cli = X8CLI(
            configuration: { try X8CLIConfiguration(value: (), profileID: "process-integration") },
            storage: { _ in InMemoryStorage() },
            shutdown: { _ in
                let socket = try fixture.socketPath()
                await cleanup.record(socketExists: FileManager.default.fileExists(atPath: socket))
            }
        )

        let forwarded = [
            "-scheme", "Example", "SETTING=a b", "--help",
            "-derivedDataPath", fixture.directory.appending(path: "My DerivedData").path,
            "-clonedSourcePackagesDirPath", "../My Packages",
            "OBJROOT=../My Objects",
        ]
        let result = await cli.run(arguments: [
            fixture.executable.path, fixture.argumentsFile.path,
        ] + forwarded)
        let arguments = try fixture.forwardedArguments()

        #expect(result == status)
        #expect(Array(arguments.prefix(forwarded.count)) == forwarded)
        #expect(arguments.count == forwarded.count + 10)
        #expect(arguments.contains("COMPILATION_CACHE_ENABLE_CACHING=YES"))
        #expect(arguments.contains("COMPILATION_CACHE_ENABLE_PLUGIN=YES"))
        #expect(arguments.contains("CLANG_MODULES_BUILD_SESSION_FILE="))
        #expect(await cleanup.observations == [false])
        #expect(try !FileManager.default.fileExists(atPath: fixture.socketPath()))
    }
}

private actor CleanupProbe {
    private(set) var observations: [Bool] = []

    func record(socketExists: Bool) {
        observations.append(socketExists)
    }
}

private struct ChildFixture: Sendable {
    let directory: URL
    let executable: URL
    let argumentsFile: URL

    init(status: Int32) throws {
        directory = FileManager.default.temporaryDirectory.appending(path: "x8-child-\(UUID().uuidString)")
        executable = directory.appending(path: "xcodebuild")
        argumentsFile = directory.appending(path: "arguments.txt")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        let termination = status == 143 ? "kill -TERM $$" : "exit \(status)"
        let script = """
        #!/bin/sh
        record_path=$1
        shift
        printf '%s\\n' "$@" > "$record_path"
        \(termination)
        """
        try script.write(to: executable, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: executable.path)
    }

    func forwardedArguments() throws -> [String] {
        try String(contentsOf: argumentsFile, encoding: .utf8).split(separator: "\n").map(String.init)
    }

    func socketPath() throws -> String {
        let prefix = "COMPILATION_CACHE_REMOTE_SERVICE_PATH="
        let setting = try #require(forwardedArguments().first { $0.hasPrefix(prefix) })
        return String(setting.dropFirst(prefix.count))
    }

    func remove() {
        // The fixture owns only this newly allocated temporary directory.
        try? FileManager.default.removeItem(at: directory)
    }
}
