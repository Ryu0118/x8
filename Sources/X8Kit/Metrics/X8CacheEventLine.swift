import Foundation

/// Renders one cache traffic event as a self-contained NDJSON line.
///
/// Every field is either a scalar or a hex-encoded byte prefix; a consumer
/// never needs to decode nested structures to render one line.
public enum X8CacheEventLine {
    /// The number of leading key bytes rendered in a line, as a display hex prefix.
    ///
    /// This truncates rather than rehashes the opaque CAS/Action Cache key,
    /// consistent with the project's rule against reinterpreting cache
    /// identifiers.
    public static let keyPrefixByteCount = 8

    /// Returns one newline-free JSON object describing `event`.
    public static func line(for event: X8CacheMetricsEvent) -> String {
        let fields: [String] = [
            "\"timestamp\":\(event.timestamp.timeIntervalSince1970)",
            "\"rpc\":\(quoted(event.rpc))",
            "\"outcome\":\"\(event.outcome.rawValue)\"",
            "\"key\":\(quoted(keyPrefix(of: event.keyBytes)))",
            "\"bytes\":\(event.byteCount)",
            "\"latencyMs\":\(String(format: "%.3f", event.latency.milliseconds))",
        ]
        return "{\(fields.joined(separator: ","))}"
    }

    private static func keyPrefix(of keyBytes: Data?) -> String? {
        guard let keyBytes, !keyBytes.isEmpty else { return nil }
        return keyBytes.prefix(keyPrefixByteCount).map { String(format: "%02x", $0) }.joined()
    }

    private static func quoted(_ value: String?) -> String {
        guard let value else { return "null" }
        let escaped = value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "\"\(escaped)\""
    }
}
