import FileManagerProtocol
import Foundation

/// Provides the shared stream mechanics used by package adapters.
///
/// The helpers keep payloads lazy when reading or prepending streams, and make
/// buffering explicit through `collect(_:maximumBytes:)`. File streams read in
/// bounded chunks, while `write` and `discard` preserve producer failures and
/// task cancellation. This is an implementation boundary, not a storage
/// policy or a second byte-stream abstraction.
package enum ByteStreamSupport {
    /// Errors raised while materializing a byte stream under a size limit.
    package enum Error: Swift.Error, Equatable, Sendable {
        /// The requested maximum is invalid.
        case invalidMaximumBytes

        /// The stream contained more bytes than the requested maximum.
        case exceededMaximumBytes
    }

    private static let defaultFileChunkSize = 64 * 1024

    /// Creates a stream that yields the supplied bytes and then completes.
    package static func make(_ bytes: Data) -> ByteStream {
        ByteStream {
            var emitted = false
            return ByteStream.AsyncIterator {
                guard !emitted else { return nil }
                emitted = true
                return bytes
            }
        }
    }

    /// Creates a stream whose next chunk is supplied on demand by the producer.
    package static func make(
        next: @escaping @Sendable () async throws -> Data?
    ) -> ByteStream {
        ByteStream {
            ByteStream.AsyncIterator(nextElement: next)
        }
    }

    /// Creates a stream that reads a file lazily in bounded chunks.
    package static func make(
        fileAt url: URL,
        fileManager: any FileManagerProtocol,
        chunkSize: Int = defaultFileChunkSize
    ) throws -> ByteStream {
        guard chunkSize > 0 else { throw Error.invalidMaximumBytes }
        guard fileManager.isReadableFile(atPath: url.path) else {
            throw CocoaError(.fileReadNoPermission, userInfo: [NSURLErrorKey: url])
        }

        return ByteStream {
            let reader = FileByteStreamReader(url: url, chunkSize: chunkSize)
            return ByteStream.AsyncIterator {
                try await reader.next()
            }
        }
    }

    /// Prepends a single chunk without starting a buffering producer.
    package static func prepend(_ prefix: Data, to stream: ByteStream) -> ByteStream {
        guard !prefix.isEmpty else { return stream }

        return ByteStream {
            var prefixPending = true
            var iterator = stream.makeAsyncIterator()
            return ByteStream.AsyncIterator {
                if prefixPending {
                    prefixPending = false
                    return prefix
                }
                return try await iterator.next()
            }
        }
    }

    /// Returns a lazy stream that observes each chunk without buffering it.
    ///
    /// The observer runs after a chunk has been pulled and before it is passed
    /// to the consumer. It is used for transfer accounting at protocol
    /// boundaries while preserving back-pressure and cancellation.
    package static func observing(
        _ stream: ByteStream,
        onChunk: @escaping @Sendable (Int) async -> Void
    ) -> ByteStream {
        ByteStream {
            var iterator = stream.makeAsyncIterator()
            return ByteStream.AsyncIterator {
                guard let chunk = try await iterator.next() else { return nil }
                await onChunk(chunk.count)
                return chunk
            }
        }
    }

    /// Collects a stream while preserving cancellation and producer failures.
    package static func collect(
        _ stream: ByteStream,
        maximumBytes: Int = .max
    ) async throws -> Data {
        guard maximumBytes >= 0 else { throw Error.invalidMaximumBytes }

        var bytes = Data()
        for try await chunk in stream {
            try Task.checkCancellation()
            try validateCapacity(
                for: chunk,
                currentCount: bytes.count,
                maximumBytes: maximumBytes
            )
            bytes.append(contentsOf: chunk)
        }
        try Task.checkCancellation()
        return bytes
    }

    /// Buffers up to `maximumBytes`, then reports whether more data remains.
    ///
    /// Unlike `collect(_:maximumBytes:)`, this never throws for an oversized
    /// stream: the source is single-pass and already partially drained by the
    /// time a size limit is known to be exceeded, so callers that need to
    /// recover the unread remainder must receive it rather than lose it to a
    /// thrown error. When `exceededLimit` is `true`, `remainder` yields the
    /// unread bytes reconstructed with `prepend(_:to:)`; when `false`,
    /// `remainder` is an empty, already-completed stream.
    package static func collectPrefix(
        _ stream: ByteStream,
        maximumBytes: Int
    ) async throws -> (prefix: Data, exceededLimit: Bool, remainder: ByteStream) {
        guard maximumBytes >= 0 else { throw Error.invalidMaximumBytes }

        var iterator = stream.makeAsyncIterator()
        var prefix = Data()
        var carried: Data?
        while carried == nil, let chunk = try await iterator.next() {
            try Task.checkCancellation()
            carried = appendWithinLimit(chunk, to: &prefix, maximumBytes: maximumBytes)
        }
        guard let carried else {
            try Task.checkCancellation()
            return (prefix, false, make(Data()))
        }
        return (prefix, true, collectPrefixRemainder(carrying: carried, iterator: iterator))
    }

    /// Writes a stream to an open file and returns the number of bytes written.
    package static func write(_ stream: ByteStream, to file: FileHandle) async throws -> Int64 {
        var byteCount: Int64 = 0
        for try await chunk in stream {
            try Task.checkCancellation()
            byteCount = try nextByteCount(after: byteCount, adding: chunk.count)
            try file.write(contentsOf: chunk)
        }
        return byteCount
    }

    /// Consumes a stream without retaining its bytes.
    package static func discard(_ stream: ByteStream) async throws {
        for try await _ in stream {
            try Task.checkCancellation()
        }
        try Task.checkCancellation()
    }

    /// Appends as much of `chunk` as fits under `maximumBytes` and returns the
    /// unread suffix, or `nil` when the whole chunk fit.
    private static func appendWithinLimit(
        _ chunk: Data,
        to prefix: inout Data,
        maximumBytes: Int
    ) -> Data? {
        guard let split = collectPrefixSplit(chunk, currentCount: prefix.count, maximumBytes: maximumBytes) else {
            prefix.append(contentsOf: chunk)
            return nil
        }
        prefix.append(contentsOf: split.kept)
        return split.carried
    }

    private static func validateCapacity(
        for chunk: Data,
        currentCount: Int,
        maximumBytes: Int
    ) throws {
        guard chunk.count <= maximumBytes - currentCount else {
            throw Error.exceededMaximumBytes
        }
    }

    private static func nextByteCount(after current: Int64, adding count: Int) throws -> Int64 {
        let (next, overflow) = current.addingReportingOverflow(Int64(count))
        guard !overflow else { throw CocoaError(.fileWriteOutOfSpace) }
        return next
    }

    /// Splits `chunk` at the point where `currentCount` would exceed `maximumBytes`, or
    /// returns `nil` when the whole chunk still fits.
    private static func collectPrefixSplit(
        _ chunk: Data,
        currentCount: Int,
        maximumBytes: Int
    ) -> (kept: Data, carried: Data)? {
        let overflow = chunk.count - (maximumBytes - currentCount)
        guard overflow > 0 else { return nil }
        return (Data(chunk.prefix(chunk.count - overflow)), Data(chunk.suffix(overflow)))
    }

    /// Rebuilds the unread remainder as a stream once `collectPrefix` stops buffering.
    private static func collectPrefixRemainder(
        carrying carried: Data,
        iterator: ByteStream.AsyncIterator
    ) -> ByteStream {
        let iteratorBox = StreamIteratorBox(iterator: iterator)
        let rest = make { try await iteratorBox.next() }
        return prepend(carried, to: rest)
    }
}

