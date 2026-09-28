#if X8_S3
    import Foundation
    import X8Core
    import X8S3
    import X8Storage

    @main
    struct X8S3ProcessIntegrationWorker {
        static func main() async throws {
            let arguments = Array(CommandLine.arguments.dropFirst())
            guard let operation = arguments.first else {
                throw WorkerError.invalidArguments
            }

            switch operation {
            case "write":
                try await write(arguments.dropFirst())
            case "verify":
                try await verify(arguments.dropFirst())
            case "cleanup":
                try await cleanup(arguments.dropFirst())
            default:
                throw WorkerError.invalidArguments
            }
        }

        private static func write(
            _ arguments: ArraySlice<String>
        ) async throws {
            let configuration = try Runtime.configuration(arguments)
            try await withStorage(configuration) { storage in
                let reference = CASDataID(rawValue: Data([0x10, 0x11]))
                let object = CASObject(
                    bytes: makeStream([Data([0x20]), Data([0x21])]),
                    references: [reference]
                )
                let objectID = try await storage.put(object)
                let blobID = try await storage.save(
                    makeStream([Data([0x30]), Data([0x31])])
                )
                let actionKey = ActionCacheKey(rawValue: Data([0x40, 0x41]))
                let actionValue = ActionCacheValue(entries: [
                    "value": Data([0x50, 0x51]),
                    "metadata": Data([0x60]),
                ])
                try await storage.putValue(actionValue, for: actionKey)

                WorkerOutput.writeLine("object_id=" + objectID.rawValue.base64EncodedString())
                WorkerOutput.writeLine("blob_id=" + blobID.rawValue.base64EncodedString())
                WorkerOutput.writeLine("action_key=" + actionKey.rawValue.base64EncodedString())
            }
        }

        private static func verify(
            _ arguments: ArraySlice<String>
        ) async throws {
            let values = try Runtime.verification(arguments)
            try await withStorage(values.configuration) { storage in
                let object = try await storage.get(id: values.objectID)
                guard let object else { throw WorkerError.recordMissing("CAS object") }
                guard object.references == [values.reference] else {
                    throw WorkerError.recordMismatch("CAS references")
                }
                guard try await collect(object.bytes) == Data([0x20, 0x21]) else {
                    throw WorkerError.recordMismatch("CAS object bytes")
                }

                let blob = try await storage.load(id: values.blobID)
                guard let blob else { throw WorkerError.recordMissing("CAS blob") }
                guard try await collect(blob) == Data([0x30, 0x31]) else {
                    throw WorkerError.recordMismatch("CAS blob bytes")
                }

                let action = try await storage.getValue(for: values.actionKey)
                guard action == values.actionValue else {
                    throw WorkerError.recordMismatch("Action Cache value")
                }
                WorkerOutput.writeLine("verified")
            }
        }

        private static func cleanup(
            _ arguments: ArraySlice<String>
        ) async throws {
            let configuration = try Runtime.configuration(arguments)
            try await withStorage(configuration) { storage in
                for kind in CacheObjectKind.allCases {
                    let objects = try await storage.listObjects(of: kind)
                    try await delete(objects, from: storage)
                }
            }
        }

        private static func delete(
            _ objects: [CacheObject],
            from storage: S3Storage
        ) async throws {
            for object in objects {
                _ = try await storage.delete(object)
            }
        }

        private static func withStorage<Result: Sendable>(
            _ configuration: S3StorageConfiguration,
            operation: @Sendable (S3Storage) async throws -> Result
        ) async throws -> Result {
            let storage = S3Storage(configuration: configuration)
            do {
                let result = try await operation(storage)
                try await storage.shutdown()
                return result
            } catch {
                // The worker must preserve the operation failure while still attempting client cleanup.
                try? await storage.shutdown()
                throw error
            }
        }

        private static func makeStream(_ chunks: [Data]) -> ByteStream {
            let (stream, continuation) = AsyncThrowingStream<Data, any Error>.makeStream(
                of: Data.self
            )
            for chunk in chunks {
                continuation.yield(chunk)
            }
            continuation.finish()
            return ByteStream(stream)
        }

        private static func collect(_ stream: ByteStream) async throws -> Data {
            var data = Data()
            for try await chunk in stream {
                data.append(contentsOf: chunk)
            }
            return data
        }
    }

    private enum WorkerOutput {
        /// Writes the worker protocol to stdout; the integration test parses these lines.
        static func writeLine(_ line: String) {
            FileHandle.standardOutput.write(Data((line + "\n").utf8))
        }
    }

    private enum Runtime {
        static func configuration(
            _ arguments: ArraySlice<String>
        ) throws -> S3StorageConfiguration {
            let values = Array(arguments)
            guard values.count == 2,
                  let endpoint = URL(string: values[0])
            else {
                throw WorkerError.invalidArguments
            }
            return S3StorageConfiguration(
                bucket: values[1],
                endpoint: endpoint
            )
        }

        static func verification(
            _ arguments: ArraySlice<String>
        ) throws -> (
            configuration: S3StorageConfiguration,
            objectID: CASDataID,
            blobID: CASDataID,
            actionKey: ActionCacheKey,
            actionValue: ActionCacheValue,
            reference: CASDataID
        ) {
            let values = Array(arguments)
            guard values.count == 5,
                  let objectID = decodeID(values[2]),
                  let blobID = decodeID(values[3]),
                  let actionKey = decodeID(values[4])
            else {
                throw WorkerError.invalidArguments
            }
            let storageConfiguration = try configuration(values[0 ..< 2])
            return (
                storageConfiguration,
                CASDataID(rawValue: objectID),
                CASDataID(rawValue: blobID),
                ActionCacheKey(rawValue: actionKey),
                ActionCacheValue(entries: [
                    "value": Data([0x50, 0x51]),
                    "metadata": Data([0x60]),
                ]),
                CASDataID(rawValue: Data([0x10, 0x11]))
            )
        }

        private static func decodeID(_ value: String) -> Data? {
            Data(base64Encoded: value)
        }
    }

    private enum WorkerError: Error, CustomStringConvertible, Sendable {
        case invalidArguments
        case recordMissing(String)
        case recordMismatch(String)

        var description: String {
            switch self {
            case .invalidArguments:
                "Invalid worker arguments."
            case let .recordMissing(record):
                "Missing " + record + "."
            case let .recordMismatch(record):
                "Mismatched " + record + "."
            }
        }
    }
#else
    @main
    struct X8S3ProcessIntegrationWorker {
        static func main() {}
    }
#endif
