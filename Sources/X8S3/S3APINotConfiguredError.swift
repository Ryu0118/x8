#if X8_S3
    /// An operation that needs signed S3 API access ran on a public-read-only profile.
    package struct S3APINotConfiguredError: Error, Equatable, Sendable, CustomStringConvertible {
        /// The rejected operation, such as "cache writes" or "cache administration".
        package let operation: String

        /// Creates the error for one operation.
        package init(operation: String) {
            self.operation = operation
        }

        /// Explains which configuration enables the operation.
        package var description: String {
            "\(operation) requires signed S3 API access; configure s3.api for this profile."
        }
    }
#endif
