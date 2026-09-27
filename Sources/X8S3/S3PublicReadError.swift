#if X8_S3
    /// A public-URL read that could not be classified as a hit or a miss.
    package enum S3PublicReadError: Error, Equatable, Sendable, CustomStringConvertible {
        /// The provider answered 403 and the object could not be proven absent.
        case accessDenied(key: String, reason: String)

        /// The provider answered with a status X8 does not interpret.
        case unexpectedStatus(key: String, status: Int)

        /// The public URL prefix and key did not form a valid URL.
        case invalidObjectURL(key: String)

        /// A diagnostic that names the object key but never a credential.
        package var description: String {
            switch self {
            case let .accessDenied(key, reason):
                "Public read of \(key) was denied (HTTP 403): \(reason)"
            case let .unexpectedStatus(key, status):
                "Public read of \(key) returned unexpected HTTP \(status)."
            case let .invalidObjectURL(key):
                "The public read URL cannot address \(key)."
            }
        }
    }
#endif
