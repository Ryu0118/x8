/// Overlays an optional local document onto a base raw configuration.
///
/// Scalars set in the local document replace the base; `nil` inherits it.
/// `s3.read`, `s3.write`, and `s3.api.credentials` are replaced whole rather
/// than merged field by field, so switching a path or credential source never
/// leaves fields from the other choice behind. This type performs no decoding
/// or validation, so the merged result remains a raw document.
enum X8ConfigurationMerger {
    static func merge(
        _ base: X8ConfigurationDocument,
        _ override: X8ConfigurationDocument?
    ) -> X8ConfigurationDocument {
        guard let override else { return base }

        return X8ConfigurationDocument(
            version: override.version ?? base.version,
            s3: merge(base.s3, override.s3),
            socketPath: override.socketPath ?? base.socketPath
        )
    }

    private static func merge(_ base: X8S3Document?, _ override: X8S3Document?) -> X8S3Document? {
        guard let base, let override else { return override ?? base }

        return X8S3Document(
            api: merge(base.api, override.api),
            read: override.read ?? base.read,
            write: override.write ?? base.write
        )
    }

    private static func merge(_ base: X8S3APIDocument?, _ override: X8S3APIDocument?) -> X8S3APIDocument? {
        guard let base, let override else { return override ?? base }

        return X8S3APIDocument(
            endpoint: override.endpoint ?? base.endpoint,
            region: override.region ?? base.region,
            bucket: override.bucket ?? base.bucket,
            credentials: override.credentials ?? base.credentials
        )
    }
}