/// Owns a non-`Sendable` iterator so it can be captured by a `@Sendable` closure.
///
/// `collectPrefix(_:maximumBytes:)` hands its provider iterator to a new
/// stream's closure after partially draining it; the box is the only
/// consumer of that iterator afterward, so serialized access through it is
/// safe despite the iterator itself not being `Sendable`.
private final class StreamIteratorBox: @unchecked Sendable {
    private var iterator: ByteStream.AsyncIterator

    init(iterator: ByteStream.AsyncIterator) {
        self.iterator = iterator
    }

    func next() async throws -> Data? {
        try Task.checkCancellation()
        return try await iterator.next()
    }
}

/// Owns one lazy file reader for the lifetime of a `ByteStream` iterator.
///
/// The handle is opened on the first read, closed immediately at EOF, and
/// closed again during deinitialization for cancellation or abandoned
/// iterators. The class is intentionally iterator-local because its mutable
/// file position must not be shared by independent streams.
private final class FileByteStreamReader: @unchecked Sendable {
    private let url: URL
    private let chunkSize: Int
    private var file: FileHandle?
    private var reachedEnd = false

    init(url: URL, chunkSize: Int) {
        self.url = url
        self.chunkSize = chunkSize
    }

    deinit {
        // An abandoned or cancelled stream still needs to release its descriptor.
        try? file?.close()
    }

    func next() async throws -> Data? {
        try Task.checkCancellation()
        guard !reachedEnd else { return nil }
        let file = try openFileIfNeeded()
        guard let chunk = try file.read(upToCount: chunkSize), !chunk.isEmpty else {
            reachedEnd = true
            try file.close()
            self.file = nil
            return nil
        }
        return chunk
    }

    private func openFileIfNeeded() throws -> FileHandle {
        if let file {
            return file
        }
        let file = try FileHandle(forReadingFrom: url)
        self.file = file
        return file
    }
}
