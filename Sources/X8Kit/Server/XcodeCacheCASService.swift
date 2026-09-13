import FileManagerProtocol
import Foundation
import GRPCCore
import X8Core
import X8Storage

/// Adapts the four Xcode CAS RPCs to the provider-neutral `CASStore` contract.
///
/// Request payloads arrive either inline or as a client-provided file path and
/// are exposed to storage as lazy `ByteStream` values. Read responses stay
/// inline when they fit the protocol adapter's bound, or are written to the
/// server-owned response-file store when Xcode requests disk-backed output.
/// Missing records are represented as protocol cache misses; storage errors
/// are translated into protocol error responses without selecting a backend.
struct XcodeCacheCASService: CompilationCacheService_Cas_V1_CASDBService.SimpleServiceProtocol, Sendable {
    private let casStore: any CASStore
    private let metrics: any X8CacheMetricsRecorder
    private let wire: XcodeCacheWire

    init(
        casStore: any CASStore,
        responseFileStore: XcodeCacheResponseFileStore? = nil,
        fileManager: any FileManagerProtocol = FileManager.default,
        metrics: any X8CacheMetricsRecorder = X8CacheMetricsStore()
    ) {
        self.casStore = casStore
        self.metrics = metrics
        wire = XcodeCacheWire(
            responseFileStore: responseFileStore,
            fileManager: fileManager
        )
    }

    func get(
        request: CompilationCacheService_Cas_V1_CASGetRequest,
        context: GRPCCore.ServerContext
    ) async throws -> CompilationCacheService_Cas_V1_CASGetResponse {
        let metricContext = X8CacheMetricContext(
            operation: .get,
            metrics: metrics,
            rpc: "cas.get",
            keyBytes: request.hasCasID ? request.casID.id : nil
        )
        let response = try await X8CacheServiceSupport.perform(
            context: context,
            operation: { try await performGet(request, metrics: metricContext) },
            errorResponse: XcodeCacheWire.casGetError
        )
        await metricContext.finish(outcome: Self.outcome(for: response.outcome))
        return response
    }

    func put(
        request: CompilationCacheService_Cas_V1_CASPutRequest,
        context: GRPCCore.ServerContext
    ) async throws -> CompilationCacheService_Cas_V1_CASPutResponse {
        let metricContext = X8CacheMetricContext(operation: .put, metrics: metrics, rpc: "cas.put")
        let response = try await X8CacheServiceSupport.perform(
            context: context,
            operation: { try await performPut(request, metrics: metricContext) },
            errorResponse: XcodeCacheWire.casPutError
        )
        await metricContext.finish(
            outcome: Self.outcome(for: response.contents),
            keyBytes: Self.keyBytes(for: response.contents)
        )
        return response
    }

    func load(
        request: CompilationCacheService_Cas_V1_CASLoadRequest,
        context: GRPCCore.ServerContext
    ) async throws -> CompilationCacheService_Cas_V1_CASLoadResponse {
        let metricContext = X8CacheMetricContext(
            operation: .get,
            metrics: metrics,
            rpc: "cas.load",
            keyBytes: request.hasCasID ? request.casID.id : nil
        )
        let response = try await X8CacheServiceSupport.perform(
            context: context,
            operation: { try await performLoad(request, metrics: metricContext) },
            errorResponse: XcodeCacheWire.casLoadError
        )
        await metricContext.finish(outcome: Self.outcome(for: response.outcome))
        return response
    }

    func save(
        request: CompilationCacheService_Cas_V1_CASSaveRequest,
        context: GRPCCore.ServerContext
    ) async throws -> CompilationCacheService_Cas_V1_CASSaveResponse {
        let metricContext = X8CacheMetricContext(operation: .put, metrics: metrics, rpc: "cas.save")
        let response = try await X8CacheServiceSupport.perform(
            context: context,
            operation: { try await performSave(request, metrics: metricContext) },
            errorResponse: XcodeCacheWire.casSaveError
        )
        await metricContext.finish(
            outcome: Self.outcome(for: response.contents),
            keyBytes: Self.keyBytes(for: response.contents)
        )
        return response
    }

