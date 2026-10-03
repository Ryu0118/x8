import Foundation
import Testing
import X8Core
@testable import X8Storage

@Suite("CAS reads re-derive the identifier before the payload is trusted")
struct CASDataIntegrityTests {
    private let references = [CASDataID(rawValue: Data([0x21, 0x22]))]

    @Test
    func passesMatchingPayloadThroughUnchanged() async throws {
        let chunks = [Data([0x01]), Data([0x02, 0x03])]
        let id = CASDataIDGenerator.id(for: Data([0x01, 0x02, 0x03]), references: references)

        let verified = CASDataIDGenerator.verifying(
            ByteStreamTestSupport.makeStream(from: chunks),
            references: references,
            expected: id
        )

        #expect(try await ByteStreamTestSupport.collect(verified) == Data([0x01, 0x02, 0x03]))
    }

    @Test
    func acceptsAnEmptyPayload() async throws {
        let id = CASDataIDGenerator.id(for: Data(), references: [])

        let verified = CASDataIDGenerator.verifying(
            ByteStreamTestSupport.makeStream(from: []),
            references: [],
            expected: id
        )

        #expect(try await ByteStreamTestSupport.collect(verified).isEmpty)
    }

    @Test
    func rejectsATamperedPayload() async throws {
        let id = CASDataIDGenerator.id(for: Data([0x01, 0x02]), references: references)

        let verified = CASDataIDGenerator.verifying(
            ByteStreamTestSupport.makeStream(from: [Data([0x01, 0xFF])]),
            references: references,
            expected: id
        )

        await #expect(throws: CASDataIntegrityError(id: id)) {
            _ = try await ByteStreamTestSupport.collect(verified)
        }
    }

    @Test
    func rejectsTamperedReferences() async throws {
        let id = CASDataIDGenerator.id(for: Data([0x01]), references: references)

        let verified = CASDataIDGenerator.verifying(
            ByteStreamTestSupport.makeStream(from: [Data([0x01])]),
            references: [CASDataID(rawValue: Data([0x99]))],
            expected: id
        )

        await #expect(throws: CASDataIntegrityError(id: id)) {
            _ = try await ByteStreamTestSupport.collect(verified)
        }
    }

    @Test
    func describesTheFailingIdentifierInHex() {
        let error = CASDataIntegrityError(id: CASDataID(rawValue: Data([0x0A, 0xFF])))

        #expect(error.description.hasPrefix("CAS record 0aff failed integrity verification"))
    }
}
