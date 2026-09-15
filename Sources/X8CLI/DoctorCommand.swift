import ArgumentParser
import Foundation
import X8Core
import X8Kit

struct DoctorCommand: X8ExecutableCommand {
    static let configuration = CommandConfiguration(
        commandName: "doctor",
        abstract: "Check configuration, storage access, and the local proxy."
    )

    /// Runs each check independently so a failure names the step it happened
    /// in and reports every step that already succeeded, instead of stopping
    /// at the first thrown error with no context about which check it came
    /// from (for example, a bare "AccessDenied" that could otherwise mean a
    /// misconfigured profile, an unauthorized credential, or a proxy fault).
    func run(context: X8CommandContext) async throws {
        let configured = try await context.loadConfiguration()
        context.logger.info("✅ configuration: ok", metadata: .color(.green))
        context.logger.info(
            "credentials: \(configured.configuration.credentialSource)",
            metadata: .color(.green)
        )

        try await configured.withStorage { storage in
            let proxy = try await Self.step(context, "protocol") {
                try await X8Doctor().checkProxy()
            }
            context.logger.info(
                "✅ protocol: ok (\(proxy.rpcMethodsExercised) unary RPCs)",
                metadata: .color(.green)
            )
            context.logger.info("✅ socket: ok \(proxy.socketPath)", metadata: .color(.green))

            _ = try await Self.step(context, "storage-read") {
                try await storage.actionCacheStore.getValue(
                    for: ActionCacheKey(rawValue: Data("x8-doctor-\(UUID().uuidString)".utf8))
                )
            }
            context.logger.info("✅ storage-read: ok", metadata: .color(.green))
        }
    }

    /// Runs one named check, reporting which step failed before rethrowing.
    ///
    /// The original error is preserved (not stringified into a new type) so
    /// exit-code mapping and any diagnostic detail it carries reach the user
    /// unchanged; only the step name is added as context.
    private static func step<Result>(
        _ context: X8CommandContext,
        _ name: String,
        _ operation: () async throws -> Result
    ) async throws -> Result {
        do {
            return try await operation()
        } catch {
            context.logger.error(
                "❌ \(name): failed - \(X8CommandSupport.message(for: error))",
                metadata: .color(.red)
            )
            throw error
        }
    }
}
