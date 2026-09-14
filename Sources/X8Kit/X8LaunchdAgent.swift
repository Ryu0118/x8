import FileManagerProtocol
import Foundation

/// A launchd `Sockets`-activated LaunchAgent's identity for one X8 serve profile.
///
/// The `Sockets.Listener` path in ``installPlan(executablePath:workingDirectory:workspaceDirectory:environment:)``
/// is always ``XcodeServeRunner/defaultSocketPath(profileID:)``, so the plist's endpoint
/// and the path `x8 serve` prints as `COMPILATION_CACHE_REMOTE_SERVICE_PATH` can never
/// drift apart. Callers that hand-authored a LaunchAgent before this type existed must
/// not point `SockPathName` anywhere else.
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

    /// What an install needs beyond this agent's identity: where `x8` lives, the
    /// directory containing `.x8.yml`, and everything else the plist template varies.
    public struct InstallPlan: Sendable {
        /// The encoded plist document, ready to write to ``X8LaunchdAgent/plistURL``.
        public let plistData: Data
    }

    private let profileID: String
    private let fileManager: any FileManagerProtocolMacOS

    /// Creates an identity for one profile's LaunchAgent.
    ///
    /// - Parameters:
    ///   - profileID: The storage profile whose stable socket path this agent serves.
    ///   - fileManager: Filesystem dependency used to resolve well-known directories.
    public init(
        profileID: String,
        fileManager: any FileManagerProtocolMacOS = FileManager.default
    ) {
        self.profileID = profileID
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

    /// Directories that must exist before the plist is written or bootstrapped.
    public var requiredDirectories: [URL] {
        [
            plistURL.deletingLastPathComponent(),
            URL(filePath: socketPath).deletingLastPathComponent(),
            logDirectory,
        ]
    }

    /// Plans the plist an install writes to ``plistURL``.
    ///
    /// - Parameters:
    ///   - executablePath: The absolute path to the `x8` binary `ProgramArguments[0]` runs.
    ///   - workingDirectory: The directory containing `.x8.yml`, used as the LaunchAgent's
    ///     `WorkingDirectory`.
    ///   - workspaceDirectory: Forwarded as `x8 serve`'s `--workspace-directory`, when the
    ///     Xcode workspace root differs from `workingDirectory`.
    ///   - environment: Extra `EnvironmentVariables` entries, such as `AWS_PROFILE`; never
    ///     captured automatically from the caller's process environment.
    public func installPlan(
        executablePath: String,
        workingDirectory: URL,
        workspaceDirectory: URL? = nil,
        environment: [EnvironmentPair] = []
    ) throws -> InstallPlan {
        var arguments = [executablePath, "serve", "--launchd", "--no-print-cache-settings"]
        if let workspaceDirectory {
            arguments += ["--workspace-directory", workspaceDirectory.path]
        }
        let document = X8LaunchdPlistDocument(
            label: label,
            programArguments: arguments,
            workingDirectory: workingDirectory.path,
            socketPathName: socketPath,
            standardOutPath: logDirectory.appending(path: "\(label).out.log").path,
            standardErrorPath: logDirectory.appending(path: "\(label).err.log").path,
            environmentVariables: [EnvironmentPair(key: "PATH", value: "/usr/bin:/bin:/usr/sbin:/sbin")]
                + environment
        )
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .xml
        return try InstallPlan(plistData: encoder.encode(document))
    }

    private var logDirectory: URL {
        fileManager.homeDirectoryForCurrentUser.appending(path: "Library/Logs/X8")
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
