import NIOCore
import NIOPosix

/// Connects to a running ``X8CacheEventsListener`` and streams its NDJSON lines.
///
/// This is the client half of the live cache-events socket. It performs no
/// parsing or presentation: each element is one newline-free NDJSON line
/// exactly as written by the listener, so a frontend decides how to render it.
package struct X8CacheEventsTailClient: Sendable {
    /// Creates a tail client. Connection happens per call to `connect(to:)`.
    package init() {}

    /// Connects to `path` and returns a stream of NDJSON lines.
    ///
    /// - Throws: If the socket does not exist or refuses the connection.
    package func connect(to path: String) async throws -> AsyncThrowingStream<String, any Error> {
        let connection = try await ClientBootstrap(group: .singletonMultiThreadedEventLoopGroup)
            .connect(unixDomainSocketPath: path) { channel in
                channel.eventLoop.makeCompletedFuture {
                    try NIOAsyncChannel(
                        wrappingChannelSynchronously: channel,
                        configuration: .init(inboundType: ByteBuffer.self, outboundType: Never.self)
                    )
                }
            }

        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    try await connection.executeThenClose { inbound, _ in
                        try await Self.yieldLines(from: inbound, to: continuation)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private static func yieldLines(
        from inbound: NIOAsyncChannelInboundStream<ByteBuffer>,
        to continuation: AsyncThrowingStream<String, any Error>.Continuation
    ) async throws {
        var buffer = ByteBuffer()
        for try await chunk in inbound {
            buffer.writeImmutableBuffer(chunk)
            yieldBufferedLines(from: &buffer, to: continuation)
        }
    }

    private static func yieldBufferedLines(
        from buffer: inout ByteBuffer,
        to continuation: AsyncThrowingStream<String, any Error>.Continuation
    ) {
        while let line = buffer.readNDJSONLine() {
            continuation.yield(line)
        }
    }
}

private extension ByteBuffer {
    /// Removes and returns one newline-delimited line, or `nil` if none is buffered yet.
    mutating func readNDJSONLine() -> String? {
        guard let newlineIndex = readableBytesView.firstIndex(of: UInt8(ascii: "\n")) else {
            return nil
        }
        let lineLength = newlineIndex - readerIndex
        let line = readString(length: lineLength) ?? ""
        moveReaderIndex(forwardBy: 1)
        return line
    }
}
