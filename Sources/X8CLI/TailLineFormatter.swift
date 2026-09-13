import Foundation
import X8Kit

/// Renders one live cache-events NDJSON line for terminal display.
enum TailLineFormatter {
    /// Returns a human-readable line, or `line` unchanged if it does not decode.
    static func render(_ line: String) -> String {
        guard let fields = try? X8CacheEventLine.decode(line) else { return line }
        let timestamp = timeFormatter.string(from: Date(timeIntervalSince1970: fields.timestamp))
        let rpc = fields.rpc ?? "-"
        let key = fields.key.map { "\($0)…" } ?? "-"
        let bytes = fields.bytes > 0 ? "\(fields.bytes)B" : "-"
        let latency = String(format: "%.0fms", fields.latencyMs)
        return "[\(timestamp)] \(fields.outcome.uppercased())  \(rpc)  \(key)  \(bytes)  \(latency)"
    }

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        formatter.timeZone = TimeZone.current
        return formatter
    }()
}
