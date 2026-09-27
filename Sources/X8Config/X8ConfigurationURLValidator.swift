import Foundation

/// Validates the expanded endpoint and public-URL strings of `.x8.yml`.
enum X8ConfigurationURLValidator {
    /// Parses an `http(s)` URL with a host and no user info, query, or fragment.
    ///
    /// Remote URLs must use TLS; plain HTTP is limited to loopback development
    /// services. Rejecting user info and URL modifiers keeps secrets and
    /// signing data from being smuggled through configuration text.
    static func url(_ value: String, field: String, requiresTrailingSlash: Bool = false) throws -> URL {
        let reason = "expected an https URL (http only for localhost) without user info, query, or fragment"
            + (requiresTrailingSlash ? ", ending in /" : "")
        guard let url = URL(string: value),
              let scheme = url.scheme?.lowercased(),
              ["http", "https"].contains(scheme),
              url.host != nil,
              url.user == nil,
              url.password == nil,
              url.query == nil,
              url.fragment == nil,
              scheme == "https" || isLoopback(url),
              !requiresTrailingSlash || value.hasSuffix("/")
        else {
            throw X8ConfigurationResolutionError.invalidField(field, reason: reason)
        }
        return url
    }

    private static func isLoopback(_ url: URL) -> Bool {
        ["localhost", "127.0.0.1", "::1"].contains(url.host?.lowercased())
    }
}
