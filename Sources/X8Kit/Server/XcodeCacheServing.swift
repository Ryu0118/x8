import FileManagerProtocol
import X8Storage

/// The lifecycle boundary used by X8 cache-server coordinators.
///
/// A factory creates a configured instance without starting it. `serve()` then
/// owns the long-running transport loop: it accepts requests until graceful
/// shutdown is requested or a transport error occurs. The coordinator that
/// launched the loop is responsible for waiting on it and for removing the
/// endpoint after it stops.
package protocol XcodeCacheServing: Sendable {
    /// The Unix-domain socket path exposed while this server is serving.
    var socketPath: String { get }

    /// The optional recorder owned by a concrete server implementation.
    ///
    /// Test doubles may leave this unavailable; lifecycle code treats that as
    /// an empty observation rather than making metrics a protocol dependency.
    var metrics: (any X8CacheMetricsRecorder)? { get }

    /// Runs the serving loop until shutdown or a transport failure.
    ///
    /// This is a long-lived operation. A normal return means the server has
    /// finished draining after `beginGracefulShutdown()`; a thrown error means
    /// the transport could not continue. Callers should retain the returned
    /// session or handle until this operation has completed.
    func serve() async throws

    /// Requests non-blocking graceful shutdown of the serving loop.
    ///
    /// Implementations stop accepting new requests and drain requests already
    /// in flight. The method only sends the request; use the session or handle
    /// to await completion. Repeated calls must remain safe.
    func beginGracefulShutdown()
}

package extension XcodeCacheServing {
    var metrics: (any X8CacheMetricsRecorder)? {
        nil
    }
}

/// Creates a configured cache server for one endpoint and storage domain.
///
/// The factory is the composition boundary between the lifecycle coordinator
/// and a concrete server implementation. It receives provider-neutral CAS and
/// Action Cache stores, plus the filesystem dependency that the server passes
/// to its protocol services. The returned server must not begin serving until
/// its `serve()` method is called.
package typealias XcodeCacheServerFactory = @Sendable (
    String,
    any CASStore,
    any ActionCacheStore,
    any FileManagerProtocol
) -> any XcodeCacheServing

/// Creates a cache server around a listener already activated by launchd.
package typealias XcodeCacheActivatedServerFactory = @Sendable (
    String,
    Int,
    any CASStore,
    any ActionCacheStore,
    any FileManagerProtocol
) -> any XcodeCacheServing
