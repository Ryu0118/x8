#if X8_S3
    import Foundation
    import X8Storage

    /// Reads cache objects through unsigned GETs of `publicReadURL + key`.
    ///
    /// A 404 is the only status treated as a miss here; every other non-200
    /// response is thrown so a permission problem never looks like an empty
    /// cache.
    package struct S3PublicURLObjectReader: S3ObjectReader {
        private let baseURL: URL
        private let transport: any S3PublicHTTPTransport
        private let semaphore: AsyncSemaphore

        /// Creates a reader for one public URL prefix ending in `/`.
        package init(
            baseURL: URL,
            transport: any S3PublicHTTPTransport,
            maximumConcurrentOperations: Int
        ) {
            self.baseURL = baseURL
            self.transport = transport
            semaphore = AsyncSemaphore(limit: maximumConcurrentOperations)
        }

        /// Returns the streamed object, `nil` for a 404, or throws for anything else.
        package func get(key: String, kind _: CacheObjectKind) async throws -> ByteStream? {
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
                try await ByteStreamSupport.discard(response.body)
                throw S3PublicReadError.accessDenied(key: key, reason: "anonymous reads are not permitted")
            default:
                try await ByteStreamSupport.discard(response.body)
                throw S3PublicReadError.unexpectedStatus(key: key, status: response.status)
            }
        }
    }
#endif
