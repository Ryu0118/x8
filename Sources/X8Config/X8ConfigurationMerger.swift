/// Overlays an optional local document onto a base raw configuration.
///
/// A non-`nil` field from the local document replaces the base field; `nil`
/// inherits the base value. This type performs no decoding or validation, so
/// the merged result remains a raw document for the resolver stage.
enum X8ConfigurationMerger {
    static func merge(
        _ base: X8ConfigurationDocument,
        _ override: X8ConfigurationDocument?
    ) -> X8ConfigurationDocument {
        guard let override else { return base }

        return X8ConfigurationDocument(
            version: override.version ?? base.version,
            endpoint: override.endpoint ?? base.endpoint,
            region: override.region ?? base.region,
            bucket: override.bucket ?? base.bucket,
            role: override.role ?? base.role,
            accessKeyID: override.accessKeyID ?? base.accessKeyID,
            secretAccessKey: override.secretAccessKey ?? base.secretAccessKey,
            sessionToken: override.sessionToken ?? base.sessionToken
        )
    }
}
