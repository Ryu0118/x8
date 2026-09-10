import ArgumentParser
import Logging

protocol X8ExecutableCommand: ParsableCommand {
    func run(context: X8CommandContext) async throws
}

struct X8CommandContext: Sendable {
    let loadConfiguration: @Sendable () async throws -> X8ConfiguredStorage
    let output: X8CLIOutput
    let logger: Logger

    init(
        loadConfiguration: @escaping @Sendable () async throws -> X8ConfiguredStorage,
        output: X8CLIOutput
    ) {
        self.loadConfiguration = loadConfiguration
        self.output = output
        logger = X8Logging.makeLogger(writeLine: output.standardError)
    }

    /// Resolves configuration, reporting a caller-supplied failure as a `ValidationError`.
    func configuredStorage() async throws -> X8ConfiguredStorage {
        try await X8CommandSupport.mapped(loadConfiguration)
    }
}
