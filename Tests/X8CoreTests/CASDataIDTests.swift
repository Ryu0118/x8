import Foundation
import Testing
import X8Core

@Suite("CAS data identifiers")
struct CASDataIDTests {
    @Test
    func preservesOpaqueBytes() {
        let rawValue = Data([0x00, 0x01, 0xFE, 0xFF])
        let identifier = CASDataID(rawValue: rawValue)

        #expect(identifier.rawValue == rawValue)
    }

    @Test
    func equalityUsesExactBytes() {
        let first = CASDataID(rawValue: Data([0x01, 0x02]))
        let same = CASDataID(rawValue: Data([0x01, 0x02]))
        let different = CASDataID(rawValue: Data([0x02, 0x01]))

        #expect(first == same)
        #expect(first != different)
    }
}
