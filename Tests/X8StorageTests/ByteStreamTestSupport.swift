import Foundation
import X8Core
import X8Storage

enum ByteStreamTestSupport {
    static func makeStream(from chunks: [Data]) -> ByteStream {
        let (stream, continuation) = AsyncThrowingStream<Data, any Error>.makeStream(
            of: Data.self,
            bufferingPolicy: .unbounded
        )

        for chunk in chunks {
            continuation.yield(chunk)
        }
        continuation.finish()
        return ByteStream(stream)
    }

    static func collect(_ stream: ByteStream) async throws -> Data {
        var data = Data()
        for try await chunk in stream {
            data.append(contentsOf: chunk)
        }
        return data
    }

    static func makeObject(
        chunks: [Data],
        references: [CASDataID]
    ) -> CASObject {
        CASObject(
            bytes: makeStream(from: chunks),
            references: references
        )
    }
}
