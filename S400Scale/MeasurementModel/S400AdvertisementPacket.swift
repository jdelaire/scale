import Foundation

struct S400AdvertisementPacket: Hashable {
    let observedAt: Date
    let frameControl: UInt16
    let packetCounter: UInt8
    let deviceModelID: UInt16
    let deviceID: String
    let profileId: Int?
    let weightKg: Double?
    let impedance: Double?
    let lowFrequencyImpedance: Double?
    let heartRate: Int?
    let rawServiceData: Data
    let decryptedPayload: Data
    let manufacturerData: Data?
    let rssi: Int
}
