import ArgumentParser

/// Restricts caller-supplied identities to a single portable runtime path component.
enum X8ProfileIDValidator {
    static func validate(_ profileID: String) throws {
        let bytes = profileID.utf8
        guard (1 ... 64).contains(bytes.count), bytes.allSatisfy(isAllowed) else {
            throw ValidationError("Profile ID must contain 1–64 ASCII letters, digits, hyphens, or underscores.")
        }
    }

    private static func isAllowed(_ byte: UInt8) -> Bool {
        switch byte {
        case 65 ... 90, 97 ... 122, 48 ... 57, 45, 95:
            true
        default:
            false
        }
    }
}
