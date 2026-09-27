#if X8_S3
    /// An operation that needs signed S3 API access ran on a public-read-only profile.
    package struct S3APINotConfiguredError: Error, Equatable, Sendable, CustomStringConvertible {
        /// The category of operation that was rejected.
        package enum Operation: String, Sendable {
            case writes = "Cache writes"
            case administration = "Cache administration"
            case retention = "Cache retention"
        }

        /// The rejected operation.
        package let operation: Operation

        /// Creates the error for one operation.
        package init(operation: Operation) {
            self.operation = operation
        }

        /// Explains which configuration enables the operation.
        package var description: String {
            "\(operation.rawValue) requires signed S3 API access; configure s3.api for this profile."
        }
    }
#endif
