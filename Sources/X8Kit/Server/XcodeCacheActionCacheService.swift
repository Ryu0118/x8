import GRPCCore
import X8Core
import X8Storage

/// Adapts the two Xcode `KeyValueDB` RPCs to `ActionCacheStore`.
///
/// The service preserves Action Cache keys and entry bytes as opaque values.
/// A missing value becomes the wire-level `keyNotFound` outcome, while storage
/// failures become protocol errors. It contains no persistence policy and is
/// reusable with any implementation of the storage protocol.
struct XcodeCacheActionCacheService: CompilationCacheService_Keyvalue_V1_KeyValueDB.SimpleServiceProtocol, Sendable {
    private let actionCacheStore: any ActionCacheStore
    private let metrics: any X8CacheMetricsRecorder

    init(
        actionCacheStore: any ActionCacheStore,
        metrics: any X8CacheMetricsRecorder = X8CacheMetricsStore()
    ) {
        self.actionCacheStore = actionCacheStore
        self.metrics = metrics
    }

    func getValue(
        request: CompilationCacheService_Keyvalue_V1_GetValueRequest,
        context: GRPCCore.ServerContext
    ) async throws -> CompilationCacheService_Keyvalue_V1_GetValueResponse {
        let metricContext = X8CacheMetricContext(
            operation: .get,
            metrics: metrics,
            rpc: "kv.getValue",
            keyBytes: request.key
        )
        let response = try await X8CacheServiceSupport.perform(
            context: context,
            operation: { try await performGetValue(request, metrics: metricContext) },
            errorResponse: XcodeCacheWire.keyValueGetError
        )
        await metricContext.finish(outcome: Self.outcome(for: response.outcome))
        return response
    }

    func putValue(
        request: CompilationCacheService_Keyvalue_V1_PutValueRequest,
        context: GRPCCore.ServerContext
    ) async throws -> CompilationCacheService_Keyvalue_V1_PutValueResponse {
        let metricContext = X8CacheMetricContext(
            operation: .put,
            metrics: metrics,
            rpc: "kv.putValue",
            keyBytes: request.key
        )
        let response = try await X8CacheServiceSupport.perform(
            context: context,
            operation: { try await performPutValue(request, metrics: metricContext) },
            errorResponse: XcodeCacheWire.keyValuePutError
        )
        await metricContext.finish(outcome: response.hasError ? .remoteError : .stored)
        return response
    }

    private func performGetValue(
        _ request: CompilationCacheService_Keyvalue_V1_GetValueRequest,
        metrics: X8CacheMetricContext
    ) async throws -> CompilationCacheService_Keyvalue_V1_GetValueResponse {
        let key = ActionCacheKey(rawValue: request.key)
        guard let value = try await actionCacheStore.getValue(for: key) else {
            var response = CompilationCacheService_Keyvalue_V1_GetValueResponse()
            response.outcome = .keyNotFound
            return response
        }
        await metrics.observe(value)
        var response = CompilationCacheService_Keyvalue_V1_GetValueResponse()
        response.outcome = .success
        response.value.entries = value.entries
        return response
    }

    private func performPutValue(
        _ request: CompilationCacheService_Keyvalue_V1_PutValueRequest,
        metrics: X8CacheMetricContext
    ) async throws -> CompilationCacheService_Keyvalue_V1_PutValueResponse {
        guard request.hasValue else {
            throw XcodeCacheServiceError.invalidRequest("PutValue requires value.")
        }
        let value = ActionCacheValue(entries: request.value.entries)
        await metrics.observe(value)
        try await actionCacheStore.putValue(
            value,
            for: ActionCacheKey(rawValue: request.key)
        )
        return CompilationCacheService_Keyvalue_V1_PutValueResponse()
    }

    private static func outcome(
        for outcome: CompilationCacheService_Keyvalue_V1_GetValueResponse.Outcome
    ) -> X8CacheMetricOutcome {
        switch outcome {
        case .success:
            .hit
        case .keyNotFound:
            .miss
        case .error, .UNRECOGNIZED:
            .remoteError
        }
    }
}
