import Foundation
import Testing
import X8Config

@Suite("Cache role permissions preserve configuration names")
struct CacheRoleTests {
    @Test
    func combinesIndependentPermissions() {
        let role: CacheRole = [.producer, .consumer]

        #expect(role == .both)
        #expect(role.contains(.producer))
        #expect(role.contains(.consumer))
        #expect(!CacheRole.producer.contains(.consumer))
        #expect(!CacheRole.consumer.contains(.producer))
        #expect(role.subtracting(.producer) == .consumer)
    }

    @Test(arguments: ["producer", "consumer", "both"])
    func preservesConfigurationSpelling(name: String) throws {
        let data = Data("\"\(name)\"".utf8)
        let role = try JSONDecoder().decode(CacheRole.self, from: data)

        #expect(try JSONEncoder().encode(role) == data)
        #expect(X8ConfigurationPresentation.render(
            X8Configuration(bucket: "cache", role: role)
        ).contains("role=\(name)"))
    }

    @Test(arguments: ["\"bogus\"", "\"\"", "3", "[\"producer\",\"consumer\"]"])
    func rejectsUnsupportedConfiguration(json: String) {
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(CacheRole.self, from: Data(json.utf8))
        }
    }

    @Test(arguments: [CacheRole(), CacheRole(rawValue: 4), CacheRole(rawValue: 7)])
    func rejectsEncodingUnrepresentablePermissions(role: CacheRole) {
        #expect(throws: EncodingError.self) {
            try JSONEncoder().encode(role)
        }
    }
}
