import ArgumentParser
import X8Kit

struct DoctorCommand: X8ExecutableCommand {
    static let configuration = CommandConfiguration(
        commandName: "doctor",
        abstract: "Check configuration, storage access, and the local proxy."
    )

    func run(context: X8CommandContext) async throws {
        let configured = try await context.loadConfiguration()
        let result = try await configured.withStorage { storage in
            try await X8Doctor().check(actionCacheStore: storage.actionCacheStore)
        }

        context.logger.info("✅ configuration: ok", metadata: .color(.green))
        context.logger.info(
            "credentials: \(configured.configuration.credentialSource)",
            metadata: .color(.green)
        )
        context.logger.info("✅ storage-read: ok", metadata: .color(.green))
        context.logger.info(
            "✅ protocol: ok (\(result.proxy.rpcMethodsExercised) unary RPCs)",
            metadata: .color(.green)
        )
        context.logger.info("✅ socket: ok \(result.proxy.socketPath)", metadata: .color(.green))
    }
}
