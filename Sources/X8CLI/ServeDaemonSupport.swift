import Foundation

/// Rotates a detached `x8 serve` process's log file by one generation.
enum ServeDaemonSupport {
    /// Moves an existing log file to `<path>.1`, replacing any prior rotation.
    ///
    /// A missing log file is not an error: it means no detached process has
    /// ever written to this profile's log, so there is nothing to rotate.
    static func rotateLog(at logFileURL: URL, fileManager: FileManager = .default) throws {
        guard fileManager.fileExists(atPath: logFileURL.path) else { return }
        let rotatedURL = logFileURL.appendingPathExtension("1")
        if fileManager.fileExists(atPath: rotatedURL.path) {
            _ = try fileManager.replaceItemAt(rotatedURL, withItemAt: logFileURL)
        } else {
            try fileManager.moveItem(at: logFileURL, to: rotatedURL)
        }
    }
}
