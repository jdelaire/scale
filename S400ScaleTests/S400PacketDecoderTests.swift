import XCTest
@testable import S400Scale

final class S400PacketDecoderTests: XCTestCase {
    func testDecodesReferenceMeasurementPacket() throws {
        let decoder = try S400PacketDecoder(
            bindKeyHex: "0728974d657a4b60964c1b1677f35f7c",
            configuredMACAddress: "8C:D0:B2:F6:BE:EF"
        )

        let packet = try decoder.decode(
            serviceData: XCTUnwrap(Data.fromHex("4859d53b0abc078ff2348c844138e930220000009e538599")),
            observedAt: Date(timeIntervalSince1970: 1_700_000_000),
            manufacturerData: nil,
            rssi: -60
        )

        XCTAssertEqual(packet.deviceID, "8C:D0:B2:F6:BE:EF")
        XCTAssertEqual(packet.deviceModelID, 0x3BD5)
        XCTAssertEqual(packet.profileId, 1)
        XCTAssertEqual(try XCTUnwrap(packet.weightKg), 69.9, accuracy: 0.01)
        XCTAssertEqual(try XCTUnwrap(packet.impedance), 543.2, accuracy: 0.01)
        XCTAssertEqual(packet.lowFrequencyImpedance, nil)
        XCTAssertEqual(packet.heartRate, 92)
    }

    func testDecodesLowFrequencyImpedancePacket() throws {
        let decoder = try S400PacketDecoder(
            bindKeyHex: "0728974d657a4b60964c1b1677f35f7c",
            configuredMACAddress: "8C:D0:B2:F6:BE:EF"
        )

        let packet = try decoder.decode(
            serviceData: XCTUnwrap(Data.fromHex("4859d53b0bd6ef0b25db72785e7e2f46d6000000d8642df6")),
            observedAt: .now,
            manufacturerData: nil,
            rssi: -60
        )

        XCTAssertEqual(packet.profileId, 1)
        XCTAssertNil(packet.weightKg)
        XCTAssertNil(packet.impedance)
        XCTAssertEqual(try XCTUnwrap(packet.lowFrequencyImpedance), 497.6, accuracy: 0.01)
        XCTAssertNil(packet.heartRate)
    }
}
