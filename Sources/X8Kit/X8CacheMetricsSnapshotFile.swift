import FileManagerProtocol
import Foundation

/// Reads and writes one persisted metrics snapshot through an injected filesystem.
package struct X8CacheMetricsSnapshotFile: Sendable {
    private let fileManager: any FileManagerProtocol

    /// Creates a snapshot file boundary.
    package init(fileManager: any FileManagerProtocol = FileManager.default) {
        self.fileManager = fileManager
    }

    /// Reads a snapshot, returning nil when the file has not been written yet.
    package func read(from url: URL) async throws -> X8CacheMetricsSnapshot? {
        guard let data = fileManager.contents(atPath: url.path) else { return nil }
        return try JSONDecoder().decode(X8CacheMetricsSnapshot.self, from: data)
    }

    /// Replaces the snapshot file with the supplied aggregate.
    package func write(
        _ snapshot: X8CacheMetricsSnapshot,
        to url: URL
    ) async throws {
        let data = try JSONEncoder().encode(snapshot)
        // FileManagerProtocol has no atomic replacement operation; remove first
        // so a successful create never leaves a stale snapshot behind.
        try? fileManager.removeItem(at: url)
        guard fileManager.createFile(atPath: url.path, contents: data, attributes: nil) else {
            throw CocoaError(.fileWriteUnknown, userInfo: [NSURLErrorKey: url])
        }
    }
}
