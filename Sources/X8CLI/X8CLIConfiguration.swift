import X8Storage

/// Connects an independently resolved configuration to the shared CLI.
///
/// `Value` belongs to the caller and is passed unchanged to the storage factory.
/// Display fields must contain only information safe to print. The CLI never
/// reflects on `value`, decodes a configuration file, or discovers credentials.
public struct X8CLIConfiguration<Value: Sendable>: Sendable {
    /// The caller's validated storage construction input.
    public let value: Value
    /// A stable, non-secret identity shared by commands addressing the same cache.
    public let profileID: String
    /// The permissions applied to Xcode cache traffic, independently of identity.
    public let role: CacheRole
    /// Ordered, non-secret fields rendered as `key=value` by `config show`.
    public let displayFields: [(key: String, value: String)]
    /// A description of the authentication mechanism, never credential values.
    public let credentialSource: String
    /// A non-secret description of the cache domain used in administrative output.
    public let storageDescription: String

    /// Creates a CLI configuration without opening storage.
    ///
    /// Profile identifiers must contain 1–64 ASCII letters, digits, hyphens,
    /// or underscores so callers cannot escape the runtime directory. Include
    /// the storage kind and cache domain in the identity, but exclude secrets
    /// and access roles. Display fields are printed in the supplied order.
    public init(
        value: Value,
        profileID: String,
        role: CacheRole = .both,
        displayFields: [(key: String, value: String)] = [],
        credentialSource: String = "unspecified",
        storageDescription: String = "cache"
    ) throws {
        try X8ProfileIDValidator.validate(profileID)

        self.value = value
        self.profileID = profileID
        self.role = role
        self.displayFields = displayFields
        self.credentialSource = credentialSource
        self.storageDescription = storageDescription
    }

    func metadata() throws -> X8CLIConfiguration<Void> {
        try X8CLIConfiguration<Void>(
            value: (),
            profileID: profileID,
            role: role,
            displayFields: displayFields,
            credentialSource: credentialSource,
            storageDescription: storageDescription
        )
    }
}
