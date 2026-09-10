import Foundation
import Testing
@testable import X8Storage

@Suite("Big-endian integer encoding")
struct BigEndianUInt64Tests {
    @Test
    func appendsNetworkOrderBytesWithoutReplacingExistingData() {
        var data = Data([0xAA])

        BigEndianUInt64.append(0x0102_0304_0506_0708, to: &data)

        #expect(data == Data([0xAA, 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08]))
        #expect(BigEndianUInt64.decode(Data(data.dropFirst())) == 0x0102_0304_0506_0708)
    }

    @Test(arguments: [Data(), Data([0x01]), Data(repeating: 0x01, count: 9)])
    func rejectsAnythingOtherThanOneUInt64(_ data: Data) {
        #expect(BigEndianUInt64.decode(data) == nil)
    }

    @Test(arguments: [UInt64.zero, UInt64.max])
    func roundTripsBoundaryValues(_ value: UInt64) {
        var data = Data()
        BigEndianUInt64.append(value, to: &data)

        #expect(BigEndianUInt64.decode(data) == value)
    }
}
