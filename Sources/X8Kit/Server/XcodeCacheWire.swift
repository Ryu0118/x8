import FileManagerProtocol
import Foundation
import X8Core
import X8Storage

/// Translates generated Xcode protocol messages at the Kit storage boundary.
///
/// Incoming CAS bytes become lazy `ByteStream` values, including paths supplied
/// by Xcode. Outgoing bytes are either collected under a bounded inline limit
/// or written to the server-owned response-file store when disk output is
/// requested. The instance captures the filesystem and response-file context
/// for one CAS service, while pure identifier and error conversions remain
/// static. This type only handles wire representation and stream lifetime; it
/// does not choose a storage backend or decide cache policy.
struct XcodeCacheWire: Sendable {
    private let fileManager: any FileManagerProtocol
    private let responseFileStore: XcodeCacheResponseFileStore?

    init(
        responseFileStore: XcodeCacheResponseFileStore?,
        fileManager: any FileManagerProtocol
    ) {
        self.responseFileStore = responseFileStore
        self.fileManager = fileManager
    }

    func stream(
        from bytes: CompilationCacheService_Cas_V1_CASBytes
    ) throws -> ByteStream {
        switch bytes.contents {
        case let .data(data):
            return ByteStreamSupport.make(data)
        case let .filePath(path):
            return try fileStream(at: path)
        case nil:
            throw XcodeCacheServiceError.invalidRequest("CAS bytes must contain data or file_path.")
        }
    }

    static func id(_ id: CASDataID) -> CompilationCacheService_Cas_V1_CASDataID {
        var result = CompilationCacheService_Cas_V1_CASDataID()
        result.id = id.rawValue
        return result
    }

    func bytes(
        from stream: ByteStream,
        writeToDisk: Bool = false
    ) async throws -> CompilationCacheService_Cas_V1_CASBytes {
        var result = CompilationCacheService_Cas_V1_CASBytes()
        if writeToDisk, let responseFileStore {
            result.contents = try await .filePath(responseFileStore.write(stream))
            return result
        }

        // `write_to_disk` is only a client preference for the common case: an
        // object over the inline bound is still a cache hit and must not
        // surface as a remote error just because the client asked for inline
        // bytes. Spill to the response-file store when the inline bound is
        // exceeded, so a hit stays a hit regardless of `write_to_disk`.
        let (prefix, exceededLimit, remainder) = try await ByteStreamSupport.collectPrefix(
            stream,
            maximumBytes: XcodeCacheWire.maximumInlineResponseBytes
        )
        guard exceededLimit else {
            result.contents = .data(prefix)
            return result
        }
        guard let responseFileStore else {
            throw XcodeCacheServiceError.invalidRequest(
                "CAS object exceeds the inline response bound and no response-file store is configured."
            )
        }
        let fullStream = ByteStreamSupport.prepend(prefix, to: remainder)
        result.contents = try await .filePath(responseFileStore.write(fullStream))
        return result
    }

    func object(
        _ object: CASObject,
        writeToDisk: Bool = false
    ) async throws -> CompilationCacheService_Cas_V1_CASObject {
        var result = CompilationCacheService_Cas_V1_CASObject()
        result.blob = try await bytes(
            from: object.bytes,
            writeToDisk: writeToDisk
        )
        result.references = object.references.map(Self.id)
        return result
    }

    static func casError(_ error: any Error) -> CompilationCacheService_Cas_V1_ResponseError {
        var result = CompilationCacheService_Cas_V1_ResponseError()
        result.description_p = String(describing: error)
        return result
    }

    static func keyValueError(
        _ error: any Error
    ) -> CompilationCacheService_Keyvalue_V1_ResponseError {
        var result = CompilationCacheService_Keyvalue_V1_ResponseError()
        result.description_p = String(describing: error)
        return result
    }

    static func casGetError(
        _ error: any Error
    ) -> CompilationCacheService_Cas_V1_CASGetResponse {
        var response = CompilationCacheService_Cas_V1_CASGetResponse()
        response.outcome = .error
        response.error = casError(error)
        return response
    }

    static func casPutError(
        _ error: any Error
    ) -> CompilationCacheService_Cas_V1_CASPutResponse {
        var response = CompilationCacheService_Cas_V1_CASPutResponse()
        response.error = casError(error)
        return response
    }

    static func casLoadError(
        _ error: any Error
    ) -> CompilationCacheService_Cas_V1_CASLoadResponse {
        var response = CompilationCacheService_Cas_V1_CASLoadResponse()
        response.outcome = .error
        response.error = casError(error)
        return response
    }

    static func casSaveError(
        _ error: any Error
    ) -> CompilationCacheService_Cas_V1_CASSaveResponse {
        var response = CompilationCacheService_Cas_V1_CASSaveResponse()
        response.error = casError(error)
        return response
    }

    static func keyValueGetError(
        _ error: any Error
    ) -> CompilationCacheService_Keyvalue_V1_GetValueResponse {
        var response = CompilationCacheService_Keyvalue_V1_GetValueResponse()
        response.outcome = .error
        response.error = keyValueError(error)
        return response
    }

    static func keyValuePutError(
        _ error: any Error
    ) -> CompilationCacheService_Keyvalue_V1_PutValueResponse {
        var response = CompilationCacheService_Keyvalue_V1_PutValueResponse()
        response.error = keyValueError(error)
        return response
    }

    static let maximumInlineResponseBytes = 64 * 1024 * 1024

    private func fileStream(at path: String) throws -> ByteStream {
        guard !path.isEmpty else {
            throw XcodeCacheServiceError.invalidRequest("CAS file_path must not be empty.")
        }
        return try ByteStreamSupport.make(
            fileAt: URL(filePath: path),
            fileManager: fileManager
        )
    }
}
