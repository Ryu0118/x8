/// The raw `s3.read` or `s3.write` value: a bare token or a `publicURL` map.
///
/// Decoding accepts either YAML shape for both keys and leaves validation to
/// the resolver, so an invalid path, including a public-URL write, reports
/// its key path and fix instead of a generic YAML error.
package enum X8AccessPathDocument: Codable, Equatable, Sendable {
    /// A bare value such as `api` or `none`.
    case token(String)

    /// A map form; `publicURL` is `nil` when the map omits it.
    case map(publicURL: String?)

    private enum CodingKeys: String, CodingKey {
        case publicURL
    }

    /// Decodes a scalar token or a map.
    package init(from decoder: any Decoder) throws {
        if let token = try? decoder.singleValueContainer().decode(String.self) {
            self = .token(token)
            return
        }
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self = try .map(publicURL: container.decodeIfPresent(String.self, forKey: .publicURL))
    }

    /// Encodes the same shape it was decoded from.
    package func encode(to encoder: any Encoder) throws {
        switch self {
        case let .token(token):
            var container = encoder.singleValueContainer()
            try container.encode(token)
        case let .map(publicURL):
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encodeIfPresent(publicURL, forKey: .publicURL)
        }
    }
}
