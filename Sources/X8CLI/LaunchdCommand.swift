import ArgumentParser
import Darwin
import Foundation
import Subprocess
import System
import X8Kit

struct LaunchdCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "launchd",
        abstract: "Manage a launchd LaunchAgent that runs x8 serve for Xcode.app builds.",
        subcommands: [
            LaunchdInstallCommand.self,
            LaunchdUninstallCommand.self,
            LaunchdStatusCommand.self,
        ]
    )
}

struct LaunchdInstallCommand: X8ExecutableCommand {
    static let configuration = CommandConfiguration(
        commandName: "install",
        abstract: "Generate a LaunchAgent plist for the current .x8.yml and bootstrap it."
    )

    @Option(
        name: .long,
        help: "Physical workspace directory to map to /^workspace, if different from the current directory."
    )
    var workspaceDirectory: String?

    @Option(
        name: .long,
        help: "Absolute path to the x8 binary to run under launchd. Defaults to the running executable."
    )
    var x8Path: String?

    @Option(
        name: .customLong("env"),
        parsing: .singleValue,
        help: "A KEY=VALUE pair to add to the LaunchAgent's environment, such as AWS_PROFILE=default. Repeatable."
    )
    var environment: [String] = []

    func run(context: X8CommandContext) async throws {
        let configuration = try await context.configuredStorage().configuration
        let agent = X8LaunchdAgent(profileID: configuration.profileID)
        let plan = try agent.installPlan(
            executablePath: Self.resolveExecutablePath(override: x8Path),
            workingDirectory: URL(
                filePath: FileManager.default.currentDirectoryPath,
                directoryHint: .isDirectory
            ),
            workspaceDirectory: workspaceDirectory.map {
                URL(filePath: $0, directoryHint: .isDirectory)
            },
            environment: environment.map(Self.parseEnvironmentPair)
        )

        for directory in agent.requiredDirectories {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        try plan.plistData.write(to: agent.plistURL)

        let uid = getuid()
        _ = try? await Launchctl.run(agent.bootoutArguments(uid: uid))
        let bootstrapResult = try await Launchctl.run(agent.bootstrapArguments(uid: uid))
        guard bootstrapResult.isSuccess else {
            throw LaunchdCommandError.launchctlFailed(
                arguments: agent.bootstrapArguments(uid: uid),
                output: bootstrapResult.standardError
            )
        }

        context.logger.info("✅ Installed \(agent.label) at \(agent.plistURL.path).", metadata: .color(.green))
        context.logger.info(
            "✅ Bootstrapped \(agent.serviceTarget(uid: uid)).",
            metadata: .color(.green)
        )
        context.output.standardOutput(
            "COMPILATION_CACHE_REMOTE_SERVICE_PATH=\(agent.socketPath)"
        )
    }

    private static func resolveExecutablePath(override: String?) throws -> String {
        if let override {
            return override
        }
        guard let executableURL = Bundle.main.executableURL else {
            throw ValidationError(
                "Could not resolve the running x8 binary's path. Pass --x8-path explicitly."
            )
        }
        return executableURL.path
    }

    private static func parseEnvironmentPair(_ pair: String) throws -> X8LaunchdAgent.EnvironmentPair {
        guard let separatorIndex = pair.firstIndex(of: "=") else {
            throw ValidationError("--env expects KEY=VALUE, got '\(pair)'.")
        }
        return X8LaunchdAgent.EnvironmentPair(
            key: String(pair[pair.startIndex ..< separatorIndex]),
            value: String(pair[pair.index(after: separatorIndex)...])
        )
    }
}

struct LaunchdUninstallCommand: X8ExecutableCommand {
    static let configuration = CommandConfiguration(
        commandName: "uninstall",
        abstract: "Bootout and remove the current .x8.yml's LaunchAgent."
    )

    func run(context: X8CommandContext) async throws {
        let configuration = try await context.configuredStorage().configuration
        let agent = X8LaunchdAgent(profileID: configuration.profileID)
        let uid = getuid()
        _ = try? await Launchctl.run(agent.bootoutArguments(uid: uid))
        try? FileManager.default.removeItem(at: agent.plistURL)
        context.logger.info("✅ Uninstalled \(agent.label).", metadata: .color(.green))
    }
}

struct LaunchdStatusCommand: X8ExecutableCommand {
    static let configuration = CommandConfiguration(
        commandName: "status",
        abstract: "Show launchd's status for the current .x8.yml's LaunchAgent."
    )

    func run(context: X8CommandContext) async throws {
        let configuration = try await context.configuredStorage().configuration
        let agent = X8LaunchdAgent(profileID: configuration.profileID)
        let uid = getuid()
        let result = try await Launchctl.run(agent.printArguments(uid: uid))
        guard result.isSuccess else {
            context.output.standardOutput("Not installed: \(agent.serviceTarget(uid: uid))")
            return
        }
        context.output.standardOutput(result.standardOutput ?? "")
    }
}

/// A `launchd` command failure, reported without ArgumentParser's usage banner.
enum LaunchdCommandError: Error, CustomStringConvertible {
    case launchctlFailed(arguments: [String], output: String?)

    var description: String {
        switch self {
        case let .launchctlFailed(arguments, output):
            "launchctl \(arguments.joined(separator: " ")) failed"
                + (output.map { ": \($0)" } ?? ".")
        }
    }
}

/// The external-process adapter for `launchctl` invocations.
enum Launchctl {
    /// One `launchctl` invocation's captured result.
    struct Result {
        let isSuccess: Bool
        let standardOutput: String?
        let standardError: String?
    }

    /// Runs `launchctl` with the given arguments and captures its output.
    static func run(_ arguments: [String]) async throws -> Result {
        let result = try await Subprocess.run(
            .name("launchctl"),
            arguments: Arguments(arguments),
            output: .string(limit: 16384),
            error: .string(limit: 16384)
        )
        let isSuccess = switch result.terminationStatus {
        case let .exited(status): status == 0
        #if !os(Windows)
            case .signaled: false
        #endif
        }
        return Result(
            isSuccess: isSuccess,
            standardOutput: result.standardOutput,
            standardError: result.standardError
        )
    }
}
