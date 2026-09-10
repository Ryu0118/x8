import Foundation

/// Separates command data from diagnostics without changing process-global streams.
struct X8CLIOutput: Sendable {
    let standardOutput: @Sendable (String) -> Void
    let standardError: @Sendable (String) -> Void

    static let live = Self(
        standardOutput: { FileHandle.standardOutput.write(Data(($0 + "\n").utf8)) },
        standardError: { FileHandle.standardError.write(Data(($0 + "\n").utf8)) }
    )
}
