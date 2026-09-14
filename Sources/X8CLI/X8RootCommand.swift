import ArgumentParser

struct X8RootCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "x8",
        abstract: "Run Xcode compilation-cache commands.",
        usage: """
        x8 [--no-prefix-mapping] <xcodebuild> [<xcodebuild-argument> ...]
        x8 <subcommand>
        """,
        discussion: """
        Pass 'xcodebuild', or a path to a specific xcodebuild binary, as the \
        first argument to run that build through an invocation-scoped cache \
        proxy. Every later argument is forwarded to xcodebuild unchanged. \
        --no-prefix-mapping must come before the xcodebuild argument.
        """,
        version: X8Version.current,
        subcommands: [
            XcodeBuildCommand.self,
            ServeCommand.self,
            CacheCommand.self,
            ConfigCommand.self,
            TailCommand.self,
            StatsCommand.self,
            DoctorCommand.self,
        ],
        defaultSubcommand: XcodeBuildCommand.self
    )
}
