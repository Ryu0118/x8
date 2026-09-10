#if X8_S3
    import Foundation
    import Subprocess
    import Testing

    @Suite("S3-compatible local process integration")
    struct S3LocalIntegrationTests {
        @Test(
            "replays CAS and Action Cache records across processes",
            .enabled(if: Runtime.endpoint != nil)
        )
        func replaysRecordsAcrossProcesses() async throws {
            let commonArguments = Runtime.commonArguments()
            var cleanupNeeded = false

            do {
                let writeOutput = try await WorkerProcess.run(
                    operation: "write",
                    arguments: commonArguments
                )
                cleanupNeeded = true
                let records = try WorkerOutput.parse(writeOutput)
                let verifyArguments = commonArguments + [
                    records.objectID,
                    records.blobID,
                    records.actionKey,
                ]
                _ = try await WorkerProcess.run(
                    operation: "verify",
                    arguments: verifyArguments
                )
                _ = try await WorkerProcess.run(
                    operation: "cleanup",
                    arguments: commonArguments
                )
                cleanupNeeded = false
            } catch {
                await cleanupIfNeeded(cleanupNeeded, arguments: commonArguments)
                throw error
            }
        }

        private func cleanupIfNeeded(
            _ needed: Bool,
            arguments: [String]
        ) async {
            guard needed else { return }
            _ = try? await WorkerProcess.run(
                operation: "cleanup",
                arguments: arguments
            )
        }
    }

    private enum Runtime {
        static let endpoint = ProcessInfo.processInfo.environment["X8_S3_ENDPOINT"]
            .flatMap(URL.init(string:))
            .flatMap { endpoint in
                ["localhost", "127.0.0.1", "::1"].contains(endpoint.host?.lowercased() ?? "")
                    ? endpoint
                    : nil
            }

        static func commonArguments() -> [String] {
            [
                endpoint?.absoluteString ?? "",
                ProcessInfo.processInfo.environment["X8_S3_BUCKET"] ?? "foo",
            ]
        }

        static var packageRoot: URL {
            URL(filePath: #filePath)
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .deletingLastPathComponent()
        }
    }

    private enum WorkerProcess {
        static func run(
            operation: String,
            arguments: [String]
        ) async throws -> String {
            let result = try await Subprocess.run(
                .name("swift"),
                arguments: Arguments([
                    "run",
                    "--package-path",
                    Runtime.packageRoot.path,
                    "--traits",
                    "S3",
                    "X8S3ProcessIntegrationWorker",
                    operation,
                ] + arguments),
                output: .string(limit: 2_000_000),
                error: .string(limit: 2_000_000)
            )
            guard case .exited(0) = result.terminationStatus else {
                throw IntegrationError.workerFailed(
                    stdout: result.standardOutput ?? "",
                    stderr: result.standardError ?? ""
                )
            }
            return result.standardOutput ?? ""
        }
    }

    private enum WorkerOutput {
        static func parse(_ output: String) throws -> Records {
            let values = output.split(separator: "\n").reduce(into: [String: String]()) { result, line in
                let parts = line.split(separator: "=", maxSplits: 1).map(String.init)
                guard parts.count == 2 else { return }
                result[parts[0]] = parts[1]
            }
            guard let objectID = values["object_id"],
                  let blobID = values["blob_id"],
                  let actionKey = values["action_key"]
            else {
                throw IntegrationError.invalidWorkerOutput(output)
            }
            return Records(objectID: objectID, blobID: blobID, actionKey: actionKey)
        }
    }

    private struct Records: Sendable {
        let objectID: String
        let blobID: String
        let actionKey: String
    }

    private enum IntegrationError: Error, CustomStringConvertible, Sendable {
        case invalidWorkerOutput(String)
        case workerFailed(stdout: String, stderr: String)

        var description: String {
            switch self {
            case let .invalidWorkerOutput(output):
                "The integration worker did not return record IDs: " + output
            case let .workerFailed(stdout, stderr):
                "The integration worker failed. stdout: " + stdout + " stderr: " + stderr
            }
        }
    }
#endif
