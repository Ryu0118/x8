/// Static credentials supplied directly to an X8 remote-cache profile.
///
/// The value is configuration data only; it does not refresh credentials or
/// create a provider client. Frontends should avoid including these fields in
/// profile identifiers, logs, or user-facing diagnostics.
package struct RemoteCacheCredentials: Equatable, Sendable {
    /// The access key used to authenticate object-store requests.
    package let accessKeyID: String

    /// The secret key used to authenticate object-store requests.
    package let secretAccessKey: String

    /// The optional session token for temporary credentials.
    package let sessionToken: String?

    /// Creates credentials for a remote-cache profile.
    package init(
        accessKeyID: String,
        secretAccessKey: String,
        sessionToken: String? = nil
    ) {
        self.accessKeyID = accessKeyID
        self.secretAccessKey = secretAccessKey
        self.sessionToken = sessionToken
    }
}

extension RemoteCacheCredentials: CustomStringConvertible, CustomDebugStringConvertible {
    /// Redacts `secretAccessKey` and `sessionToken`; `accessKeyID` is not a secret.
    ///
    /// This conformance closes the common `print(configuration)`/string
    /// interpolation footgun, but it is not a hard guarantee: `dump()` and
    /// direct `Mirror` reflection bypass it and still expose stored
    /// properties.
    package var description: String {
        "RemoteCacheCredentials(accessKeyID: \"\(accessKeyID)\", secretAccessKey: <redacted>, "
            + "sessionToken: \(sessionToken == nil ? "nil" : "<redacted>"))"
    }

    /// Redacts secrets the same way `description` does.
    package var debugDescription: String {
        description
    }
}
