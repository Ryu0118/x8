import NIOCore
import NIOPosix

/// Probes a Unix socket path for a live listener using a real client connection.
///
/// A short-lived connect attempt is the only reliable signal that something
/// is actually accepting on the path: the file's mere existence says nothing
/// about whether the process that created it is still running.
package enum XcodeCacheSocketProbe {
    /// Returns whether a live listener answers at `path`.
    package static func isListening(at path: String) async -> Bool {
        do {
            let connection = try await ClientBootstrap(group: .singletonMultiThreadedEventLoopGroup)
                .connectTimeout(.milliseconds(200))
                .connect(unixDomainSocketPath: path)
                .get()
            connection.close(promise: nil)
            return true
        } catch {
            return false
        }
    }
}
