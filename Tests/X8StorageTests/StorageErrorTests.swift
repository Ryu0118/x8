import Foundation
import Testing
import X8Core
import X8Storage

@Suite("Storage errors")
struct StorageErrorTests {
    @Test
    func exposesConflictKindAndIdentifier() {
        let identifier = CASDataID(rawValue: Data([0x01, 0x02]))
        let error = StorageError(kind: .conflictingCASBlob, id: identifier)

        #expect(error.kind == .conflictingCASBlob)
        #expect(error.id == identifier)
    }
}
