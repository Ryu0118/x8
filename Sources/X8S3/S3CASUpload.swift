#if X8_S3
    import FileManagerProtocol
    import Foundation
    import X8Storage

    /// Owns one locally staged CAS payload until its upload finishes.
    ///
    /// Staging gives the backend a replayable body after consuming the incoming
    /// stream once. The temporary directory and payload are removed when the
    /// upload object is released, and failed staging removes them immediately.
    /// This object is not a durable cache record and is never listed by the
    /// CAS namespace.
    package final class S3CASUpload: Sendable {
        /// The number of payload bytes written to the staging file.
        package let byteCount: Int64

        private let directory: URL
        private let fileURL: URL
        private let fileManager: any FileManagerProtocol

        private init(
            directory: URL,
            fileURL: URL,
            byteCount: Int64,
            fileManager: any FileManagerProtocol
        ) {
            self.directory = directory
            self.fileURL = fileURL
            self.byteCount = byteCount
            self.fileManager = fileManager
        }

        /// Consumes a payload into a private, cancellable local staging file.
        ///
        /// - Returns: An upload handle whose stream can be opened repeatedly
        ///   while the handle remains alive.
        package static func stage(
            _ stream: ByteStream,
            fileManager: any FileManagerProtocol
        ) async throws -> S3CASUpload {
            let directory = fileManager.temporaryDirectory
                .appending(path: "x8-cas-upload-\(UUID().uuidString)")
            let fileURL = directory.appending(path: "payload")
            try fileManager.createDirectory(
                at: directory,
                withIntermediateDirectories: false,
                attributes: [.posixPermissions: 0o700]
            )

            do {
                try createFile(at: fileURL, fileManager: fileManager)
                let byteCount = try await writeAndClose(stream, at: fileURL)
                return S3CASUpload(
                    directory: directory,
                    fileURL: fileURL,
                    byteCount: byteCount,
                    fileManager: fileManager
                )
            } catch {
                try? fileManager.removeItem(at: directory)
                throw error
            }
        }

        deinit {
            try? fileManager.removeItem(at: directory)
        }

        /// Returns a fresh stream over the staged payload.
        package func stream() throws -> ByteStream {
            try ByteStreamSupport.make(fileAt: fileURL, fileManager: fileManager)
        }

        private static func writeAndClose(_ stream: ByteStream, at url: URL) async throws -> Int64 {
            let file = try FileHandle(forWritingTo: url)
            do {
                let byteCount = try await ByteStreamSupport.write(stream, to: file)
                try file.close()
                return byteCount
            } catch {
                try? file.close()
                throw error
            }
        }

        private static func createFile(
            at url: URL,
            fileManager: any FileManagerProtocol
        ) throws {
            guard fileManager.createFile(
                atPath: url.path,
                contents: nil,
                attributes: [.posixPermissions: 0o600]
            ) else {
                throw CocoaError(.fileWriteUnknown, userInfo: [NSURLErrorKey: url])
            }
        }
    }
#endif
