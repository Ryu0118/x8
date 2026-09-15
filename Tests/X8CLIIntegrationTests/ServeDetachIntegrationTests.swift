#if X8_S3
    import Darwin
    import Foundation
    import Subprocess
    import System
    import Testing
    @testable import X8CLI
    import X8Config
    import X8Kit

    @Suite("Detached serve against the real x8 binary", .serialized, .timeLimit(.minutes(1)))
    struct ServeDetachIntegrationTests {
        @Test
        func detachStartsAReachableDaemon() async throws {
            let fixture = try DetachedServeFixture()
            try await fixture.withTearDown {
                let start = try await fixture.run(["serve", "-d", "--print-socket"])
                #expect(start.status == 0)
                #expect(start.stdout.trimmingCharacters(in: .whitespacesAndNewlines) == fixture.socketPath)
                #expect(start.stderr.contains("Cache server is running in the background at"))

                let record = try fixture.readRecord()
                #expect(record.executablePath == fixture.executable.resolvingSymlinksInPath().path)
                #expect(fixture.isAlive(record.pid))
                #expect(try await fixture.waitUntil { fixture.canConnect() })
                #expect(FileManager.default.fileExists(atPath: fixture.eventsSocketPath))
            }
        }

        @Test
        func losingDetachLeavesTheRunningDaemonUntouched() async throws {
            let fixture = try DetachedServeFixture()
            try await fixture.withTearDown {
                let start = try await fixture.run(["serve", "-d", "--print-socket"])
                #expect(start.status == 0)
                let first = try fixture.readRecord()
                let pidBytes = try Data(contentsOf: fixture.pidFileURL)

                let second = try await fixture.run(["serve", "-d", "--print-socket"])
                #expect(second.status == 64)
                #expect(second.stderr.contains("exited before becoming ready (status 1)"))
                let log = try String(contentsOf: fixture.logFileURL, encoding: .utf8)
                #expect(log.contains(
                    "The cache socket path is already occupied by an existing endpoint: \(fixture.socketPath)."
                ))

                // The loser must not have unlinked the winner's socket or pidfile.
                #expect(FileManager.default.fileExists(atPath: fixture.socketPath))
                #expect(fixture.canConnect())
                let stillFirst = try fixture.readRecord()
                #expect(stillFirst.pid == first.pid)
                #expect(stillFirst.startTime == first.startTime)
                #expect(try Data(contentsOf: fixture.pidFileURL) == pidBytes)
                #expect(fixture.isAlive(first.pid))
            }
        }

        @Test
        func stopTerminatesGracefullyAndCleansUp() async throws {
            let fixture = try DetachedServeFixture()
            try await fixture.withTearDown {
                let start = try await fixture.run(["serve", "-d", "--print-socket"])
                #expect(start.status == 0)
                let record = try fixture.readRecord()

                let stop = try await fixture.run(["serve", "stop"])
                #expect(stop.status == 0)
                #expect(stop.stderr.contains("Stopped the detached `x8 serve` process (pid \(record.pid))"))
                #expect(try await fixture.waitUntil(.seconds(2)) { fixture.isGone(record.pid) })
                #expect(!FileManager.default.fileExists(atPath: fixture.pidFileURL.path))
                #expect(!FileManager.default.fileExists(atPath: fixture.socketPath))
                #expect(!FileManager.default.fileExists(atPath: fixture.eventsSocketPath))
            }
        }

        @Test
        func detachReclaimsAfterSigkill() async throws {
            let fixture = try DetachedServeFixture()
            try await fixture.withTearDown {
                let start = try await fixture.run(["serve", "-d", "--print-socket"])
                #expect(start.status == 0)
                let old = try fixture.readRecord()

                #expect(kill(old.pid, SIGKILL) == 0)
                #expect(try await fixture.waitUntil(.seconds(2)) { fixture.isGone(old.pid) })
                #expect(FileManager.default.fileExists(atPath: fixture.pidFileURL.path))
                #expect(FileManager.default.fileExists(atPath: fixture.socketPath))
                #expect(FileManager.default.fileExists(atPath: fixture.eventsSocketPath))

                let again = try await fixture.run(["serve", "-d", "--print-socket"])
                #expect(again.status == 0)
                let new = try fixture.readRecord()
                #expect(new.pid != old.pid)
                #expect(new.startTime != old.startTime)
                #expect(fixture.isAlive(new.pid))
                #expect(try await fixture.waitUntil { fixture.canConnect() })
                let log = try String(contentsOf: fixture.logFileURL, encoding: .utf8)
                #expect(!log.contains("Live cache-events socket unavailable"))
            }
        }

        @Test
        func stopAfterSigkillCleansStaleRecord() async throws {
            let fixture = try DetachedServeFixture()
            try await fixture.withTearDown {
                let start = try await fixture.run(["serve", "-d", "--print-socket"])
                #expect(start.status == 0)
                let record = try fixture.readRecord()
                #expect(kill(record.pid, SIGKILL) == 0)
                #expect(try await fixture.waitUntil(.seconds(2)) { fixture.isGone(record.pid) })

                let stop = try await fixture.run(["serve", "stop"])
                #expect(stop.status == 0)
                #expect(stop.stderr.contains("No detached `x8 serve` process is running for this profile."))
                #expect(!FileManager.default.fileExists(atPath: fixture.pidFileURL.path))
                #expect(!FileManager.default.fileExists(atPath: fixture.socketPath))
            }
        }
    }

    private final class BundleMarker {}

    private struct CommandResult {
        let status: Int32
        let stdout: String
        let stderr: String
    }

    /// One detached-serve profile: its config directory, runtime directory, and every PID it observed.
    ///
    /// The runtime directory lives under the real `~/Library/Application Support/X8/`
    /// because `HOME` does not relocate it on macOS; isolation comes from a unique
    /// bucket per fixture, and a marker file lets a later fixture sweep leftovers
    /// from a hard-killed test run without touching unrelated profiles.
    private final class DetachedServeFixture: @unchecked Sendable {
        static let markerFileName = "x8-detach-integration.marker"

        let executable: URL
        let configDirectory: URL
        let runtimeDirectory: URL
        let pidFileURL: URL
        let socketPath: String
        let eventsSocketPath: String
        let logFileURL: URL
        private let lock = NSLock()
        private var trackedPIDs: Set<Int32> = []

        init() throws {
            let override = ProcessInfo.processInfo.environment["X8_EXECUTABLE"]
            executable = override.map { URL(filePath: $0) }
                ?? Bundle(for: BundleMarker.self).bundleURL
                .deletingLastPathComponent()
                .appending(path: "x8")
            guard FileManager.default.isExecutableFile(atPath: executable.path) else {
                throw FixtureError.executableMissing(executable.path)
            }

            try Self.sweepStaleFixtures()

            let bucket = "x8-detach-it-" + UUID().uuidString.lowercased()
                .replacingOccurrences(of: "-", with: "").prefix(12)
            let endpoint = "http://127.0.0.1:1"
            let profileID = X8Configuration(bucket: String(bucket), endpoint: URL(string: endpoint)).profileID

            runtimeDirectory = Self.applicationSupportX8Root
                .appending(path: profileID, directoryHint: .isDirectory)
            pidFileURL = runtimeDirectory.appending(path: "serve.pid")
            socketPath = runtimeDirectory.appending(path: "cache.sock").path
            eventsSocketPath = runtimeDirectory.appending(path: "events.sock").path
            logFileURL = runtimeDirectory.appending(path: "serve.log")
            try FileManager.default.createDirectory(
                at: runtimeDirectory,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
            try Data().write(to: runtimeDirectory.appending(path: Self.markerFileName))

            configDirectory = FileManager.default.temporaryDirectory
                .appending(path: "x8-detach-\(UUID().uuidString)", directoryHint: .isDirectory)
            try FileManager.default.createDirectory(at: configDirectory, withIntermediateDirectories: true)
            try """
            version: 1
            bucket: \(bucket)
            endpoint: \(endpoint)
            accessKeyID: test
            secretAccessKey: test
            """.write(to: configDirectory.appending(path: ".x8.yml"), atomically: true, encoding: .utf8)
        }

        func withTearDown(_ body: () async throws -> Void) async throws {
            do {
                try await body()
            } catch {
                await tearDown()
                throw error
            }
            await tearDown()
        }

        func run(_ arguments: [String]) async throws -> CommandResult {
            let result = try await Subprocess.run(
                .path(FilePath(executable.path)),
                arguments: Arguments(arguments),
                environment: .inherit.updating(["NO_COLOR": "1"]),
                workingDirectory: FilePath(configDirectory.path),
                output: .string(limit: 1_000_000),
                error: .string(limit: 1_000_000)
            )
            guard case let .exited(status) = result.terminationStatus else {
                throw FixtureError.signaled(String(describing: result.terminationStatus))
            }
            return CommandResult(
                status: status,
                stdout: result.standardOutput ?? "",
                stderr: result.standardError ?? ""
            )
        }

        func readRecord() throws -> XcodeServeProcessRecord {
            guard let record = XcodeServeRunner.readProcessRecord(at: pidFileURL) else {
                throw FixtureError.pidFileUnreadable(pidFileURL.path)
            }
            lock.withLock { _ = trackedPIDs.insert(record.pid) }
            return record
        }

        func isAlive(_ pid: Int32) -> Bool {
            kill(pid, 0) == 0
        }

        func isGone(_ pid: Int32) -> Bool {
            kill(pid, 0) == -1 && errno == ESRCH
        }

        func canConnect() -> Bool {
            let descriptor = socket(AF_UNIX, SOCK_STREAM, 0)
            guard descriptor >= 0 else { return false }
            defer { close(descriptor) }

            var address = sockaddr_un()
            address.sun_family = sa_family_t(AF_UNIX)
            let capacity = MemoryLayout.size(ofValue: address.sun_path)
            guard socketPath.utf8.count < capacity else { return false }
            withUnsafeMutableBytes(of: &address.sun_path) { buffer in
                buffer.initializeMemory(as: UInt8.self, repeating: 0)
                buffer.copyBytes(from: socketPath.utf8)
            }

            return withUnsafePointer(to: &address) { pointer in
                pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { rebound in
                    connect(descriptor, rebound, socklen_t(MemoryLayout<sockaddr_un>.size))
                }
            } == 0
        }

        func waitUntil(_ deadline: Duration = .seconds(5), _ condition: () -> Bool) async throws -> Bool {
            let clock = ContinuousClock()
            let end = clock.now.advanced(by: deadline)
            while clock.now < end, !condition() {
                try await Task.sleep(for: .milliseconds(50))
            }
            return condition()
        }

        /// Stops, kills, and removes everything this fixture produced, in that order.
        ///
        /// `serve stop` handles the alive, stale, and absent cases on its own; the
        /// SIGKILL pass covers a daemon whose pidfile `stop` never saw. The daemon
        /// runs in its own session, so it cannot be reaped with `waitpid` and its
        /// exit is observed through `kill(pid, 0)` instead.
        func tearDown() async {
            _ = try? await run(["serve", "stop"])
            let pids = lock.withLock { trackedPIDs }
            for pid in pids {
                _ = kill(pid, SIGKILL)
            }
            for pid in pids {
                _ = try? await waitUntil(.seconds(2)) { isGone(pid) }
            }
            try? FileManager.default.removeItem(at: runtimeDirectory)
            try? FileManager.default.removeItem(at: configDirectory)
        }

        private static var applicationSupportX8Root: URL {
            let applicationSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                ?? FileManager.default.homeDirectoryForCurrentUser
            return applicationSupport.appending(path: "X8", directoryHint: .isDirectory)
        }

        /// Removes profiles a previous, hard-killed run left behind, killing any daemon still alive in them.
        ///
        /// Only directories carrying this fixture's marker are touched, and only a
        /// process whose recorded start time still matches is signaled, so a
        /// reused PID belonging to an unrelated process is left alone.
        private static func sweepStaleFixtures() throws {
            guard let entries = try? FileManager.default.contentsOfDirectory(
                at: applicationSupportX8Root,
                includingPropertiesForKeys: nil
            ) else { return }
            let probe = LiveProcessLivenessProbe()
            let markedDirectories = entries.filter {
                FileManager.default.fileExists(atPath: $0.appending(path: markerFileName).path)
            }
            for directory in markedDirectories {
                try sweep(directory, probe: probe)
            }
        }

        private static func sweep(_ directory: URL, probe: LiveProcessLivenessProbe) throws {
            if let record = XcodeServeRunner.readProcessRecord(at: directory.appending(path: "serve.pid")),
               probe.isAlive(record)
            {
                _ = kill(record.pid, SIGKILL)
            }
            try FileManager.default.removeItem(at: directory)
        }
    }

    private enum FixtureError: Error, CustomStringConvertible {
        case executableMissing(String)
        case pidFileUnreadable(String)
        case signaled(String)

        var description: String {
            switch self {
            case let .executableMissing(path):
                "No x8 executable at \(path); build the S3 trait or set X8_EXECUTABLE."
            case let .pidFileUnreadable(path):
                "No decodable process record at \(path)."
            case let .signaled(status):
                "The x8 invocation did not exit normally: \(status)."
            }
        }
    }
#endif
