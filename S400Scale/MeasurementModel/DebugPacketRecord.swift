import Foundation

struct DebugPacketRecord: Identifiable, Hashable {
    let id = UUID()
    let observedAt: Date
    let deviceId: String
    let deviceModelID: String
    let packetCounter: Int
    let frameControl: String
    let frequencyHz: Double?
    let weightKg: Double?
    let impedance: Double?
    let lowFrequencyImpedance: Double?
    let heartRate: Int?
    let profileId: Int?
    let rawServiceDataHex: String
    let decryptedPayloadHex: String
    let manufacturerDataHex: String?
}
