import AsyncOperations
import GRPCCore

/// An invalid request that cannot be represented as a provider operation.
enum XcodeCacheServiceError: Error {
    case invalidRequest(String)
}

/// Applies the shared cancellation and error-response policy to one RPC.
///
/// The helper races the storage operation against gRPC request cancellation.
/// Cancellation escapes as cancellation so the transport can stop work, while
/// non-cancellation failures are converted by the service-specific response
/// factory. This keeps the CAS and Action Cache adapters consistent.
enum X8CacheServiceSupport {
    /// Races each RPC against request cancellation and keeps cancellation out of the wire response.
    static func perform<Result: Sendable>(
        context: GRPCCore.ServerContext,
        operation: @escaping @Sendable () async throws -> Result,
        errorResponse: @escaping @Sendable (any Error) -> Result
    ) async throws -> Result {
        let resultBox = FirstResultBox<Result>()
        let events: [ServiceWaitEvent] = [.operation, .cancellation]
        _ = await events.asyncContains(numberOfConcurrentTasks: 2) { event in
            let outcome = await outcome(of: event, context: context, operation: operation)
            await resultBox.store(outcome)
            return true
        }

        do {
            return try await resolvedValue(from: resultBox)
        } catch {
            return try map(error: error, context: context, response: errorResponse)
        }
    }

    static func isCancellation(
        _ error: any Error,
        context: GRPCCore.ServerContext
    ) -> Bool {
        error is CancellationError || context.cancellation.isCancelled || Task.isCancelled
    }

    private static func resolvedValue<Result: Sendable>(
        from resultBox: FirstResultBox<Result>
    ) async throws -> Result {
        guard let outcome = await resultBox.value() else {
            throw CancellationError()
        }
        return try outcome.get()
    }

    private static func outcome<Result: Sendable>(
        of event: ServiceWaitEvent,
        context: GRPCCore.ServerContext,
        operation: @escaping @Sendable () async throws -> Result
    ) async -> Swift.Result<Result, any Error> {
        switch event {
        case .operation:
            await run(operation)
        case .cancellation:
            await waitForCancellation(context)
        }
    }

    private static func run<Result: Sendable>(
        _ operation: () async throws -> Result
    ) async -> Swift.Result<Result, any Error> {
        do {
            return try await .success(operation())
        } catch {
            return .failure(error)
        }
    }

    private static func waitForCancellation<Result: Sendable>(
        _ context: GRPCCore.ServerContext
    ) async -> Swift.Result<Result, any Error> {
        do {
            try await context.cancellation.cancelled
            return .failure(CancellationError())
        } catch {
            return .failure(error)
        }
    }

    private static func map<Result: Sendable>(
        error: any Error,
        context: GRPCCore.ServerContext,
        response: @Sendable (any Error) -> Result
    ) throws -> Result {
        guard !isCancellation(error, context: context) else {
            throw error
        }
        return response(error)
    }

    private enum ServiceWaitEvent: Sendable {
        case operation
        case cancellation
    }

    private actor FirstResultBox<Success: Sendable> {
        private var outcome: Swift.Result<Success, any Error>?

        func store(_ outcome: Swift.Result<Success, any Error>) {
            guard self.outcome == nil else { return }
            self.outcome = outcome
        }

        func value() -> Swift.Result<Success, any Error>? {
            outcome
        }
    }
}
