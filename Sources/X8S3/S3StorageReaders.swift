#if X8_S3
    import Foundation
    import X8Storage

    extension S3StorageCodec {
        /// Reads a complete encoded value from an in-memory buffer.
        struct Reader {
            private let data: Data
            private var offset = 0

            init(data: Data) {
                self.data = data
            }

            var isAtEnd: Bool {
                offset == data.count
            }

            mutating func expect(_ expected: Data, error: S3StorageCodecError) throws {
                guard data.count - offset >= expected.count else { throw error }
                guard data.subdata(in: offset ..< (offset + expected.count)) == expected else {
                    throw error
                }
                offset += expected.count
            }

            mutating func readCount(
                error: S3StorageCodecError,
                minimumBytesPerItem: Int = 0,
                maximum: Int = .max
            ) throws -> Int {
                let bytes = try readBytes(count: MemoryLayout<UInt64>.size, error: error)
                guard let value = BigEndianUInt64.decode(bytes) else { throw error }
                guard value <= UInt64(maximum) else {
                    throw error
                }
                try validateMinimum(
                    value,
                    bytesPerItem: minimumBytesPerItem,
                    remainingBytes: data.count - offset,
                    error: error
                )
                return Int(value)
            }

            mutating func readBytes(count: Int, error: S3StorageCodecError) throws -> Data {
                guard count >= 0, offset <= data.count, count <= data.count - offset else {
                    throw error
                }
                let result = data.subdata(in: offset ..< (offset + count))
                offset += count
                return result
            }

            mutating func readRemainingBytes() -> Data {
                let result = data.subdata(in: offset ..< data.count)
                offset = data.count
                return result
            }

            private func validateMinimum(
                _ value: UInt64,
                bytesPerItem: Int,
                remainingBytes: Int,
                error: S3StorageCodecError
            ) throws {
                guard bytesPerItem > 0 else { return }
                guard value <= UInt64(remainingBytes / bytesPerItem) else {
                    throw error
                }
            }
        }

        /// Reads an envelope header while leaving the payload as a lazy stream.
        struct StreamReader {
            private var iterator: ByteStream.AsyncIterator
            private var buffer = Data()
            private var bufferOffset = 0

            init(stream: ByteStream) {
                iterator = stream.makeAsyncIterator()
            }

            mutating func expect(_ expected: Data, error: S3StorageCodecError) async throws {
                guard try await readBytes(count: expected.count, error: error) == expected else {
                    throw error
                }
            }

            mutating func readCount(
                error: S3StorageCodecError,
                maximum: Int
            ) async throws -> Int {
                let bytes = try await readBytes(
                    count: MemoryLayout<UInt64>.size,
                    error: error
                )
                guard let value = BigEndianUInt64.decode(bytes) else { throw error }
                guard value <= UInt64(maximum) else { throw error }
                return Int(value)
            }

            mutating func readBytes(count: Int, error: S3StorageCodecError) async throws -> Data {
                while availableBytes < count {
                    try await readNextChunk(error: error)
                }
                let start = buffer.index(buffer.startIndex, offsetBy: bufferOffset)
                let end = buffer.index(start, offsetBy: count)
                let result = Data(buffer[start ..< end])
                bufferOffset += count
                return result
            }

            mutating func remainder() -> ByteStream {
                let start = buffer.index(buffer.startIndex, offsetBy: bufferOffset)
                let buffered = Data(buffer[start ..< buffer.endIndex])
                // Preserve unread bytes before handing the provider iterator to the response stream.
                let iteratorBox = StreamIterator(iterator: iterator)
                let remainder = ByteStreamSupport.make {
                    try await iteratorBox.next()
                }
                return ByteStreamSupport.prepend(buffered, to: remainder)
            }

            private var availableBytes: Int {
                buffer.count - bufferOffset
            }

            private mutating func readNextChunk(error: S3StorageCodecError) async throws {
                compactBuffer()
                guard let chunk = try await iterator.next() else { throw error }
                buffer.append(contentsOf: chunk)
            }

            private mutating func compactBuffer() {
                guard bufferOffset > 0 else { return }
                // Drop consumed bytes before appending another provider chunk.
                let start = buffer.index(buffer.startIndex, offsetBy: bufferOffset)
                buffer = Data(buffer[start ..< buffer.endIndex])
                bufferOffset = 0
            }
        }

        /// Owns the non-Sendable iterator after the parser hands it to the body stream.
        /// The remainder producer is the only consumer of this box.
        final class StreamIterator: @unchecked Sendable {
            private var iterator: ByteStream.AsyncIterator

            init(iterator: ByteStream.AsyncIterator) {
                self.iterator = iterator
            }

            func next() async throws -> Data? {
                try Task.checkCancellation()
                return try await iterator.next()
            }
        }
    }
#endif
