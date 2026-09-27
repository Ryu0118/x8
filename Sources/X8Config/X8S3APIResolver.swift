import Foundation

/// Expands and validates the `s3.api` block.
enum X8S3APIResolver {
    static func resolve(
        _ document: X8S3APIDocument,
        expander: inout ScalarParameterExpander
    ) throws -> X8S3APIConfiguration {
        let bucket = try expandRequired(document.bucket, field: "s3.api.bucket", expander: &expander)
        // Path separators and dot components would escape the configured object key.
        guard !bucket.contains("/"), !bucket.contains("\\"), bucket != ".", bucket != ".." else {
            throw X8ConfigurationResolutionError.invalidField("s3.api.bucket", reason: "expected a single path component")
        }
        let region = try expander.expand(document.region ?? "us-east-1")
        guard !region.isEmpty else {
            throw X8ConfigurationResolutionError.invalidField("s3.api.region", reason: "must not be empty")
        }

        var endpoint: URL?
        if let value = document.endpoint {
            endpoint = try X8ConfigurationURLValidator.url(expander.expand(value), field: "s3.api.endpoint")
        }
        let credentials = try resolveCredentials(document.credentials, expander: &expander)

        return X8S3APIConfiguration(endpoint: endpoint, region: region, bucket: bucket, credentials: credentials)
    }

    private static func resolveCredentials(
        _ document: X8CredentialsDocument?,
        expander: inout ScalarParameterExpander
    ) throws -> X8CredentialSource {
        guard let document else {
            throw X8ConfigurationResolutionError.missingField("s3.api.credentials")
        }
        switch document.source {
        case "defaultChain":
            return try resolveDefaultChain(document)
        case "static":
            return try .static(resolveStatic(document, expander: &expander))
        case nil:
            throw X8ConfigurationResolutionError.missingField("s3.api.credentials.source")
        default:
            throw X8ConfigurationResolutionError.invalidField(
                "s3.api.credentials.source",
                reason: "expected static or defaultChain"
            )
        }
    }

    private static func resolveDefaultChain(_ document: X8CredentialsDocument) throws -> X8CredentialSource {
        guard document.accessKeyID == nil, document.secretAccessKey == nil, document.sessionToken == nil else {
            throw X8ConfigurationResolutionError.defaultChainWithStaticFields
        }
        return .defaultChain
    }

    private static func resolveStatic(
        _ document: X8CredentialsDocument,
        expander: inout ScalarParameterExpander
    ) throws -> RemoteCacheCredentials {
        guard let accessKeyID = document.accessKeyID, let secretAccessKey = document.secretAccessKey else {
            throw X8ConfigurationResolutionError.incompleteCredentials
        }
        let accessKey = try expander.expand(accessKeyID)
        let secretKey = try expander.expand(secretAccessKey)
        guard !accessKey.isEmpty, !secretKey.isEmpty else {
            throw X8ConfigurationResolutionError.invalidField(
                "s3.api.credentials",
                reason: "accessKeyID and secretAccessKey must not expand to empty values"
            )
        }
        var sessionToken: String?
        if let value = document.sessionToken {
            sessionToken = try expander.expand(value)
        }

        return RemoteCacheCredentials(
            accessKeyID: accessKey,
            secretAccessKey: secretKey,
            sessionToken: sessionToken?.isEmpty == true ? nil : sessionToken
        )
    }

    private static func expandRequired(
        _ value: String?,
        field: String,
        expander: inout ScalarParameterExpander
    ) throws -> String {
        guard let value else {
            throw X8ConfigurationResolutionError.missingField(field)
        }
        let expanded = try expander.expand(value)
        guard !expanded.isEmpty else {
            throw X8ConfigurationResolutionError.invalidField(field, reason: "must not be empty")
        }
        return expanded
    }
}
