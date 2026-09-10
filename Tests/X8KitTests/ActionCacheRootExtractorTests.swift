import Foundation
import Testing
import X8Core
@testable import X8Kit
import X8Storage

@Suite("Action Cache root extraction")
struct ActionCacheRootExtractorTests {
    @Test
    func decodesReferencesFromARealCASObjectMessage() throws {
        let references = [
            CASDataID(rawValue: Data([0x01, 0x02])),
            CASDataID(rawValue: Data([0x03, 0x04])),
        ]
        var object = CompilationCacheService_Cas_V1_CASObject()
        object.references = references.map { reference in
            var wireID = CompilationCacheService_Cas_V1_CASDataID()
            wireID.id = reference.rawValue
            return wireID
        }
        let value = try ActionCacheValue(entries: ["value": object.serializedData()])

        let roots = ActionCacheRootExtractor().roots(in: value)

        #expect(roots == references)
    }

    @Test
    func returnsNilWhenTheValueEntryIsMissing() {
        let value = ActionCacheValue(entries: [:])

        #expect(ActionCacheRootExtractor().roots(in: value) == nil)
    }

    @Test
    func returnsNilWhenTheValueEntryDoesNotParseAsACASObject() {
        let value = ActionCacheValue(entries: ["value": Data([0xFF, 0xFF, 0xFF])])

        #expect(ActionCacheRootExtractor().roots(in: value) == nil)
    }

    @Test
    func returnsAnEmptyArrayWhenTheCASObjectHasNoReferences() throws {
        let object = CompilationCacheService_Cas_V1_CASObject()
        let value = try ActionCacheValue(entries: ["value": object.serializedData()])

        #expect(ActionCacheRootExtractor().roots(in: value) == [])
    }
}
