import ArgumentParser
import X8Kit

struct TailCommand: X8ExecutableCommand {
    static let configuration = CommandConfiguration(
        commandName: "tail",
        abstract: "Stream live cache traffic from a running standalone proxy."
    )

    func run(context: X8CommandContext) async throws {
        let configuration = try await context.configuredStorage().configuration
        let path = XcodeServeRunner.defaultEventsSocketURL(profileID: configuration.profileID).path

        let stream = try await X8CommandSupport.mapped {
            try await X8CacheEventsTailClient().connect(to: path)
        }
        for try await line in stream {
            context.output.standardOutput(TailLineFormatter.render(line))
        }
    }
}
