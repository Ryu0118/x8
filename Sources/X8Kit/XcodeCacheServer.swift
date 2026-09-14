import FileManagerProtocol
import Foundation
import GRPCCore
import GRPCNIOTransportHTTP2
import X8Storage

/// Serves Xcode's compilation-cache RPCs on a Unix-domain socket.
///
/// The server owns the concrete gRPC transport and adapts CAS and Action Cache
/// requests to the provider-neutral storage protocols. `serve()` starts the
/// long-lived accept loop and does not return until the transport has stopped;
/// `beginGracefulShutdown()` requests that new requests stop while in-flight
/// requests drain. Response files created for disk-backed CAS responses are
/// owned by this server and cleaned up when `serve()` returns.
///
/// The server does not own the lifetime or policy of the supplied storage
/// implementations. Its lifecycle is managed by `XcodeCacheServerSession` or
/// another caller using the `XcodeCacheServing` boundary.
public final class XcodeCacheServer: XcodeCacheServing, Sendable {
    /// The socket path owned by this server.
    public let socketPath: String

    private let server: GRPCServer<HTTP2ServerTransport.Posix>
    private let responseFileStore: XcodeCacheResponseFileStore

    private let metricsRecorder: any X8CacheMetricsRecorder

    /// Builds the live factory shared by runners that start the built-in gRPC server.
    ///
    /// - Parameter responseDirectory: Where disk-backed CAS response files are
    ///   staged. Xcode's compilation-cache plugin links these files into
    ///   DerivedData; a directory on a different filesystem than DerivedData
    ///   makes that link fail with `EXDEV`. Pass the DerivedData root (or a
    ///   directory known to share its volume) when it might differ from the
    ///   socket's volume. `nil` keeps the response directory next to the
    ///   socket, which is correct whenever both live under the same home
    ///   volume.
    package static func liveFactory(
        responseDirectory: URL? = nil,
        metrics: any X8CacheMetricsRecorder = X8CacheMetricsStore()
    ) -> XcodeCacheServerFactory {
        { socketPath, casStore, actionCacheStore, fileManager in
            XcodeCacheServer(
                socketPath: socketPath,
                casStore: casStore,
                actionCacheStore: actionCacheStore,
                fileManager: fileManager,
                metrics: metrics,
                responseDirectory: responseDirectory
            )
        }
    }

    /// The metrics recorder shared by the CAS and Action Cache services.
    ///
    /// Declared as the protocol's optional type so this witnesses
    /// `XcodeCacheServing.metrics` directly; a non-optional stored property of
    /// a different type does not satisfy an optional protocol requirement and
    /// silently falls back to the `nil`-returning default implementation.
    package var metrics: (any X8CacheMetricsRecorder)? {
        metricsRecorder
    }

    /// Creates a plaintext HTTP/2 server for the Xcode cache protocol.
    ///
    /// - Parameters:
    ///   - socketPath: The local Unix-domain socket endpoint.
    ///   - casStore: The CAS implementation served by this endpoint.
    ///   - actionCacheStore: The Action Cache implementation served by this endpoint.
    ///   - fileManager: Filesystem dependency used for response files and cleanup.
    ///   - metrics: The recorder receiving cache traffic observations.
    ///   - responseDirectory: See `liveFactory(responseDirectory:)`. `nil`
    ///     stages response files next to the socket.
    public convenience init(
        socketPath: String,
        casStore: any CASStore,
        actionCacheStore: any ActionCacheStore,
        fileManager: any FileManagerProtocol = FileManager.default,
        metrics: any X8CacheMetricsRecorder = X8CacheMetricsStore(),
        responseDirectory: URL? = nil
    ) {
        let transport = HTTP2ServerTransport.Posix(
            address: .unixDomainSocket(path: socketPath),
            transportSecurity: .plaintext
        )
        self.init(
            socketPath: socketPath,
            transport: transport,
            casStore: casStore,
            actionCacheStore: actionCacheStore,
            fileManager: fileManager,
            metrics: metrics,
            responseDirectory: responseDirectory
        )
    }

    private init(
        socketPath: String,
        transport: HTTP2ServerTransport.Posix,
        casStore: any CASStore,
        actionCacheStore: any ActionCacheStore,
        fileManager: any FileManagerProtocol,
        metrics: any X8CacheMetricsRecorder,
        responseDirectory: URL?
    ) {
        self.socketPath = socketPath
        metricsRecorder = metrics
        let responseFileStore = XcodeCacheResponseFileStore(
            directory: (responseDirectory ?? URL(filePath: socketPath).deletingLastPathComponent())
                .appending(path: "responses"),
            fileManager: fileManager
        )
        server = GRPCServer(
            transport: transport,
            services: [
                XcodeCacheCASService(
                    casStore: casStore,
                    responseFileStore: responseFileStore,
                    fileManager: fileManager,
                    metrics: metrics
                ),
                XcodeCacheActionCacheService(
                    actionCacheStore: actionCacheStore,
                    metrics: metrics
                ),
            ]
        )
        self.responseFileStore = responseFileStore
    }

    /// Starts serving requests until graceful shutdown or transport failure.
    ///
    /// The method is long-lived and performs response-file cleanup on every
    /// exit path. The server socket becomes usable during this operation; the
    /// lifecycle coordinator is responsible for waiting until it appears.
    public func serve() async throws {
        defer { responseFileStore.cleanup() }
        try await server.serve()
    }

    /// Requests non-blocking shutdown and draining of in-flight requests.
    ///
    /// Completion is observed by awaiting `serve()` through the owning session
    /// or handle. Calling this method more than once is safe.
    public func beginGracefulShutdown() {
        server.beginGracefulShutdown()
    }
}
