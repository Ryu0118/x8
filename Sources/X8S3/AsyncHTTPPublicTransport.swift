#if X8_S3
    import AsyncHTTPClient
    import Foundation
    import NIOCore
    import X8Storage

    /// The live unsigned transport, backed by its own AsyncHTTPClient instance.
    ///
    /// This client is deliberately separate from Soto's: it has no credential
    /// provider and never adds headers, and it does not follow redirects, so a
    /// public URL cannot bounce a request to an unexpected origin.
    package struct AsyncHTTPPublicTransport: S3PublicHTTPTransport {
        /// Bounds one GET, including streaming its body.
        private static let requestTimeout = TimeAmount.minutes(5)

        private let client: HTTPClient

        /// Creates a transport with a dedicated connection pool.
        package init(maximumConnectionsPerHost: Int) {
            var configuration = HTTPClient.Configuration(redirectConfiguration: .disallow)
            configuration.connectionPool.concurrentHTTP1ConnectionsPerHostSoftLimit = maximumConnectionsPerHost
            client = HTTPClient(eventLoopGroupProvider: .singleton, configuration: configuration)
        }

        /// Builds the header-free GET request for `url`.
        package static func request(for url: URL) -> HTTPClientRequest {
            var request = HTTPClientRequest(url: url.absoluteString)
            request.method = .GET
            return request
        }

        /// Issues an unsigned GET without buffering the body.
        package func get(_ url: URL) async throws -> S3PublicHTTPResponse {
            let response = try await client.execute(Self.request(for: url), timeout: Self.requestTimeout)
            return S3PublicHTTPResponse(
                status: Int(response.status.code),
                body: ByteStream(response.body.map { Data($0.readableBytesView) })
            )
        }

        /// Releases the connection pool.
        package func shutdown() async throws {
            try await client.shutdown()
        }

        /// Releases the connection pool from a synchronous context.
        package func syncShutdown() {
            // A deinitializer cannot report a shutdown failure; release the client best effort.
            try? client.syncShutdown()
        }
    }
#endif
