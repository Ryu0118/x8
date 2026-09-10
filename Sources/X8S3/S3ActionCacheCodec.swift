#if X8_S3
    import Foundation
    import X8Core
    import X8Storage

    package extension S3StorageCodec {
        /// Encodes an action-cache value in key order for stable bytes.
        static func encodeActionCache(_ value: ActionCacheValue) -> Data {
            var data = actionCacheHeader
            let entries = value.entries.sorted { $0.key < $1.key }
            BigEndianUInt64.append(UInt64(entries.count), to: &data)

            for (key, value) in entries {
                let keyData = Data(key.utf8)
                BigEndianUInt64.append(UInt64(keyData.count), to: &data)
                data.append(contentsOf: keyData)
                BigEndianUInt64.append(UInt64(value.count), to: &data)
                data.append(contentsOf: value)
            }
            return data
        }

        /// Decodes an action-cache value.
        static func decodeActionCache(_ data: Data) throws -> ActionCacheValue {
            var reader = Reader(data: data)
            try reader.expect(actionCacheHeader, error: .invalidActionCacheValue)
            let entryCount = try reader.readCount(
                error: .invalidActionCacheValue,
                minimumBytesPerItem: MemoryLayout<UInt64>.size * 2
            )
            var entries: [String: Data] = [:]
            entries.reserveCapacity(entryCount)

            for _ in 0 ..< entryCount {
                let entry = try readActionCacheEntry(from: &reader)
                entries[entry.key] = entry.value
            }

            guard reader.isAtEnd else { throw S3StorageCodecError.invalidActionCacheValue }
            return ActionCacheValue(entries: entries)
        }

        private static func readActionCacheEntry(from reader: inout Reader) throws -> (key: String, value: Data) {
            let keyLength = try reader.readCount(error: .invalidActionCacheValue)
            let keyData = try reader.readBytes(count: keyLength, error: .invalidActionCacheValue)
            guard let key = String(data: keyData, encoding: .utf8) else {
                throw S3StorageCodecError.invalidActionCacheValue
            }

            let valueLength = try reader.readCount(error: .invalidActionCacheValue)
            let value = try reader.readBytes(count: valueLength, error: .invalidActionCacheValue)
            return (key, value)
        }
    }
#endif
