import Foundation

/// Errors raised while parsing a human-readable purge duration.
///
/// The parser accepts a compact non-negative number followed by `ms`, `s`,
/// `m`, `h`, or `d`; syntax and numeric-value failures are kept distinct for
/// frontend diagnostics.
package enum CachePurgeDurationError: Error, Equatable, Sendable, CustomStringConvertible {
    /// The input did not contain a supported number and unit.
    case invalidFormat

    /// The input represented a negative, infinite, or otherwise invalid duration.
    case invalidValue

    /// A diagnostic description suitable for CLI validation output.
    package var description: String {
        switch self {
        case .invalidFormat:
            "Duration must use a number followed by ms, s, m, h, or d."
        case .invalidValue:
            "Duration must be finite and non-negative."
        }
    }
}

/// Parses the compact duration syntax accepted by cache administration commands.
///
/// This is a pure parser. It does not apply a default, inspect cache state, or
/// decide which purge scope a duration belongs to.
package enum CachePurgeDurationParser {
    /// Parses values such as `500ms`, `30s`, `2h`, and `7d`.
    package static func parse(_ source: String) throws -> Duration {
        let units: [(suffix: String, seconds: Double)] = [
            ("ms", 0.001),
            ("s", 1),
            ("m", 60),
            ("h", 3600),
            ("d", 86400),
        ]
        guard let unit = units.first(where: { source.hasSuffix($0.suffix) }) else {
            throw CachePurgeDurationError.invalidFormat
        }
        let number = String(source.dropLast(unit.suffix.count))
        guard !number.isEmpty, let value = Double(number) else {
            throw CachePurgeDurationError.invalidFormat
        }
        let seconds = value * unit.seconds
        guard value.isFinite, value >= 0, seconds.isFinite else {
            throw CachePurgeDurationError.invalidValue
        }
        return .seconds(seconds)
    }
}
