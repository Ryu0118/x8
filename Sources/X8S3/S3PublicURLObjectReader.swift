#if X8_S3
    import Foundation
    import X8Storage

    /// Reads cache objects through unsigned GETs of `publicReadURL + key`.
    ///
    /// A 404 is a miss. A 403 is a miss only when the body is an S3
    /// `AccessDenied` error and `S3PublicReadVerifier` has proven anonymous
    /// read access to that namespace; every other non-200 response is thrown
    /// so a permission problem never looks like an empty cache.
    package struct S3PublicURLObjectReader: S3ObjectReader {
        /// Bounds how much of a 403 body is inspected; S3 error documents are tiny.
        private static let maximumErrorBodyBytes = 64 * 1024

        private let baseURL: URL
        private let transport: any S3PublicHTTPTransport
        private let verifier: S3PublicReadVerifier
        private let semaphore: AsyncSemaphore

        /// Creates a reader for one public URL prefix ending in `/`.
        package init(
            baseURL: URL,
            transport: any S3PublicHTTPTransport,
            verifier: S3PublicReadVerifier,
            maximumConcurrentOperations: Int
        ) {
            self.baseURL = baseURL
            self.transport = transport
            self.verifier = verifier
            semaphore = AsyncSemaphore(limit: maximumConcurrentOperations)
        }

        /// Returns the streamed object, `nil` for a 404, or throws for anything else.
        package func get(key: String, kind: CacheObjectKind) async throws -> ByteStream? {
            guard let url = URL(string: baseURL.absoluteString + key) else {
                throw S3PublicReadError.invalidObjectURL(key: key)
            }
            let response = try await semaphore.withPermit { try await transport.get(url) }

            switch response.status {
            case 200:
                return response.body
            case 404:
                try await ByteStreamSupport.discard(response.body)
                return nil
            case 403:
                try await classifyForbidden(response.body, key: key, kind: kind)
                return nil
            default:
                try await ByteStreamSupport.discard(response.body)
                throw S3PublicReadError.unexpectedStatus(key: key, status: response.status)
            }
        }

        /// Returns when a 403 is a proven miss and throws otherwise.
        private func classifyForbidden(_ body: ByteStream, key: String, kind: CacheObjectKind) async throws {
            let (prefix, _, remainder) = try await ByteStreamSupport.collectPrefix(
                body,
                maximumBytes: Self.maximumErrorBodyBytes
            )
            try await ByteStreamSupport.discard(remainder)

            // CDN/WAF pages and other S3 error codes (such as AllAccessDisabled) are never misses.
            guard String(decoding: prefix, as: UTF8.self).contains("<Code>AccessDenied</Code>") else {
                throw S3PublicReadError.accessDenied(
                    key: key,
                    reason: "the response is not an S3 AccessDenied error"
                )
            }
            guard await verifier.isReadable(kind) else {
                throw S3PublicReadError.accessDenied(
                    key: key,
                    reason: "anonymous read access is unproven; run a writer (write: api) once to publish "
                        + "the probe object, or allow anonymous ListBucket so misses return 404"
                )
            }
        }
    }
#endif
