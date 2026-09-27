#if X8_S3
    import Foundation
    import X8Storage

    /// One unsigned HTTP response whose body has not been consumed yet.
    package struct S3PublicHTTPResponse: Sendable {
        /// The HTTP status code.
        package let status: Int

        /// The lazily streamed response body.
        package let body: ByteStream

        /// Creates a response.
        package init(status: Int, body: ByteStream) {
            self.status = status
            self.body = body
        }
    }

    /// Performs unsigned GET requests against public object URLs.
    ///
    /// Implementations must never attach credentials or signing headers;
    /// the live transport has no credential source at all.
    package protocol S3PublicHTTPTransport: Sendable {
        /// Issues an unsigned GET and returns once the response head arrives.
        func get(_ url: URL) async throws -> S3PublicHTTPResponse
    }
#endif
