import Synchronization
@testable import X8CLI

final class CLIRecorder: Sendable {
    private let entries = Mutex<[String]>([])

    var events: [String] {
        entries.withLock { $0 }
    }

    func record(_ event: String) {
        entries.withLock { $0.append(event) }
    }

    func capturing(_ source: X8CLI) -> X8CLI {
        var cli = source
        cli.output = X8CLIOutput(
            standardOutput: { self.record("stdout:\($0)") },
            standardError: { self.record("stderr:\($0)") }
        )
        return cli
    }
}
