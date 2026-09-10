import ArgumentParser
import X8Core
import X8Kit

struct StatsCommand: X8ExecutableCommand {
    static let configuration = CommandConfiguration(
        commandName: "stats",
        abstract: "Show cache traffic recorded by the standalone proxy.",
        shouldDisplay: false
    )

    func run(context: X8CommandContext) async throws {
        let result = try await Self.load(context: context)
        guard let snapshot = result.snapshot else {
            context.logger.info(
                "ℹ️ No metrics have been recorded for profile \(result.configuration.profileID).",
                metadata: .color(.yellow)
            )
            return
        }
        context.output.standardOutput(X8CacheMetricsPresentation.render(snapshot))
    }

    private static func load(context: X8CommandContext) async throws -> (
        configuration: X8CLIConfiguration<Void>,
        snapshot: X8CacheMetricsSnapshot?
    ) {
        let configuration = try await context.configuredStorage().configuration
        let snapshot = try await X8CommandSupport.mapped {
            try await X8CacheStatsRunner().load(profileID: configuration.profileID)
        }
        return (configuration, snapshot)
    }
}
