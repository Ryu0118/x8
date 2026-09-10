import Darwin

private enum X8LaunchdSocketAPI {
    /// `launch_activate_socket` is a macOS launchd ABI entry point with no Swift
    /// module declaration. Keep the unsafe binding private to this file.
    @_silgen_name("launch_activate_socket")
    static func activate(
        _ name: UnsafePointer<CChar>,
        _ descriptors: UnsafeMutablePointer<UnsafeMutablePointer<Int32>?>,
        _ count: UnsafeMutablePointer<Int>
    ) -> Int32
}

/// Errors raised while adopting a launchd socket entry.
public enum X8LaunchdSocketActivationError: Error, Equatable, Sendable, CustomStringConvertible {
    /// launchd rejected the activation request with a POSIX error code.
    case activationFailed(Int32)

    /// The socket entry did not provide exactly one listener.
    case unexpectedDescriptorCount(Int)

    /// A diagnostic description suitable for command-line output.
    public var description: String {
        switch self {
        case let .activationFailed(code):
            "launchd socket activation failed with POSIX error \(code)."
        case let .unexpectedDescriptorCount(count):
            "launchd provided \(count) socket descriptors; exactly one is required."
        }
    }
}

/// Retrieves the listener descriptor owned by one launchd `Sockets` entry.
public struct X8LaunchdSocketActivation: Sendable {
    private let socketName: String

    /// Creates an activation reader for a launchd socket entry name.
    public init(socketName: String = "Listener") {
        self.socketName = socketName
    }

    /// Consumes the launchd activation and transfers the listener to X8's gRPC server.
    ///
    /// The returned descriptor must be passed directly to
    /// `HTTP2ServerTransport.Posix`; gRPC takes ownership of it. Calling this
    /// method outside a launchd-managed process returns an activation error.
    public func activate() async throws -> Int {
        var descriptors: UnsafeMutablePointer<Int32>?
        var count = 0
        let result = socketName.withCString {
            X8LaunchdSocketAPI.activate($0, &descriptors, &count)
        }
        defer { free(descriptors) }

        guard result == 0 else {
            closeDescriptors(descriptors, count: count)
            throw X8LaunchdSocketActivationError.activationFailed(result)
        }
        guard let descriptors, count == 1 else {
            closeDescriptors(descriptors, count: count)
            throw X8LaunchdSocketActivationError.unexpectedDescriptorCount(count)
        }
        return Int(descriptors.pointee)
    }

    private func closeDescriptors(
        _ descriptors: UnsafeMutablePointer<Int32>?,
        count: Int
    ) {
        guard let descriptors else { return }
        for index in 0 ..< count {
            _ = close(descriptors[index])
        }
    }
}
