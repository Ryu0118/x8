import ArgumentParser

enum X8CommandSupport {
    static func message(for error: any Error) -> String {
        String(describing: error)
    }

    /// Reports a caller-supplied throwing operation's failure as a `ValidationError`.
    static func mapped<Result>(_ operation: () throws -> Result) throws -> Result {
        do {
            return try operation()
        } catch {
            throw ValidationError(message(for: error))
        }
    }

    static func mapped<Result>(_ operation: () async throws -> Result) async throws -> Result {
        do {
            return try await operation()
        } catch {
            throw ValidationError(message(for: error))
        }
    }
}