    private func performGet(
        _ request: CompilationCacheService_Cas_V1_CASGetRequest,
        metrics: X8CacheMetricContext
    ) async throws -> CompilationCacheService_Cas_V1_CASGetResponse {
        guard request.hasCasID else {
            throw XcodeCacheServiceError.invalidRequest("CAS Get requires cas_id.")
        }
        let id = CASDataID(rawValue: request.casID.id)
        guard let object = try await casStore.get(id: id) else {
            var response = CompilationCacheService_Cas_V1_CASGetResponse()
            response.outcome = .objectNotFound
            return response
        }
        var response = CompilationCacheService_Cas_V1_CASGetResponse()
        response.outcome = .success
        response.data = try await wire.object(
            CASObject(
                bytes: metrics.observe(object.bytes),
                references: object.references
            ),
            writeToDisk: request.writeToDisk
        )
        return response
    }

    private func performPut(
        _ request: CompilationCacheService_Cas_V1_CASPutRequest,
        metrics: X8CacheMetricContext
    ) async throws -> CompilationCacheService_Cas_V1_CASPutResponse {
        guard request.hasData, request.data.hasBlob else {
            throw XcodeCacheServiceError.invalidRequest("CAS Put requires data.blob.")
        }
        let bytes = try metrics.observe(wire.stream(from: request.data.blob))
        let references = request.data.references.map { CASDataID(rawValue: $0.id) }
        let id = try await casStore.put(
            CASObject(
                bytes: bytes,
                references: references
            )
        )
        var response = CompilationCacheService_Cas_V1_CASPutResponse()
        response.casID = XcodeCacheWire.id(id)
        return response
    }

    private func performLoad(
        _ request: CompilationCacheService_Cas_V1_CASLoadRequest,
        metrics: X8CacheMetricContext
    ) async throws -> CompilationCacheService_Cas_V1_CASLoadResponse {
        guard request.hasCasID else {
            throw XcodeCacheServiceError.invalidRequest("CAS Load requires cas_id.")
        }
        let id = CASDataID(rawValue: request.casID.id)
        guard let bytes = try await casStore.load(id: id) else {
            var response = CompilationCacheService_Cas_V1_CASLoadResponse()
            response.outcome = .objectNotFound
            return response
        }
        var blob = CompilationCacheService_Cas_V1_CASBlob()
        blob.blob = try await wire.bytes(
            from: metrics.observe(bytes),
            writeToDisk: request.writeToDisk
        )
        var response = CompilationCacheService_Cas_V1_CASLoadResponse()
        response.outcome = .success
        response.data = blob
        return response
    }

    private func performSave(
        _ request: CompilationCacheService_Cas_V1_CASSaveRequest,
        metrics: X8CacheMetricContext
    ) async throws -> CompilationCacheService_Cas_V1_CASSaveResponse {
        guard request.hasData, request.data.hasBlob else {
            throw XcodeCacheServiceError.invalidRequest("CAS Save requires data.blob.")
        }
        let bytes = try metrics.observe(wire.stream(from: request.data.blob))
        let id = try await casStore.save(bytes)
        var response = CompilationCacheService_Cas_V1_CASSaveResponse()
        response.casID = XcodeCacheWire.id(id)
        return response
    }

    private static func outcome(
        for contents: CompilationCacheService_Cas_V1_CASPutResponse.OneOf_Contents?
    ) -> X8CacheMetricOutcome {
        if case .casID = contents {
            return .stored
        }
        return .remoteError
    }

    private static func outcome(
        for contents: CompilationCacheService_Cas_V1_CASSaveResponse.OneOf_Contents?
    ) -> X8CacheMetricOutcome {
        if case .casID = contents {
            return .stored
        }
        return .remoteError
    }

    private static func keyBytes(
        for contents: CompilationCacheService_Cas_V1_CASPutResponse.OneOf_Contents?
    ) -> Data? {
        guard case let .casID(id) = contents else { return nil }
        return id.id
    }

    private static func keyBytes(
        for contents: CompilationCacheService_Cas_V1_CASSaveResponse.OneOf_Contents?
    ) -> Data? {
        guard case let .casID(id) = contents else { return nil }
        return id.id
    }

    private static func outcome(
        for outcome: CompilationCacheService_Cas_V1_CASGetResponse.Outcome
    ) -> X8CacheMetricOutcome {
        switch outcome {
        case .success:
            .hit
        case .objectNotFound:
            .miss
        case .error, .UNRECOGNIZED:
            .remoteError
        }
    }

    private static func outcome(
        for outcome: CompilationCacheService_Cas_V1_CASLoadResponse.Outcome
    ) -> X8CacheMetricOutcome {
        switch outcome {
        case .success:
            .hit
        case .objectNotFound:
            .miss
        case .error, .UNRECOGNIZED:
            .remoteError
        }
    }
}
