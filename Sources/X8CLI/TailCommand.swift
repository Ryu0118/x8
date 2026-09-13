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

        let stream: AsyncThrowingStream<String, any Error>
        do {
            stream = try await X8CacheEventsTailClient().connect(to: path)
        } catch {
            throw TailCommandError.eventsSocketUnavailable(
                profileID: configuration.profileID,
                path: path,
                underlying: error
            )
        }
        for try await line in stream {
            context.output.standardOutput(TailLineFormatter.render(line))
        }
    }
}

/// A `tail`-specific failure, reported without ArgumentParser's usage banner.
enum TailCommandError: Error, CustomStringConvertible {
    /// The events socket could not be reached, most likely because no `x8 serve` is running.
    case eventsSocketUnavailable(profileID: String, path: String, underlying: any Error)

    var description: String {
        switch self {
        case let .eventsSocketUnavailable(profileID, path, underlying):
            """
            Could not connect to the live cache-events socket at \(path).
            Is `x8 serve` running for profile \(profileID)? (\(underlying))
            """
        }
    }
}
