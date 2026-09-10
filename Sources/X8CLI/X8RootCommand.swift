import ArgumentParser

struct X8RootCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "x8",
        abstract: "Run Xcode compilation-cache commands.",
        version: X8Version.current,
        subcommands: [
            XcodeBuildCommand.self,
            ServeCommand.self,
            CacheCommand.self,
            ConfigCommand.self,
            StatsCommand.self,
            DoctorCommand.self,
        ],
        defaultSubcommand: XcodeBuildCommand.self
    )
}
