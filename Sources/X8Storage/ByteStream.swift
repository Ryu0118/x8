import Foundation

/// A pull-driven, provider-neutral stream of byte chunks.
///
/// A stream is lazy: constructing it does not consume its source, and each
/// iterator pulls the next `Data` chunk only when requested. Producers may
/// throw their underlying I/O or transport error, and consumers are expected
/// to preserve cancellation while forwarding chunks between protocol and
/// storage boundaries.
public struct ByteStream: AsyncSequence, Sendable {
    /// The byte chunk yielded by this sequence.
    public typealias Element = Data

    /// An iterator that pulls one byte chunk at a time.
    public struct AsyncIterator: AsyncIteratorProtocol {
        private let nextElement: () async throws -> Data?

        /// Creates an iterator backed by an asynchronous next-element operation.
        package init(nextElement: @escaping () async throws -> Data?) {
            self.nextElement = nextElement
        }

        /// Returns the next chunk, or `nil` after the stream completes.
        public mutating func next() async throws -> Data? {
            try await nextElement()
        }
    }

    private let makeIterator: @Sendable () -> AsyncIterator

    /// Creates an iterator that forwards pulls to a sendable source sequence.
    ///
    /// The source is not consumed until the returned stream is iterated.
    public init<Source: AsyncSequence & Sendable>(_ source: Source) where Source.Element == Data {
        makeIterator = {
            var iterator = source.makeAsyncIterator()
            return AsyncIterator {
                try await iterator.next()
            }
        }
    }

    /// Creates a stream from a package-owned iterator factory.
    package init(makeIterator: @escaping @Sendable () -> AsyncIterator) {
        self.makeIterator = makeIterator
    }

    /// Creates a fresh iterator for this stream.
    public func makeAsyncIterator() -> AsyncIterator {
        makeIterator()
    }
}
