import ArgumentParser
import Foundation
import Subprocess
import System
import X8Kit
import X8Storage

struct XcodeBuildCommand: X8ExecutableCommand {
    /// Reached only through `X8RootCommand`'s `defaultSubcommand` fallback,
    /// so a leading `xcodebuild` (or a path ending in it) in `arguments` is
    /// never consumed as a subcommand selector. The command name must never
    /// equal `xcodebuild` or that invariant breaks; it is hidden because the
    /// root's `usage` already documents the invocation shape.
    static let configuration = CommandConfiguration(
        commandName: "xcode-build",
        abstract: "Run xcodebuild through an embedded X8 cache proxy.",
        usage: "x8 [--no-prefix-mapping] <xcodebuild> [<xcodebuild-argument> ...]",
        shouldDisplay: false
    )

    @Flag(
        name: .customLong("no-prefix-mapping"),
        help: """
        Do not inject SWIFT_ENABLE_PREFIX_MAPPING, SWIFT_ENABLE_PROJECT_PREFIX_MAPPING, \
        CLANG_ENABLE_PREFIX_MAPPING, CLANG_ENABLE_PROJECT_PREFIX_MAPPING, prefix values, \
        and the empty CLANG_MODULES_BUILD_SESSION_FILE. Only for a \
        project that sets these itself; without them a shared cache misses on every \
        machine whose DerivedData path differs. Must precede the xcodebuild argument.
        """
    )
    var noPrefixMapping = false

    @Argument(
        parsing: .captureForPassthrough,
        help: "Arguments forwarded to xcodebuild."
    )
    var arguments: [String] = []

    func run(context: X8CommandContext) async throws {
        let executable = try Self.parseExecutable(from: arguments)
        let buildArguments = XcodeBuildArguments(values: Array(arguments.dropFirst()))
        let prefixMapping: XcodeCachePrefixMapping = noPrefixMapping ? .disabled : .enabled
        let workingDirectory = URL(
            filePath: FileManager.default.currentDirectoryPath,
            directoryHint: .isDirectory
        )
        let configured = try await context.loadConfiguration()
        let configuration = configured.configuration
        try await configured.withStorage { storage in
            let cacheSession = try await XcodeCacheSession.start(
                casStore: storage.casStore(role: configuration.role),
                actionCacheStore: storage.actionCacheStore(role: configuration.role),
                prefixMapping: prefixMapping,
                workingDirectory: workingDirectory,
                responseDirectory: buildArguments.responseDirectory
            )
            let terminationStatus = try await Self.runXcodeBuild(
                executable: executable,
                arguments: buildArguments,
                cacheSettings: cacheSession.cacheEnvironment,
                cacheSession: cacheSession
            )
            guard terminationStatus == 0 else {
                throw ExitCode(terminationStatus)
            }
        }
    }

    /// Extracts the `xcodebuild` executable path from the leading forwarded argument.
    ///
    /// The first forwarded argument must resolve to `xcodebuild` by its last
    /// path component, so callers can pass a bare `xcodebuild` (resolved
    /// through `PATH`) or an absolute or relative path to a specific
    /// `xcodebuild` binary (e.g. one under a non-default Xcode.app).
    private static func parseExecutable(from arguments: [String]) throws -> Executable {
        guard let first = arguments.first else {
            throw ValidationError(
                "Expected the xcodebuild executable as the first argument, or a "
                    + "subcommand (serve, cache, config, stats, doctor). Run 'x8 --help' for usage."
            )
        }
        guard first.split(separator: "/").last == "xcodebuild" else {
            throw ValidationError(
                "The first argument must be 'xcodebuild' or a path ending in 'xcodebuild', got '\(first)'."
            )
        }
        if arguments.count >= 2, arguments[1] == "xcodebuild" {
            throw ValidationError(
                "x8 no longer takes a subcommand name before xcodebuild; drop the leading 'xcodebuild' "
                    + "(e.g. 'x8 xcodebuild -workspace ... build')."
            )
        }
        return first == "xcodebuild" ? .name(first) : .path(FilePath(first))
    }

    private static func runXcodeBuild(
        executable: Executable,
        arguments: XcodeBuildArguments,
        cacheSettings: [String: String],
        cacheSession: XcodeCacheSession
    ) async throws -> Int32 {
        // Xcode's build system resolves COMPILATION_CACHE_* and the
        // *_ENABLE_PREFIX_MAPPING settings as build settings, not as
        // inherited process environment variables. Appending them as
        // command-line `SETTING=VALUE` overrides is the form that actually
        // reaches SWBTaskConstruction. Overrides beat xcconfig, which is why
        // --no-prefix-mapping exists for projects that set those themselves.
        do {
            let result = try await Subprocess.run(
                executable,
                arguments: Arguments(
                    arguments.appending(cacheSettings: cacheSettings)
                ),
                output: .standardOutput,
                error: .standardError
            )
            await cacheSession.shutdown()
            return Self.exitStatus(for: result.terminationStatus)
        } catch {
            await cacheSession.shutdown()
            throw error
        }
    }

    private static func exitStatus(
        for terminationStatus: Subprocess.TerminationStatus
    ) -> Int32 {
        switch terminationStatus {
        case let .exited(status):
            status
        #if !os(Windows)
            case let .signaled(signal):
                128 + signal
        #endif
        }
    }
}
