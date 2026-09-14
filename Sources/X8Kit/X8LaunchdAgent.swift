import FileManagerProtocol
import Foundation

/// A launchd `Sockets`-activated LaunchAgent for one X8 serve profile.
///
/// The `Sockets.Listener` path is always ``XcodeServeRunner/defaultSocketPath(profileID:)``,
/// so the plist's endpoint and the path `x8 serve` prints as
/// `COMPILATION_CACHE_REMOTE_SERVICE_PATH` can never drift apart. Callers
/// that hand-authored a LaunchAgent before this type existed must not point
/// `SockPathName` anywhere else.
public struct X8LaunchdAgent: Sendable {
    /// One `KEY=VALUE` environment pair for the LaunchAgent's `EnvironmentVariables`.
    public struct EnvironmentPair: Sendable, Equatable {
        /// The environment variable's name.
        public let key: String
        /// The environment variable's value.
        public let value: String

        /// Creates one `KEY=VALUE` pair.
        public init(key: String, value: String) {
            self.key = key
            self.value = value
        }
    }

    private let profileID: String
    private let executablePath: String
    private let workingDirectory: URL
    private let workspaceDirectory: URL?
    private let environment: [EnvironmentPair]
    private let fileManager: any FileManagerProtocolMacOS

    /// Creates a planner for one profile's LaunchAgent.
    ///
    /// - Parameters:
    ///   - profileID: The storage profile whose stable socket path this agent serves.
    ///   - executablePath: The absolute path to the `x8` binary `ProgramArguments[0]` runs.
    ///   - workingDirectory: The directory containing `.x8.yml`, used as the LaunchAgent's
    ///     `WorkingDirectory`.
    ///   - workspaceDirectory: Forwarded as `x8 serve`'s `--workspace-directory`, when the
    ///     Xcode workspace root differs from `workingDirectory`.
    ///   - environment: Extra `EnvironmentVariables` entries, such as `AWS_PROFILE`; never
    ///     captured automatically from the caller's process environment.
    ///   - fileManager: Filesystem dependency used to resolve well-known directories.
    public init(
        profileID: String,
        executablePath: String,
        workingDirectory: URL,
        workspaceDirectory: URL? = nil,
        environment: [EnvironmentPair] = [],
        fileManager: any FileManagerProtocolMacOS = FileManager.default
    ) {
        self.profileID = profileID
        self.executablePath = executablePath
        self.workingDirectory = workingDirectory
        self.workspaceDirectory = workspaceDirectory
        self.environment = environment
        self.fileManager = fileManager
    }

    /// The reverse-DNS LaunchAgent label, unique per profile.
    public var label: String {
        "com.x8.\(profileID)"
    }

    /// The plist path this agent is installed to.
    public var plistURL: URL {
        fileManager.homeDirectoryForCurrentUser
            .appending(path: "Library/LaunchAgents")
            .appending(path: "\(label).plist")
    }

    /// The stable socket path launchd binds and hands to `x8 serve --launchd`.
    public var socketPath: String {
        XcodeServeRunner.defaultSocketPath(profileID: profileID, fileManager: fileManager)
    }

    /// The `launchctl` service target, `gui/<uid>/<label>`.
    public func serviceTarget(uid: UInt32) -> String {
        "gui/\(uid)/\(label)"
    }

    /// Directories that must exist before the plist is written or bootstrapped.
    public var requiredDirectories: [URL] {
        [
            plistURL.deletingLastPathComponent(),
            URL(filePath: socketPath).deletingLastPathComponent(),
            logDirectory,
        ]
    }

    /// The encoded plist document, ready to write to ``plistURL``.
    public func plistData() throws -> Data {
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .xml
        return try encoder.encode(document)
    }

    /// `launchctl bootstrap gui/<uid> <plistURL>` arguments, excluding `launchctl` itself.
    public func bootstrapArguments(uid: UInt32) -> [String] {
        ["bootstrap", "gui/\(uid)", plistURL.path]
    }

    /// `launchctl bootout <target>` arguments, excluding `launchctl` itself.
    public func bootoutArguments(uid: UInt32) -> [String] {
        ["bootout", serviceTarget(uid: uid)]
    }

    /// `launchctl enable <target>` arguments, excluding `launchctl` itself.
    public func enableArguments(uid: UInt32) -> [String] {
        ["enable", serviceTarget(uid: uid)]
    }

    /// `launchctl print <target>` arguments, excluding `launchctl` itself.
    public func printArguments(uid: UInt32) -> [String] {
        ["print", serviceTarget(uid: uid)]
    }

    private var logDirectory: URL {
        fileManager.homeDirectoryForCurrentUser.appending(path: "Library/Logs/X8")
    }

    private var programArguments: [String] {
        var arguments = [executablePath, "serve", "--launchd", "--no-print-cache-settings"]
        if let workspaceDirectory {
            arguments += ["--workspace-directory", workspaceDirectory.path]
        }
        return arguments
    }

    private var document: X8LaunchdPlistDocument {
        X8LaunchdPlistDocument(
            label: label,
            programArguments: programArguments,
            workingDirectory: workingDirectory.path,
            socketPathName: socketPath,
            standardOutPath: logDirectory.appending(path: "\(label).out.log").path,
            standardErrorPath: logDirectory.appending(path: "\(label).err.log").path,
            environmentVariables: [EnvironmentPair(key: "PATH", value: "/usr/bin:/bin:/usr/sbin:/sbin")]
                + environment
        )
    }
}

/// The `Codable` shape of a launchd `Sockets`-activated LaunchAgent plist.
///
/// Kept separate from `X8LaunchdAgent` so its `CodingKeys` carry the exact
/// plist key spelling without leaking that concern into the public planner API.
private struct X8LaunchdPlistDocument: Encodable {
    struct SocketsDictionary: Encodable {
        struct Listener: Encodable {
            let sockFamily = "Unix"
            let sockType = "stream"
            let sockPathName: String
            let sockPathMode = 0o600

            enum CodingKeys: String, CodingKey {
                case sockFamily = "SockFamily"
                case sockType = "SockType"
                case sockPathName = "SockPathName"
                case sockPathMode = "SockPathMode"
            }
        }

        let listener: Listener

        enum CodingKeys: String, CodingKey {
            case listener = "Listener"
        }
    }

    let label: String
    let programArguments: [String]
    let workingDirectory: String
    let sockets: SocketsDictionary
    let processType = "Interactive"
    let standardOutPath: String
    let standardErrorPath: String
    let environmentVariables: [String: String]

    init(
        label: String,
        programArguments: [String],
        workingDirectory: String,
        socketPathName: String,
        standardOutPath: String,
        standardErrorPath: String,
        environmentVariables: [X8LaunchdAgent.EnvironmentPair]
    ) {
        self.label = label
        self.programArguments = programArguments
        self.workingDirectory = workingDirectory
        sockets = SocketsDictionary(listener: .init(sockPathName: socketPathName))
        self.standardOutPath = standardOutPath
        self.standardErrorPath = standardErrorPath
        self.environmentVariables = Dictionary(
            environmentVariables.map { ($0.key, $0.value) },
            uniquingKeysWith: { _, last in last }
        )
    }

    enum CodingKeys: String, CodingKey {
        case label = "Label"
        case programArguments = "ProgramArguments"
        case workingDirectory = "WorkingDirectory"
        case sockets = "Sockets"
        case processType = "ProcessType"
        case standardOutPath = "StandardOutPath"
        case standardErrorPath = "StandardErrorPath"
        case environmentVariables = "EnvironmentVariables"
    }
}
