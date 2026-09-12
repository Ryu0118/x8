import FileManagerProtocol
import Foundation

/// Loads the last persisted metrics snapshot for one X8 serve profile.
///
/// This runner owns the profile-path convention and filesystem read. It does
/// not start a server or attempt to contact the cache backend, so `stats`
/// remains a read-only diagnostic command.
///
/// The snapshot describes remote-cache traffic X8 observed directly. An
/// Xcode build-system decision such as "up to date" is not a cache hit
/// unless the proxy also observed the corresponding storage hit.
public struct X8CacheStatsRunner: Sendable {
    private let fileManager: any FileManagerProtocolMacOS

    /// Creates a stats runner with an injectable filesystem dependency.
    public init(
        fileManager: any FileManagerProtocolMacOS = FileManager.default
    ) {
        self.fileManager = fileManager
    }

    /// Reads the last completed snapshot for a serve profile.
    ///
    /// - Parameter profileID: The resolved non-secret storage-profile ID.
    /// - Returns: The persisted snapshot, or `nil` when the profile has not
    ///   completed a metrics-bearing session yet.
    /// - Throws: If the snapshot exists but cannot be decoded or read.
    public func load(profileID: String) async throws -> X8CacheMetricsSnapshot? {
        let url = XcodeServeRunner.defaultMetricsFileURL(
            profileID: profileID,
            fileManager: fileManager
        )
        return try await X8CacheMetricsSnapshotFile(fileManager: fileManager).read(from: url)
    }
}
