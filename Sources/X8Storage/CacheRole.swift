/// The cache operations an invocation may perform, combined as independent permissions.
public struct CacheRole: OptionSet, Codable, Sendable {
    /// The permission bits; unknown bits grant no additional operations.
    public let rawValue: Int

    /// Permits cache writes.
    public static let producer = Self(rawValue: 1 << 0)

    /// Permits cache reads.
    public static let consumer = Self(rawValue: 1 << 1)

    /// Permits both cache writes and cache reads.
    public static let both: Self = [.producer, .consumer]

    /// Creates a permission set, including an empty set that disables reads and writes.
    public init(rawValue: Int) {
        self.rawValue = rawValue
    }

    /// Decodes the existing configuration names: `producer`, `consumer`, or `both`.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        let name = try container.decode(String.self)
        switch name {
        case "producer": self = .producer
        case "consumer": self = .consumer
        case "both": self = .both
        default:
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Expected producer, consumer, or both."
            )
        }
    }

    /// Encodes a configuration name; empty sets and unknown bits are not valid configuration values.
    public func encode(to encoder: any Encoder) throws {
        guard let configurationName else {
            throw EncodingError.invalidValue(self, .init(
                codingPath: encoder.codingPath,
                debugDescription: "Expected producer, consumer, or both."
            ))
        }
        var container = encoder.singleValueContainer()
        try container.encode(configurationName)
    }

    /// The compatible configuration spelling, absent for unsupported permission sets.
    package var configurationName: String? {
        switch self {
        case .producer: "producer"
        case .consumer: "consumer"
        case .both: "both"
        default: nil
        }
    }
}
