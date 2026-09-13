import NIOCore
import NIOPosix

/// The result of attempting to bind the live cache-events socket.
package enum X8CacheEventsListenerOutcome: Sendable {
    /// The socket is bound; the task serves connections until cancelled.
    case started(Task<Void, Never>)

    /// The socket could not be claimed. The cache proxy is unaffected.
    case skipped(reason: String)
}

/// Serves live cache-traffic events as NDJSON lines on a dedicated Unix socket.
///
/// This is a second, non-Xcode-protocol endpoint: the Xcode compilation-cache
/// socket carries only the six protocol RPCs, so observability traffic never
/// shares that transport or its request/response framing. Binding this socket
/// is fail-open by design: a bind failure yields `.skipped` and leaves the
/// cache proxy fully functional, since a live tail is a diagnostic
/// convenience, not part of the cache's correctness contract. This type never
/// logs or prints; the caller decides how to surface a `.skipped` outcome.
package struct X8CacheEventsListener: Sendable {
    private typealias ServerChannel = NIOAsyncChannel<Channel, Never>

    private let broadcaster: X8CacheEventBroadcaster

    /// Creates a listener that streams events recorded by `broadcaster`.
    package init(broadcaster: X8CacheEventBroadcaster) {
        self.broadcaster = broadcaster
    }

    /// Attempts to bind `path` and returns the outcome.
    ///
    /// A path already answering as a live listener is left untouched — it
    /// belongs to another running proxy. A stale socket file left behind by a
    /// crashed process is removed and rebound. Any other bind failure is
    /// treated the same as "no listener available."
    package func start(at path: String) async -> X8CacheEventsListenerOutcome {
        guard await pathIsBindable(path) else {
            return .skipped(reason: "another listener already owns \(path)")
        }

        let server: ServerChannel
        do {
            server = try await ServerBootstrap(group: .singletonMultiThreadedEventLoopGroup)
                .bind(unixDomainSocketPath: path, cleanupExistingSocketFile: true) { channel in
                    channel.eventLoop.makeSucceededFuture(channel)
                }
        } catch {
            return .skipped(reason: "\(error)")
        }

        let broadcaster = broadcaster
        let task = Task {
            do {
                try await server.executeThenClose { connections in
                    // A structured group ties every per-connection writer to this task's
                    // lifetime: cancelling the listener cancels the group, which cancels
                    // each writer before it can be deinitialized without finishing.
                    try await withThrowingDiscardingTaskGroup { group in
                        for try await connection in connections {
                            group.addTask { await Self.serve(connection, broadcaster: broadcaster) }
                        }
                    }
                }
            } catch {
                // A closed or failed listener ends the tail feature only; the cache socket is unaffected.
            }
        }
        return .started(task)
    }

    /// Returns whether `path` is free to bind: absent, or a stale file with no live listener.
    private func pathIsBindable(_ path: String) async -> Bool {
        do {
            let probe = try await ClientBootstrap(group: .singletonMultiThreadedEventLoopGroup)
                .connectTimeout(.milliseconds(200))
                .connect(unixDomainSocketPath: path)
                .get()
            probe.close(promise: nil)
            return false
        } catch {
            return true
        }
    }

    /// Wraps `channel` into a writer and immediately consumes it.
    ///
    /// The wrap happens here, not in the `ServerBootstrap` child channel
    /// initializer, so a writer is never constructed until this call is
    /// already committed to `executeThenClose`. A writer built earlier and
    /// buffered in the accept stream can be dropped by listener cancellation
    /// before this function ever runs, and `NIOAsyncChannel` traps if its
    /// writer is deinitialized without `finish()` — which only
    /// `executeThenClose` guarantees.
    private static func serve(
        _ channel: Channel,
        broadcaster: X8CacheEventBroadcaster
    ) async {
        guard let connection = try? await channel.eventLoop.submit({
            try NIOAsyncChannel<Never, ByteBuffer>(
                wrappingChannelSynchronously: channel,
                configuration: .init(inboundType: Never.self, outboundType: ByteBuffer.self)
            )
        }).get() else {
            return
        }
        let events = await broadcaster.subscribe()
        try? await connection.executeThenClose { _, outbound in
            for await event in events {
                try Task.checkCancellation()
                var buffer = channel.allocator.buffer(capacity: 256)
                buffer.writeString(X8CacheEventLine.line(for: event))
                buffer.writeString("\n")
                try await outbound.write(buffer)
            }
        }
    }
}
