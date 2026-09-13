import Foundation

/// One decoded NDJSON line produced by ``X8CacheEventLine/line(for:)``.
///
/// A frontend decodes lines into this type to render them without
/// re-implementing the wire format. `key` is already the truncated display
/// prefix; it is never the full opaque identifier.
public struct X8CacheEventFields: Decodable, Sendable {
    /// Seconds since the Unix epoch when the operation completed.
    public let timestamp: Double

    /// The wire-level RPC name, or `nil` when the event did not report one.
    public let rpc: String?

    /// The operation outcome, as its raw string (`hit`, `miss`, `stored`, …).
    public let outcome: String

    /// The hex-encoded key prefix, or `nil` when the event had no key.
    public let key: String?

    /// The number of payload bytes transferred.
    public let bytes: Int64

    /// The elapsed operation time, in milliseconds.
    public let latencyMs: Double
}

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

    /// Decodes one NDJSON line produced by `line(for:)`.
    public static func decode(_ line: String) throws -> X8CacheEventFields {
        try JSONDecoder().decode(X8CacheEventFields.self, from: Data(line.utf8))
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
