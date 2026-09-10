import FileManagerProtocol
import Foundation
import X8Storage

/// Owns temporary files returned for disk-backed Xcode CAS responses.
///
/// Each `write(_:)` call creates a private `0600` file below the store's
/// directory and streams the response into it without retaining the complete
/// payload in memory. The returned path remains valid until `cleanup()` is
/// called. The cache server calls cleanup when its serving loop ends, so these
/// files are scoped to one server lifetime rather than becoming persistent
/// cache records.
struct XcodeCacheResponseFileStore: Sendable {
    private let directory: URL
    private let fileManager: any FileManagerProtocol

    init(
        directory: URL,
        fileManager: any FileManagerProtocol = FileManager.default
    ) {
        self.directory = directory
        self.fileManager = fileManager
    }

    /// Writes one response stream and returns a path owned by this store.
    func write(_ stream: ByteStream) async throws -> String {
        try makeDirectoryIfNeeded()

        let fileURL = directory.appending(path: UUID().uuidString)
        guard fileManager.createFile(
            atPath: fileURL.path,
            contents: nil,
            attributes: [.posixPermissions: 0o600]
        ) else {
            throw CocoaError(.fileWriteUnknown, userInfo: [NSURLErrorKey: fileURL])
        }

        do {
            let file = try FileHandle(forWritingTo: fileURL)
            // A close failure must not hide the stream error or a successful response.
            defer { try? file.close() }
            _ = try await ByteStreamSupport.write(stream, to: file)
            return fileURL.path
        } catch {
            // Preserve the write failure; the server owns this partial file and can remove it best effort.
            try? fileManager.removeItem(at: fileURL)
            throw error
        }
    }

    /// Removes all response files owned by this store.
    func cleanup() {
        // Cleanup follows server shutdown and must not replace the transport result.
        try? fileManager.removeItem(at: directory)
    }

    private func makeDirectoryIfNeeded() throws {
        try fileManager.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        try fileManager.setAttributes(
            [.posixPermissions: 0o700],
            ofItemAtPath: directory.path
        )
    }
}
