import ArgumentParser

struct CacheCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "cache",
        abstract: "Inspect and maintain the remote compilation cache.",
        subcommands: [CachePurgeCommand.self]
    )
}
