import FileManagerProtocol
import Foundation
import X8Core
import X8Storage

/// The proxy portion of the health check used by `x8 doctor`.
package struct X8DoctorProxyResult: Equatable, Sendable {
    /// The temporary socket used for the check.
    package let socketPath: String

    /// The number of unary RPC methods exercised successfully.
    package let rpcMethodsExercised: Int

    /// Creates a proxy health result.
    package init(socketPath: String, rpcMethodsExercised: Int) {
        self.socketPath = socketPath
        self.rpcMethodsExercised = rpcMethodsExercised
    }
}

/// The successful result of the complete `x8 doctor` check.
package struct X8DoctorResult: Equatable, Sendable {
    /// The local proxy result. A returned value also implies the storage read passed.
    package let proxy: X8DoctorProxyResult

    /// Creates a doctor result.
    package init(proxy: X8DoctorProxyResult) {
        self.proxy = proxy
    }
}

/// Performs backend-neutral checks on X8's local protocol proxy.
package struct X8Doctor: Sendable {
    /// Creates a doctor.
    package init() {}

    /// Runs the complete backend-neutral doctor check.
    ///
    /// The proxy is exercised against an in-memory store, then the supplied
    /// Action Cache store receives one read-only probe using a unique key. A
    /// successful return therefore proves both the local six-RPC adapter and
    /// the storage read path without mutating the remote cache.
    ///
    /// - Parameters:
    ///   - actionCacheStore: The configured storage implementation to probe.
    ///   - fileManager: The filesystem dependency used by the temporary proxy.
    /// - Returns: The successful proxy result. The storage read is also known
    ///   to have succeeded when this returns.
    /// - Throws: If the proxy cannot start, its protocol probe fails, or the
    ///   storage read fails.
    package func check(
        actionCacheStore: any ActionCacheStore,
        fileManager: any FileManagerProtocol = FileManager.default
    ) async throws -> X8DoctorResult {
        let proxy = try await checkProxy(fileManager: fileManager)
        _ = try await actionCacheStore.getValue(
            for: ActionCacheKey(
                rawValue: Data("x8-doctor-\(UUID().uuidString)".utf8)
            )
        )
        return X8DoctorResult(proxy: proxy)
    }

    /// Starts a temporary in-memory proxy and verifies all six RPCs.
    ///
    /// This check does not contact an object store and does not retain the
    /// temporary socket. A frontend may combine its result with a backend
    /// connectivity check appropriate for the selected storage trait.
    package func checkProxy(
        fileManager: any FileManagerProtocol = FileManager.default
    ) async throws -> X8DoctorProxyResult {
        let storage = InMemoryStorage()
        let session = try await XcodeCacheSession.start(
            casStore: storage,
            actionCacheStore: storage,
            fileManager: fileManager
        )
        do {
            let rpcMethodsExercised = try await XcodeCacheProtocolProbe().verify(
                socketPath: session.socketPath
            )
            let result = X8DoctorProxyResult(
                socketPath: session.socketPath,
                rpcMethodsExercised: rpcMethodsExercised
            )
            await session.shutdown()
            return result
        } catch {
            await session.shutdown()
            throw error
        }
    }
}
