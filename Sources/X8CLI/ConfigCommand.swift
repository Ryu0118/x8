import ArgumentParser

struct ConfigCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "config",
        abstract: "Validate and inspect repository configuration.",
        subcommands: [ConfigValidateCommand.self, ConfigShowCommand.self]
    )
}

struct ConfigValidateCommand: X8ExecutableCommand {
    static let configuration = CommandConfiguration(
        commandName: "validate",
        abstract: "Validate the selected storage configuration."
    )

    func run(context: X8CommandContext) async throws {
        _ = try await context.configuredStorage()
        context.logger.info("✅ Configuration is valid.", metadata: .color(.green))
    }
}

struct ConfigShowCommand: X8ExecutableCommand {
    static let configuration = CommandConfiguration(
        commandName: "show",
        abstract: "Show resolved non-secret configuration."
    )

    func run(context: X8CommandContext) async throws {
        let configuration = try await context.configuredStorage()
        context.output.standardOutput(
            configuration.configuration.displayFields.map { "\($0.key)=\($0.value)" }.joined(separator: "\n")
        )
    }
}
