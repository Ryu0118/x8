import Foundation

/// How this invocation reads the cache.
package enum X8ReadPath: Equatable, Sendable {
    /// Signed GetObject through the configuration's `api`.
    case api

    /// Unsigned GET of `publicURL + key`; no credentials are resolved for it.
    case publicURL(URL)

    /// Reads are disabled and return cache misses without I/O.
    case none

    /// The public URL prefix, when reads use one.
    package var publicURL: URL? {
        guard case let .publicURL(url) = self else { return nil }
        return url
    }
}
