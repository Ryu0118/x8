import Foundation
import NIOCore
import NIOPosix
import Testing
@testable import X8Kit

@Suite("Live cache-events socket over NDJSON")
struct X8CacheEventsListenerIntegrationTests {
    @Test("streams recorded events as NDJSON lines to a connected client")
    func streamsEventsToClient() async throws {
        let path = temporarySocketPath()
        defer { try? FileManager.default.removeItem(atPath: path) }

        let broadcaster = X8CacheEventBroadcaster(wrapping: X8CacheMetricsStore())
        let outcome = await X8CacheEventsListener(broadcaster: broadcaster).start(at: path)
        guard case let .started(task) = outcome else {
            Issue.record("Expected the events socket to start.")
            return
        }
        defer { task.cancel() }

        let connection = try await ClientBootstrap(group: .singletonMultiThreadedEventLoopGroup)
            .connect(unixDomainSocketPath: path) { channel in
                channel.eventLoop.makeCompletedFuture {
                    try NIOAsyncChannel(
                        wrappingChannelSynchronously: channel,
                        configuration: .init(inboundType: ByteBuffer.self, outboundType: Never.self)
                    )
                }
            }

        // Give the server a moment to register the new subscriber before recording.
        try await Task.sleep(for: .milliseconds(50))
        await broadcaster.record(
            X8CacheMetricsEvent(
                operation: .get,
                outcome: .hit,
                byteCount: 4,
                latency: .milliseconds(1),
                rpc: "cas.get",
                keyBytes: Data([0xAB])
            )
        )

        let line: String? = try await connection.executeThenClose { inbound, _ in
            for try await buffer in inbound {
                return String(buffer: buffer)
            }
            return nil
        }

        #expect(line?.contains("\"rpc\":\"cas.get\"") == true)
        #expect(line?.hasSuffix("\n") == true)
    }

    @Test("does not start a second listener on an already-bound path")
    func skipsWhenPathIsAlreadyServing() async {
        let path = temporarySocketPath()
        defer { try? FileManager.default.removeItem(atPath: path) }

        let first = await X8CacheEventsListener(broadcaster: X8CacheEventBroadcaster(wrapping: X8CacheMetricsStore()))
            .start(at: path)
        guard case let .started(firstTask) = first else {
            Issue.record("Expected the first listener to start.")
            return
        }
        defer { firstTask.cancel() }

        let second = await X8CacheEventsListener(broadcaster: X8CacheEventBroadcaster(wrapping: X8CacheMetricsStore()))
            .start(at: path)

        guard case .skipped = second else {
            Issue.record("Expected the second listener to be skipped.")
            return
        }
    }

    @Test(
        "cancelling right after accepted connections are buffered does not trap",
        .timeLimit(.minutes(1)),
        arguments: 0 ..< 10
    )
    func cancellingWithBufferedConnectionsDoesNotTrap(_: Int) async {
        let path = temporarySocketPath()
        defer { try? FileManager.default.removeItem(atPath: path) }

        let outcome = await X8CacheEventsListener(broadcaster: X8CacheEventBroadcaster(wrapping: X8CacheMetricsStore()))
            .start(at: path)
        guard case let .started(task) = outcome else {
            Issue.record("Expected the listener to start.")
            return
        }

        // Fire every connect without awaiting any of them, so several
        // accepted child channels can still be sitting unconsumed in the
        // listener's inbound stream at the instant cancel() lands. That is
        // the window that used to trap: a writer built before this point
        // dropped without `executeThenClose` finishing it.
        let futures = (0 ..< 20).map { _ in
            ClientBootstrap(group: .singletonMultiThreadedEventLoopGroup)
                .connect(unixDomainSocketPath: path)
        }
        task.cancel()
        for future in futures {
            await closeIfConnected(future)
        }
        await task.value
    }

    private func closeIfConnected(_ future: EventLoopFuture<Channel>) async {
        guard let channel = try? await future.get() else { return }
        try? await channel.close().get()
    }

    private func temporarySocketPath() -> String {
        FileManager.default.temporaryDirectory
            .appending(path: "x8-events-\(UUID().uuidString).sock")
            .path
    }
}
