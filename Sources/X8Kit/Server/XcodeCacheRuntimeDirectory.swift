import FileManagerProtocol
import Foundation

/// Represents one private runtime directory and socket endpoint used by X8 runners.
///
/// Directories and socket endpoints receive restrictive `0700` permissions.
/// Removal is best-effort because it runs after server shutdown and must not
/// hide the original process or transport failure.
package struct XcodeCacheRuntimeDirectory: Sendable {
    static let socketFileName = "cache.sock"
    /// The live cache-event tail endpoint, separate from the Xcode protocol socket.
    static let eventsSocketFileName = "events.sock"
    let url: URL
    private static let permissions = 0o700

    private let fileManager: any FileManagerProtocol

    init(url: URL, fileManager: any FileManagerProtocol) {
        self.url = url
        self.fileManager = fileManager
    }

    /// The Unix socket endpoint inside this runtime directory.
    var socketURL: URL {
        url.appending(path: Self.socketFileName)
    }

    /// The live cache-event tail endpoint inside this runtime directory.
    var eventsSocketURL: URL {
        url.appending(path: Self.eventsSocketFileName)
    }

    /// Creates the directory and applies its private permissions.
    func create(withIntermediateDirectories: Bool) throws {
        try fileManager.createDirectory(
            at: url,
            withIntermediateDirectories: withIntermediateDirectories,
            attributes: [.posixPermissions: Self.permissions]
        )
        try fileManager.setAttributes(
            [.posixPermissions: Self.permissions],
            ofItemAtPath: url.path
        )
    }

    /// Applies the private permissions to the Unix socket created in this directory.
    func protectSocket() throws {
        try fileManager.setAttributes(
            [.posixPermissions: Self.permissions],
            ofItemAtPath: socketURL.path
        )
    }

    /// Removes only the socket endpoint without removing its parent directory.
    func removeSocket() {
        try? fileManager.removeItem(at: socketURL)
    }

    /// Removes only the events-tail socket endpoint, when one was ever bound.
    func removeEventsSocket() {
        try? fileManager.removeItem(at: eventsSocketURL)
    }

    /// Removes the socket and directory without masking the original failure.
    func remove() {
        removeSocket()
        try? fileManager.removeItem(at: url)
    }
}
