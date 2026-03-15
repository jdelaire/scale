import XCTest
@testable import S400Scale

final class S400MeasurementAggregatorTests: XCTestCase {
    func testAggregatorFinalizesWhenReferenceFieldsArrive() throws {
        let aggregator = S400MeasurementAggregator()
        let bodyComposition = BodyCompositionEstimate(
            fatFreeMassKg: 56.8,
            fatPercentage: 18.7,
            leanMassKg: 56.8
        )

        let massPacket = S400AdvertisementPacket(
            observedAt: Date(timeIntervalSince1970: 1_700_000_000),
            frameControl: 0x5948,
            packetCounter: 10,
            deviceModelID: 0x3BD5,
            deviceID: "8C:D0:B2:F6:BE:EF",
            profileId: 1,
            weightKg: 69.9,
            impedance: 543.2,
            lowFrequencyImpedance: nil,
            heartRate: 92,
            rawServiceData: Data(),
            decryptedPayload: Data(),
            manufacturerData: nil,
            rssi: -60
        )

        let lowPacket = S400AdvertisementPacket(
            observedAt: Date(timeIntervalSince1970: 1_700_000_001),
            frameControl: 0x5948,
            packetCounter: 11,
            deviceModelID: 0x3BD5,
            deviceID: "8C:D0:B2:F6:BE:EF",
            profileId: 1,
            weightKg: nil,
            impedance: nil,
            lowFrequencyImpedance: 497.6,
            heartRate: nil,
            rawServiceData: Data(),
            decryptedPayload: Data(),
            manufacturerData: nil,
            rssi: -60
        )

        XCTAssertNil(aggregator.ingest(massPacket, bodyComposition: bodyComposition))
        let measurement = aggregator.ingest(lowPacket, bodyComposition: bodyComposition)

        XCTAssertNotNil(measurement)
        XCTAssertEqual(try XCTUnwrap(measurement?.weightKg), 69.9, accuracy: 0.01)
        XCTAssertEqual(try XCTUnwrap(measurement?.impedance), 543.2, accuracy: 0.01)
        XCTAssertEqual(try XCTUnwrap(measurement?.lowFrequencyImpedance), 497.6, accuracy: 0.01)
        XCTAssertEqual(measurement?.heartRate, 92)
        XCTAssertEqual(measurement?.bodyComposition, bodyComposition)
    }

    func testAggregatorFinalizesWhenHeartRateIsMissing() throws {
        let aggregator = S400MeasurementAggregator()

        let massPacket = S400AdvertisementPacket(
            observedAt: Date(timeIntervalSince1970: 1_700_000_100),
            frameControl: 0x5948,
            packetCounter: 181,
            deviceModelID: 0x30D9,
            deviceID: "8C:D0:B2:F6:BE:EF",
            profileId: 1,
            weightKg: 78.7,
            impedance: 423.9,
            lowFrequencyImpedance: nil,
            heartRate: nil,
            rawServiceData: Data(),
            decryptedPayload: Data(),
            manufacturerData: nil,
            rssi: -53
        )

        let lowPacket = S400AdvertisementPacket(
            observedAt: Date(timeIntervalSince1970: 1_700_000_101),
            frameControl: 0x5948,
            packetCounter: 182,
            deviceModelID: 0x30D9,
            deviceID: "8C:D0:B2:F6:BE:EF",
            profileId: 1,
            weightKg: nil,
            impedance: nil,
            lowFrequencyImpedance: 380.2,
            heartRate: nil,
            rawServiceData: Data(),
            decryptedPayload: Data(),
            manufacturerData: nil,
            rssi: -53
        )

        XCTAssertNil(aggregator.ingest(massPacket, bodyComposition: nil))
        let measurement = aggregator.ingest(lowPacket, bodyComposition: nil)

        XCTAssertNotNil(measurement)
        XCTAssertEqual(try XCTUnwrap(measurement?.weightKg), 78.7, accuracy: 0.01)
        XCTAssertEqual(try XCTUnwrap(measurement?.impedance), 423.9, accuracy: 0.01)
        XCTAssertEqual(try XCTUnwrap(measurement?.lowFrequencyImpedance), 380.2, accuracy: 0.01)
        XCTAssertNil(measurement?.heartRate)
    }
}
