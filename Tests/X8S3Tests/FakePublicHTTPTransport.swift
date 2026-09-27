#if X8_S3
    import Foundation
    @testable import X8S3

    /// Serves canned unsigned responses by URL and records every request.
    actor FakePublicHTTPTransport: S3PublicHTTPTransport {
        private var responses: [String: (status: Int, body: Data)] = [:]
        private(set) var requestedURLs: [String] = []

        func respond(to url: String, status: Int, body: Data = Data()) {
            responses[url] = (status, body)
        }

        func get(_ url: URL) async throws -> S3PublicHTTPResponse {
            requestedURLs.append(url.absoluteString)
            let response = responses[url.absoluteString] ?? (404, Data())
            return S3PublicHTTPResponse(
                status: response.status,
                body: TestByteStream.make([response.body])
            )
        }
    }
#endif
