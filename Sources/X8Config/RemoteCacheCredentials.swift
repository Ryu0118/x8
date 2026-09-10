/// Static credentials supplied directly to an X8 remote-cache profile.
///
/// The value is configuration data only; it does not refresh credentials or
/// create a provider client. Frontends should avoid including these fields in
/// profile identifiers, logs, or user-facing diagnostics.
public struct RemoteCacheCredentials: Equatable, Sendable {
    /// The access key used to authenticate object-store requests.
    public let accessKeyID: String

    /// The secret key used to authenticate object-store requests.
    public let secretAccessKey: String

    /// The optional session token for temporary credentials.
    public let sessionToken: String?

    /// Creates credentials for a remote-cache profile.
    public init(
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
    public var description: String {
        "RemoteCacheCredentials(accessKeyID: \"\(accessKeyID)\", secretAccessKey: <redacted>, "
            + "sessionToken: \(sessionToken == nil ? "nil" : "<redacted>"))"
    }

    /// Redacts secrets the same way `description` does.
    public var debugDescription: String {
        description
    }
}
