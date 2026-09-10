import Darwin
import Foundation
import Logging

enum X8Logging {
    static func makeLogger(writeLine: @escaping @Sendable (String) -> Void) -> Logger {
        let colorEnabled = X8ColorPolicy.current.isEnabled
        return Logger(label: "com.ryu.x8") { _ in
            X8LogHandler(colorEnabled: colorEnabled, writeLine: writeLine)
        }
    }
}

private enum X8ColorPolicy: Sendable {
    case automatic
    case always
    case never

    static var current: Self {
        let environment = ProcessInfo.processInfo.environment

        if environment["NO_COLOR"] != nil {
            return .never
        }
        if environment["FORCE_COLOR"].map(Self.isEnabledValue) == true {
            return .always
        }
        return .automatic
    }

    var isEnabled: Bool {
        switch self {
        case .automatic:
            isatty(STDERR_FILENO) == 1
        case .always:
            true
        case .never:
            false
        }
    }

    private static func isEnabledValue(_ value: String) -> Bool {
        !value.isEmpty && value != "0"
    }
}

enum X8LogColor: UInt8, Sendable {
    case red = 31
    case green = 32
    case yellow = 33
    case blue = 34
    case cyan = 36
    case lightBlack = 90

    func applying(to message: String) -> String {
        "\u{001B}[\(rawValue)m\(message)\u{001B}[0m"
    }

    static func defaultColor(for level: Logger.Level) -> Self {
        switch level {
        case .trace, .debug:
            .lightBlack
        case .info:
            .cyan
        case .notice:
            .blue
        case .warning:
            .yellow
        case .error, .critical:
            .red
        }
    }
}

extension Logger.MetadataValue {
    static func color(_ color: X8LogColor) -> Self {
        .stringConvertible(color.rawValue)
    }
}

extension Logger.Metadata {
    static func color(_ color: X8LogColor) -> Self {
        ["color": .color(color)]
    }
}

private struct X8LogHandler: LogHandler {
    private static let writeLock = NSLock()
    private let colorEnabled: Bool
    private let writeLine: @Sendable (String) -> Void

    var logLevel: Logger.Level = .info
    var metadata = Logger.Metadata()
    var metadataProvider: Logger.MetadataProvider?

    init(
        colorEnabled: Bool,
        writeLine: @escaping @Sendable (String) -> Void
    ) {
        self.colorEnabled = colorEnabled
        self.writeLine = writeLine
    }

    subscript(metadataKey metadataKey: String) -> Logger.Metadata.Value? {
        get {
            metadata[metadataKey]
        }
        set {
            metadata[metadataKey] = newValue
        }
    }

    func log(event: LogEvent) {
        let color = color(for: event)
        let message = event.message.description
        let renderedMessage = colorEnabled
            ? color.applying(to: message)
            : message

        Self.writeLock.lock()
        defer { Self.writeLock.unlock() }
        writeLine(renderedMessage)
    }

    private func color(for event: LogEvent) -> X8LogColor {
        let effectiveMetadata = mergedMetadata(for: event)
        if let value = effectiveMetadata["color"],
           let rawValue = UInt8(value.description),
           let color = X8LogColor(rawValue: rawValue)
        {
            return color
        }
        return .defaultColor(for: event.level)
    }

    private func mergedMetadata(for event: LogEvent) -> Logger.Metadata {
        var result = metadata
        if let provided = metadataProvider?.get() {
            result.merge(provided, uniquingKeysWith: { _, provided in provided })
        }
        if let explicit = event.metadata {
            result.merge(explicit, uniquingKeysWith: { _, explicit in explicit })
        }
        return result
    }
}
