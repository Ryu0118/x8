import Foundation
import GRPCCore
import GRPCNIOTransportHTTP2

/// Performs a local wire-level self-check for the six Xcode cache RPCs.
package struct XcodeCacheProtocolProbe: Sendable {
    /// Creates a protocol probe.
    package init() {}

    /// The number of RPC methods exercised by `verify(socketPath:)`.
    package static let rpcMethodsExercised = 6

    /// Connects to a ready socket and exercises every supported RPC method.
    ///
    /// The probe uses in-memory server storage and small inline payloads. It
    /// verifies transport registration and response mapping without contacting
    /// a provider or requiring an Xcode process.
    ///
    /// - Parameter socketPath: A ready Xcode cache Unix-domain socket.
    /// - Returns: The number of RPC methods exercised.
    /// - Throws: If the socket cannot be connected to or a response has an
    ///   unexpected protocol shape.
    package func verify(socketPath: String) async throws -> Int {
        try await withGRPCClient(
            transport: HTTP2ClientTransport.Posix(
                target: .unixDomainSocket(path: socketPath),
                transportSecurity: .plaintext
            )
        ) { client in
            let cas = CompilationCacheService_Cas_V1_CASDBService.Client<HTTP2ClientTransport.Posix>(
                wrapping: client
            )
            let keyValue = CompilationCacheService_Keyvalue_V1_KeyValueDB.Client<HTTP2ClientTransport.Posix>(
                wrapping: client
            )
            let saveResponse = try await cas.save(Self.saveRequest())
            let savedID = try Self.responseID(from: saveResponse)
            try await Self.verifyLoad(cas, id: savedID)

            let putResponse = try await cas.put(Self.putRequest())
            let putID = try Self.responseID(from: putResponse)
            try await Self.verifyGet(cas, id: putID)

            let key = Data([0x31, 0x32])
            _ = try await keyValue.putValue(Self.putValueRequest(key: key))
            try await Self.verifyGetValue(keyValue, key: key)
            return Self.rpcMethodsExercised
        }
    }

    private static func saveRequest() -> CompilationCacheService_Cas_V1_CASSaveRequest {
        var request = CompilationCacheService_Cas_V1_CASSaveRequest()
        request.data.blob.contents = .data(Data([0x01, 0x02]))
        return request
    }

    private static func putRequest() -> CompilationCacheService_Cas_V1_CASPutRequest {
        var request = CompilationCacheService_Cas_V1_CASPutRequest()
        request.data.blob.contents = .data(Data([0x03, 0x04]))
        request.data.references = [wireID(Data([0x05]))]
        return request
    }

    private static func putValueRequest(
        key: Data
    ) -> CompilationCacheService_Keyvalue_V1_PutValueRequest {
        var request = CompilationCacheService_Keyvalue_V1_PutValueRequest()
        request.key = key
        request.value.entries = ["value": Data([0x06, 0x07])]
        return request
    }

    private static func verifyLoad(
        _ cas: CompilationCacheService_Cas_V1_CASDBService.Client<HTTP2ClientTransport.Posix>,
        id: CompilationCacheService_Cas_V1_CASDataID
    ) async throws {
        var request = CompilationCacheService_Cas_V1_CASLoadRequest()
        request.casID = id
        request.writeToDisk = false
        let response = try await cas.load(request)
        guard case let .data(blob) = response.contents,
              case let .data(bytes) = blob.blob.contents,
              bytes == Data([0x01, 0x02])
        else {
            throw XcodeCacheProtocolProbeError.unexpectedResponse("CAS Load")
        }
    }

    private static func verifyGet(
        _ cas: CompilationCacheService_Cas_V1_CASDBService.Client<HTTP2ClientTransport.Posix>,
        id: CompilationCacheService_Cas_V1_CASDataID
    ) async throws {
        var request = CompilationCacheService_Cas_V1_CASGetRequest()
        request.casID = id
        request.writeToDisk = false
        let response = try await cas.get(request)
        guard case let .data(object) = response.contents,
              case let .data(bytes) = object.blob.contents,
              bytes == Data([0x03, 0x04]),
              object.references.map(\.id) == [Data([0x05])]
        else {
            throw XcodeCacheProtocolProbeError.unexpectedResponse("CAS Get")
        }
    }

    private static func verifyGetValue(
        _ keyValue: CompilationCacheService_Keyvalue_V1_KeyValueDB.Client<HTTP2ClientTransport.Posix>,
        key: Data
    ) async throws {
        var request = CompilationCacheService_Keyvalue_V1_GetValueRequest()
        request.key = key
        let response = try await keyValue.getValue(request)
        guard case let .value(value) = response.contents,
              value.entries == ["value": Data([0x06, 0x07])]
        else {
            throw XcodeCacheProtocolProbeError.unexpectedResponse("GetValue")
        }
    }

    private static func responseID(
        from response: CompilationCacheService_Cas_V1_CASSaveResponse
    ) throws -> CompilationCacheService_Cas_V1_CASDataID {
        guard case let .casID(id) = response.contents else {
            throw XcodeCacheProtocolProbeError.unexpectedResponse("CAS Save")
        }
        return id
    }

    private static func responseID(
        from response: CompilationCacheService_Cas_V1_CASPutResponse
    ) throws -> CompilationCacheService_Cas_V1_CASDataID {
        guard case let .casID(id) = response.contents else {
            throw XcodeCacheProtocolProbeError.unexpectedResponse("CAS Put")
        }
        return id
    }

    private static func wireID(
        _ bytes: Data
    ) -> CompilationCacheService_Cas_V1_CASDataID {
        var id = CompilationCacheService_Cas_V1_CASDataID()
        id.id = bytes
        return id
    }
}

private enum XcodeCacheProtocolProbeError: Error, CustomStringConvertible, Sendable {
    case unexpectedResponse(String)

    var description: String {
        switch self {
        case let .unexpectedResponse(method):
            "Unexpected response from " + method + "."
        }
    }
}
